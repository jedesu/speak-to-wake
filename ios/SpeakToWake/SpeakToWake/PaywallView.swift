import StoreKit
import SwiftUI

/// Mingo Pro offer: a 7-day free trial, then monthly or yearly, bought through
/// Apple's in-app purchases (see Store.swift). Prices come from the App Store,
/// so they're shown in the user's own currency.
struct PaywallView: View {
    let onDone: () -> Void

    private enum Plan { case yearly, monthly }
    @State private var plan = Plan.yearly
    @State private var buying = false
    @State private var message: String?
    @State private var managing = false
    private var store = Store.shared

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
    }

    private var selected: Product? { plan == .yearly ? store.yearly : store.monthly }
    private var trial: Bool { store.trialEligible }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MINGO PRO")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Theme.accent)
                    Text(store.isPro ? "You're on Mingo Pro" : trial ? "Try Pro free for 7 days" : "Get Mingo Pro")
                        .font(.largeTitle.weight(.heavy))
                    Text("Your alarm picks the words you're about to forget, so every morning counts.")
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("brain.head.profile", "Spaced repetition", "The alarm and Review bring back words right before you'd forget them")
                    feature("square.stack.3d.up.fill", "Every word pack", "All levels and topics, not just the starter sections")
                    feature("chart.bar.fill", "Detailed progress", "See which words stick and which keep slipping")
                    feature("globe", "New languages as they launch", "Spanish and French are next")
                }
                .card(padding: 20)

                if store.isPro {
                    Button("Manage subscription") { managing = true }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Done") { onDone() }
                        .font(.headline)
                        .foregroundStyle(Theme.link)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    if trial { timeline }
                    plans
                    buyButton
                    Button("Continue with free") { onDone() }
                        .font(.headline)
                        .foregroundStyle(Theme.link)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }

                if let message {
                    Text(message)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                legal
            }
            .padding(24)
        }
        .background(Theme.ground)
        .manageSubscriptionsSheet(isPresented: $managing)
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
    }

    // MARK: Plans and buying

    @ViewBuilder
    private var plans: some View {
        VStack(spacing: 10) {
            planRow(.yearly, title: "Yearly", price: store.yearly.map { "\($0.displayPrice) / year" } ?? "$49.99 / year",
                    detail: monthlyEquivalent.map { "\($0) a month" } ?? "", badge: "Save 17%")
            planRow(.monthly, title: "Monthly", price: store.monthly.map { "\($0.displayPrice) / month" } ?? "$4.99 / month",
                    detail: "Cancel anytime", badge: nil)
        }
        if let error = store.loadError {
            VStack(spacing: 6) {
                Text(error).font(.footnote).foregroundStyle(Theme.muted)
                Button("Try again") { Task { await store.loadProducts() } }.font(.footnote.bold())
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The yearly price split into 12 months, in the user's currency.
    private var monthlyEquivalent: String? {
        guard let yearly = store.yearly else { return nil }
        return (yearly.price / 12).formatted(yearly.priceFormatStyle)
    }

    private var buyButton: some View {
        Button {
            guard let product = selected else { return }
            buying = true
            message = nil
            Task {
                defer { buying = false }
                do {
                    switch try await store.purchase(product) {
                    case .purchased: onDone()
                    case .pending: message = "Waiting for approval. Pro turns on as soon as it's approved."
                    case .cancelled: break
                    }
                } catch {
                    message = error.localizedDescription
                }
            }
        } label: {
            if buying {
                ProgressView().tint(.white)
            } else {
                Text(trial ? "Start my free week" : "Subscribe")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(selected == nil || buying)
        .opacity(selected == nil ? 0.5 : 1)
    }

    /// What App Review asks for on a subscription screen: price and length,
    /// auto-renewal, how to cancel, restore, terms and privacy.
    private var legal: some View {
        VStack(spacing: 10) {
            if !store.isPro {
                Text(renewalText)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button("Restore purchases") {
                    Task {
                        do {
                            try await store.restore()
                            message = store.isPro ? "Pro restored." : "No Mingo Pro subscription found for this Apple account."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
                .font(.footnote.bold())
            }
            HStack(spacing: 16) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://jedesu.github.io/speak-to-wake/privacy.html")!)
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
    }

    private var renewalText: String {
        let price = selected.map { "\($0.displayPrice) a \(plan == .yearly ? "year" : "month")" }
            ?? (plan == .yearly ? "$49.99 a year" : "$4.99 a month")
        let start = trial ? "Free for 7 days, then \(price)." : "\(price)."
        return "\(start) Renews automatically until you cancel, at least 24 hours before the period ends, in Settings > Apple Account > Subscriptions. Free keeps the speaking alarm, every challenge type and the level 1 sections, and a 7-day wake-up streak still earns a free Pro section.\(trial ? " We'll remind you 2 days before the trial ends." : "")"
    }

    // MARK: Pieces

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.chip, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    /// Today → reminder → first charge, so nobody is surprised.
    private var timeline: some View {
        HStack(alignment: .top, spacing: 0) {
            stop("Today", "Full access", filled: true)
            stop("Day 5", "Reminder", filled: false)
            stop("Day 7", selected?.displayPrice ?? (plan == .yearly ? "$49.99" : "$4.99"), filled: false)
        }
        .background(alignment: .top) {
            Rectangle().fill(Theme.toggleOff).frame(height: 2).padding(.horizontal, 50).padding(.top, 9)
        }
    }

    private func stop(_ day: String, _ detail: String, filled: Bool) -> some View {
        VStack(spacing: 6) {
            Circle()
                .fill(filled ? Theme.accent : Theme.card)
                .stroke(Theme.accent, lineWidth: 2)
                .frame(width: 20, height: 20)
            Text(day).font(.subheadline.bold())
            Text(detail).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func planRow(_ option: Plan, title: String, price: String, detail: String, badge: String?) -> some View {
        let isSelected = plan == option
        return Button {
            plan = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.off)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent, in: .capsule)
                        }
                    }
                    Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                Text(price).font(.subheadline.bold())
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(isSelected ? Theme.accent : Theme.toggleOff, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
