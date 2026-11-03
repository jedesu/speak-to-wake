import AuthenticationServices
import SwiftData
import SwiftUI
import WakeCore

/// "Save your progress": Sign in with Apple (once the paid developer account
/// exists), Google, or a sign-in link by email. Shown after the first section,
/// from Settings, and on the welcome screen.
struct SignInView: View {
    var title = "Save your progress"
    var message = "Your first section is free to try. Sign in to keep learning, save your progress and let your alarm quiz you."
    var skipTitle = "Not now"
    /// Called instead of dismissing, when this screen is a step inside another flow (onboarding).
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var working = false
    @State private var error: String?
    @State private var appleNonce = ""

    // Email code
    private enum EmailStep { case hidden, enterEmail, linkSent }
    @State private var emailStep = EmailStep.hidden
    @State private var email = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("🐼").font(.system(size: 80)).accessibilityHidden(true).padding(.top, 32)
                Text(title).font(.largeTitle.weight(.heavy)).multilineTextAlignment(.center)
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 12)

                if SupabaseConfig.appleSignInEnabled {
                    SignInWithAppleButton(.continue) { request in
                        let nonce = AuthService.shared.makeAppleNonce()
                        appleNonce = nonce.raw
                        request.requestedScopes = [.email]
                        request.nonce = nonce.hashed
                    } onCompletion: { result in
                        Task { await finishApple(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .clipShape(.capsule)
                }

                Button {
                    Task { await signInWithGoogle() }
                } label: {
                    optionLabel("Continue with Google", systemImage: "globe")
                }
                .buttonStyle(.plain)

                emailSection

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                if working { ProgressView() }

                Button(skipTitle) { finish() }
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.link)
                    .frame(minHeight: 44)
            }
            .padding(24)
            .disabled(working)
        }
        .background(Theme.ground)
        .onChange(of: AuthService.shared.isSignedIn) {
            if AuthService.shared.isSignedIn { finish() }
        }
    }

    private func optionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.title3.bold())
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(Theme.text)
        .background(Theme.card, in: .capsule)
        .overlay(Capsule().stroke(Theme.toggleOff, lineWidth: 2))
    }

    @ViewBuilder
    private var emailSection: some View {
        switch emailStep {
        case .hidden:
            Button {
                emailStep = .enterEmail
            } label: {
                optionLabel("Continue with email", systemImage: "envelope")
            }
            .buttonStyle(.plain)
        case .enterEmail:
            VStack(spacing: 10) {
                TextField("you@example.com", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .background(Theme.card, in: .capsule)
                Button("Email me a sign-in link") { Task { await sendLink() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!email.contains("@"))
            }
        case .linkSent:
            VStack(spacing: 10) {
                Image(systemName: "envelope.open.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("Check your email").font(.title3.bold())
                Text("We sent a sign-in link to \(email). Open it on this iPhone and tap Sign in. Mingo will open, signed in.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Button("Use a different email") { emailStep = .enterEmail }
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.link)
                    .frame(minHeight: 44)
            }
            .card(padding: 18)
        }
    }

    // MARK: Actions

    private func run(_ action: () async throws -> Void) async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await action()
        } catch let cancel as ASWebAuthenticationSessionError where cancel.code == .canceledLogin {
            // Closed the Google page; nothing to report.
        } catch let cancel as ASAuthorizationError where cancel.code == .canceled {
            // Closed the Apple sheet.
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func signedIn() async {
        await SyncService.shared.sync(modelContext)
        finish()
    }

    private func finish() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func signInWithGoogle() async {
        await run {
            let callback = try await webAuthenticationSession.authenticate(
                using: AuthService.shared.googleSignInURL(),
                callbackURLScheme: SupabaseConfig.callbackScheme,
                preferredBrowserSession: .shared)
            try await AuthService.shared.finishSignIn(callback: callback)
            await signedIn()
        }
    }

    private func sendLink() async {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        await run {
            try await AuthService.shared.sendEmailLink(to: address)
            email = address
            emailStep = .linkSent
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        await run {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                throw SupabaseError(message: "Apple didn't return a sign-in token.")
            }
            try await AuthService.shared.signInWithApple(idToken: token, rawNonce: appleNonce)
            await signedIn()
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
                        Text(auth.email ?? "Your account").font(.subheadline).foregroundStyle(Theme.muted)
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
        !AppSettings.hasAccountAccess && !learnedPackIDs.isEmpty && !learnedPackIDs.contains(pack.id)
    }
}
