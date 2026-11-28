import Foundation
import StoreKit
import UserNotifications

/// Mingo Pro through Apple's in-app purchases (StoreKit 2): load the two plans,
/// buy, restore, and keep `isPro` up to date when a subscription starts, renews,
/// lapses or is refunded.
///
/// Testing without a paid developer account: Xcode plays the App Store using
/// `ios/SpeakToWake/Mingo.storekit` (Product > Scheme > Edit Scheme > Run >
/// Options > StoreKit Configuration). Real charges need the products created in
/// App Store Connect with these same ids.
@Observable
final class Store {
    static let shared = Store()

    static let monthlyID = "com.jedesu.SpeakToWake.pro.monthly"
    static let yearlyID = "com.jedesu.SpeakToWake.pro.yearly"
    static let productIDs = [yearlyID, monthlyID]

    /// Saved, so the app knows on launch (before StoreKit answers) and offline.
    static let proKey = "storePro"

    private(set) var products: [Product] = []
    private(set) var isPro = UserDefaults.standard.bool(forKey: proKey)
    /// Whether this Apple account can still get the free week.
    private(set) var trialEligible = true
    private(set) var loadError: String?

    private var updates: Task<Void, Never>?

    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var monthly: Product? { products.first { $0.id == Self.monthlyID } }

    /// Call once at launch: listens for purchases made elsewhere (renewals,
    /// Ask to Buy, another device) and checks what this account owns.
    func start() async {
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    await self?.refresh()
                }
            }
        }
        await loadProducts()
        await refresh()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { Self.productIDs.firstIndex(of: $0.id)! < Self.productIDs.firstIndex(of: $1.id)! }
            loadError = products.isEmpty ? "Plans aren't available right now." : nil
            if let subscription = products.first?.subscription {
                trialEligible = await subscription.isEligibleForIntroOffer
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    enum Outcome { case purchased, cancelled, pending }

    /// Shows Apple's purchase sheet. `pending` means it needs a parent's approval (Ask to Buy).
    func purchase(_ product: Product) async throws -> Outcome {
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else { throw StoreError.unverified }
            await transaction.finish()
            await refresh()
            if transaction.offer?.type == .introductory {
                await scheduleTrialReminder(start: transaction.purchaseDate)
            }
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// "Restore purchases": asks the App Store for this account's subscriptions.
    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    /// Pro is on while any Mingo Pro subscription is active (StoreKit leaves out
    /// expired and refunded ones).
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPro = active
        UserDefaults.standard.set(active, forKey: Self.proKey)
    }

    /// The paywall promises a reminder 2 days before the free week ends.
    private func scheduleTrialReminder(start: Date) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your Mingo Pro trial ends in 2 days"
        content.body = "Keep it and do nothing, or cancel any time in Settings > Mingo > Manage subscription."
        let fireDate = start.addingTimeInterval(5 * 24 * 3600)
        guard fireDate > .now else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSinceNow, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "trialReminder", content: content, trigger: trigger))
    }
}

enum StoreError: LocalizedError {
    case unverified
    var errorDescription: String? { "The App Store couldn't confirm this purchase. Please try again." }
}
