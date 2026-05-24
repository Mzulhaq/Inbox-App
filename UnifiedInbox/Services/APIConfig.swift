import Foundation

enum APIConfig {
    private static let env = EnvFile.load(named: "API")

    static var baseURL: URL? {
        guard let raw = env["API_BASE_URL"], !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    static var isConfigured: Bool { baseURL != nil }

    static var hint: String {
        if isConfigured { return "API: \(env["API_BASE_URL"] ?? "")" }
        return "Add UnifiedInbox/Resources/API.env with API_BASE_URL (see API.env.example)."
    }
}
