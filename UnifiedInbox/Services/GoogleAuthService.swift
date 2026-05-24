import AuthenticationServices
import Foundation
import UIKit

enum GoogleConfig {
    private static var env: [String: String] {
        EnvFile.load(named: "OAuth")
    }

    static var clientID: String { env["GOOGLE_CLIENT_ID"] ?? "" }
    static var reversedClientID: String { env["GOOGLE_URL_SCHEME"] ?? "" }
    static var redirectURI: String { "\(reversedClientID):/oauthredirect" }
    static let scope = "https://www.googleapis.com/auth/gmail.readonly"

    static var isConfigured: Bool {
        !clientID.isEmpty && !reversedClientID.isEmpty
    }

    /// Helpful when debugging "not configured" in Simulator.
    static var configurationHint: String {
        if isConfigured { return "OAuth.env loaded." }
        if Bundle.main.url(forResource: "OAuth", withExtension: "env") == nil {
            return "OAuth.env is not in the app bundle. Add UnifiedInbox/Resources/OAuth.env to Copy Bundle Resources, then Clean Build (⇧⌘K) and Run."
        }
        return "OAuth.env found but GOOGLE_CLIENT_ID or GOOGLE_URL_SCHEME is missing or empty."
    }

    static var authURL: URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        return c.url!
    }
}

/// Loads `OAuth.env` from the app bundle (Copy Bundle Resources).
enum EnvFile {
    static func load(named name: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "env"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = value
            }
        }
        return result
    }
}

enum AuthError: LocalizedError {
    case notConfigured, cancelled, noCode, tokenFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            GoogleConfig.configurationHint
        case .cancelled: "Sign in cancelled."
        case .noCode: "No authorization code returned."
        case .tokenFailed: "Could not get access token. Check OAuth client ID and URL scheme in Google Cloud."
        }
    }
}

@MainActor
final class GoogleAuthService: NSObject {
    private var session: ASWebAuthenticationSession?

    var isSignedIn: Bool { KeychainStore.load() != nil }

    func signIn() async throws {
        guard GoogleConfig.isConfigured else { throw AuthError.notConfigured }

        let code = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let s = ASWebAuthenticationSession(
                url: GoogleConfig.authURL,
                callbackURLScheme: GoogleConfig.reversedClientID
            ) { url, err in
                if let err {
                    let ns = err as NSError
                    if ns.domain == ASWebAuthenticationSessionErrorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: AuthError.cancelled)
                    } else { cont.resume(throwing: err) }
                    return
                }
                guard let url,
                      let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = c.queryItems?.first(where: { $0.name == "code" })?.value else {
                    cont.resume(throwing: AuthError.noCode)
                    return
                }
                cont.resume(returning: code)
            }
            s.presentationContextProvider = self
            self.session = s
            s.start()
        }

        let tokens = try await exchangeCode(code)
        try KeychainStore.save(tokens)
    }

    func validAccessToken() async throws -> String {
        guard var tokens = KeychainStore.load() else { throw AuthError.tokenFailed }
        if let exp = tokens.expiresAt, exp > Date().addingTimeInterval(60) {
            return tokens.accessToken
        }
        guard let refresh = tokens.refreshToken else { throw AuthError.tokenFailed }
        tokens = try await refreshToken(refresh)
        try KeychainStore.save(tokens)
        return tokens.accessToken
    }

    func signOut() throws {
        try KeychainStore.delete()
    }

    private func exchangeCode(_ code: String) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody([
            "code": code,
            "client_id": GoogleConfig.clientID,
            "redirect_uri": GoogleConfig.redirectURI,
            "grant_type": "authorization_code"
        ])
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.tokenFailed }
        return try parseTokens(data)
    }

    private func refreshToken(_ refresh: String) async throws -> OAuthTokens {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formBody([
            "client_id": GoogleConfig.clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ])
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.tokenFailed }
        var tokens = try parseTokens(data)
        tokens.refreshToken = tokens.refreshToken ?? refresh
        return tokens
    }

    private func formBody(_ fields: [String: String]) -> Data {
        fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }

    private func parseTokens(_ data: Data) throws -> OAuthTokens {
        struct R: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Int? }
        let r = try JSONDecoder().decode(R.self, from: data)
        return OAuthTokens(
            accessToken: r.access_token,
            refreshToken: r.refresh_token,
            expiresAt: r.expires_in.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
