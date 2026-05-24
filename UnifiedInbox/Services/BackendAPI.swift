import Foundation

struct TokenResponse: Decodable {
    let access_token: String
}

struct FeedItemDTO: Decodable {
    let id: UUID
    let source_id: UUID
    let external_id: String
    let title: String
    let sender: String?
    let body: String?
    let url: String?
    let published_at: Date
    let is_read: Bool
    let is_muted: Bool
    let priority: Int
    let rank_category: String?
    let rank_label: String?
}

struct SourceDTO: Decodable {
    let id: UUID
    let name: String
    let type: String
    let is_enabled: Bool
    let last_synced_at: Date?
    let email: String?
}

struct SyncResultDTO: Decodable {
    let inserted: Int
    let total: Int
}

enum BackendAPIError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured: APIConfig.hint
        case .http(let code, let body): "API error \(code): \(body)"
        case .decode: "Could not read API response."
        }
    }
}

enum BackendAPI {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            let formatters = [
                ISO8601DateFormatter(),
                {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return f
                }()
            ]
            for f in formatters {
                if let date = f.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(raw)")
        }
        return d
    }()

    static func register(email: String) async throws {
        let res: TokenResponse = try await send(method: "POST", path: "/api/auth/register", json: ["email": email], auth: false)
        try BackendSessionStore.save(token: res.access_token)
    }

    static func linkGmail(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        email: String?
    ) async throws -> SourceDTO {
        var json: [String: Any] = ["access_token": accessToken]
        if let refreshToken { json["refresh_token"] = refreshToken }
        if let expiresAt { json["expires_at"] = ISO8601DateFormatter().string(from: expiresAt) }
        if let email { json["email"] = email }
        return try await send(method: "POST", path: "/api/accounts/gmail/link", json: json, auth: true)
    }

    static func syncFeed() async throws -> SyncResultDTO {
        try await send(method: "POST", path: "/api/feed/sync", json: nil, auth: true)
    }

    static func rerankFeed() async throws -> SyncResultDTO {
        try await send(method: "POST", path: "/api/feed/rerank", json: nil, auth: true)
    }

    static func fetchFeed() async throws -> [FeedItemDTO] {
        try await send(method: "GET", path: "/api/feed?limit=200", json: nil, auth: true)
    }

    static func patchItem(id: UUID, isRead: Bool) async throws {
        let _: FeedItemDTO = try await send(
            method: "PATCH",
            path: "/api/feed/\(id.uuidString)",
            json: ["is_read": isRead],
            auth: true
        )
    }

    static func unlinkGmail() async throws {
        try await sendVoid(method: "DELETE", path: "/api/accounts/gmail", auth: true)
    }

    private static func sendVoid(method: String, path: String, auth: Bool) async throws {
        guard let base = APIConfig.baseURL else { throw BackendAPIError.notConfigured }
        guard let url = URL(string: path, relativeTo: base) else { throw BackendAPIError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if auth, let token = BackendSessionStore.load() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw BackendAPIError.decode }
        if http.statusCode >= 400 {
            throw BackendAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static func send<T: Decodable>(
        method: String,
        path: String,
        json: [String: Any]?,
        auth: Bool
    ) async throws -> T {
        guard let base = APIConfig.baseURL else { throw BackendAPIError.notConfigured }
        guard let url = URL(string: path, relativeTo: base) else { throw BackendAPIError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token = BackendSessionStore.load() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw BackendAPIError.decode }
        if http.statusCode >= 400 {
            throw BackendAPIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }
}
