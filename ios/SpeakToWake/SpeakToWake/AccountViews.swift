import AuthenticationServices
import SwiftData
import SwiftUI
import WakeCore

/// "Save your progress": sign in with Google (Apple comes with the paid developer
/// account). Shown after the first section, from Settings, and on the welcome screen.
struct SignInView: View {
    var title = "Save your progress"
    var message = "Your first section is free to try. Sign in to keep learning, save your progress and let your alarm quiz you."

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🐼").font(.system(size: 88)).accessibilityHidden(true)
            Text(title).font(.largeTitle.weight(.heavy)).multilineTextAlignment(.center)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                Task { await signIn() }
            } label: {
                HStack(spacing: 10) {
                    if working { ProgressView().tint(Theme.text) } else { Image(systemName: "globe") }
                    Text("Continue with Google")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(Theme.text)
                .background(Theme.card, in: .capsule)
                .overlay(Capsule().stroke(Theme.toggleOff, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(working)
            Text("Sign in with Apple is coming soon.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button("Not now") { dismiss() }
                .font(.subheadline.bold())
                .foregroundStyle(Theme.link)
                .frame(minHeight: 44)
        }
        .padding(24)
        .background(Theme.ground)
    }

    private func signIn() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: AuthService.shared.googleSignInURL(),
                callbackURLScheme: SupabaseConfig.callbackScheme,
                preferredBrowserSession: .shared)
            try await AuthService.shared.finishSignIn(callback: callback)
            await SyncService.shared.sync(modelContext)
            dismiss()
        } catch let cancel as ASWebAuthenticationSessionError where cancel.code == .canceledLogin {
            // The user closed the sign-in page; nothing to report.
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The Account card in Settings: who's signed in, Sign out, Delete account.
struct AccountCard: View {
    private var auth = AuthService.shared
    private var sync = SyncService.shared
    @Environment(\.modelContext) private var modelContext
    @State private var signingIn = false
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if auth.isSignedIn {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in").font(.headline)
                        Text(auth.email ?? "Google account").font(.subheadline).foregroundStyle(Theme.muted)
                        if let last = sync.lastSync {
                            Text("Synced \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.fill").foregroundStyle(Theme.accent)
                }
                Button("Sync now") { Task { await sync.sync(modelContext) } }
                    .buttonStyle(ChipButtonStyle())
                Button("Sign out") { auth.signOut() }
                    .font(.headline)
                    .foregroundStyle(Theme.link)
                    .frame(minHeight: 44)
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .font(.headline)
                    .frame(minHeight: 44)
            } else {
                Text("Sign in to save your progress and learn past the first section.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Button { signingIn = true } label: { Label("Sign in", systemImage: "person.crop.circle") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if let error = error ?? sync.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $signingIn) {
            SignInView(title: "Sign in", message: "Save your progress and keep learning on any iPhone.")
        }
        .confirmationDialog("Delete your Mingo account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    do { try await auth.deleteAccount() } catch { self.error = error.localizedDescription }
                }
            }
        } message: {
            Text("This deletes your account and the progress saved with it. Progress on this iPhone stays until you delete the app.")
        }
    }
}

extension Learning {
    /// The first section is a free trial; learning more needs an account.
    static func needsSignIn(toStudy pack: Pack, learnedPackIDs: Set<String>) -> Bool {
        !AuthService.shared.isSignedIn && !learnedPackIDs.isEmpty && !learnedPackIDs.contains(pack.id)
    }
}
