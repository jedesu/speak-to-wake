import CryptoKit
import Foundation
import Security

/// Mingo's Supabase project. The publishable key is meant to ship inside apps:
/// row-level security on every table means a user can only reach their own rows.
enum SupabaseConfig {
    static let url = URL(string: "https://ryylhfyyovezxxxnqqay.supabase.co")!
    static let publishableKey = "sb_publishable_YypM0S9LmWapWM1IeoMcgQ_maweWv8E"
    /// Where Supabase sends the browser back after Google sign-in.
    static let callbackScheme = "mingo"
    static let redirect = "mingo://login-callback"
}

struct SupabaseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Signing in (Google, through Supabase), keeping the login fresh, and calling
/// the database as the signed-in user. No SDK: plain HTTPS requests.
@Observable
final class AuthService {
    static let shared = AuthService()

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
        var email: String?
    }

    private(set) var session: Session? = Keychain.loadSession()
    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }
    var userID: String? { session?.userID }

    private var codeVerifier: String?

    // MARK: Google sign-in (OAuth with PKCE)

    /// The page that starts "Continue with Google". Open it in a web authentication session.
    func googleSignInURL() -> URL {
        let verifier = Self.randomURLSafeString()
        codeVerifier = verifier
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        var parts = URLComponents(url: SupabaseConfig.url.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: SupabaseConfig.redirect),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return parts.url!
    }

    /// Finishes sign-in with the URL Supabase redirected back to (mingo://login-callback?code=…).
    func finishSignIn(callback: URL) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error_description" })?.value {
            throw SupabaseError(message: error)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, let verifier = codeVerifier else {
            throw SupabaseError(message: "Sign-in didn't finish. Please try again.")
        }
        try await token(grant: "pkce", body: ["auth_code": code, "code_verifier": verifier])
        codeVerifier = nil
    }

    func signOut() {
        session = nil
        Keychain.deleteSession()
    }

    /// Deletes the account and everything stored with it on the server.
    func deleteAccount() async throws {
        _ = try await database("rpc/delete_my_account", method: "POST", body: Data("{}".utf8))
        signOut()
    }

    // MARK: Database requests (PostgREST)

    /// Calls `rest/v1/<path>` as the signed-in user.
    @discardableResult
    func database(_ path: String, method: String = "GET", body: Data? = nil,
                  prefer: String? = nil) async throws -> Data {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: SupabaseConfig.url.absoluteString + "/rest/v1/" + path)!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        return try await Self.send(request)
    }

    // MARK: Private

    private func validAccessToken() async throws -> String {
        guard let session else { throw SupabaseError(message: "Not signed in") }
        if session.expiresAt > .now.addingTimeInterval(60) {
            return session.accessToken
        }
        try await token(grant: "refresh_token", body: ["refresh_token": session.refreshToken])
        return self.session!.accessToken
    }

    private func token(grant: String, body: [String: String]) async throws {
        struct TokenResponse: Decodable {
            struct User: Decodable { let id: String; let email: String? }
            let access_token: String
            let refresh_token: String
            let expires_in: Double
            let user: User
        }
        var request = URLRequest(url: URL(string: SupabaseConfig.url.absoluteString + "/auth/v1/token?grant_type=\(grant)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let response = try JSONDecoder().decode(TokenResponse.self, from: try await Self.send(request))
        let new = Session(accessToken: response.access_token, refreshToken: response.refresh_token,
                          expiresAt: .now.addingTimeInterval(response.expires_in),
                          userID: response.user.id, email: response.user.email)
        session = new
        Keychain.saveSession(new)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseError(message: "Server error \((response as? HTTPURLResponse)?.statusCode ?? 0): \(text.prefix(200))")
        }
        return data
    }

    private static func randomURLSafeString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// The login is kept in the Keychain, not in plain app storage.
private enum Keychain {
    private static let account = "supabase-session"
    private static let service = "com.jedesu.SpeakToWake"

    static func saveSession(_ session: AuthService.Session) {
        deleteSession()
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
                    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock, kSecValueData: data] as CFDictionary, nil)
    }

    static func loadSession() -> AuthService.Session? {
        var result: AnyObject?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                          kSecAttrAccount: account, kSecReturnData: true] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthService.Session.self, from: data)
    }

    static func deleteSession() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
}
