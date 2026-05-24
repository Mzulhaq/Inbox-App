import Foundation

enum GmailService {
    private static let maxMessages = 50

    static func fetchProfileEmail(token: String) async throws -> String {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!
        let data = try await get(url, token: token)
        struct P: Decodable { let emailAddress: String }
        return try JSONDecoder().decode(P.self, from: data).emailAddress
    }

    static func fetchInbox(token: String, afterInternalDate: Int64?) async throws -> [InboxItemDraft] {
        var drafts: [InboxItemDraft] = []
        var pageToken: String?

        repeat {
            var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            var q = [URLQueryItem(name: "labelIds", value: "INBOX"), URLQueryItem(name: "maxResults", value: "50")]
            if let afterInternalDate {
                q.append(URLQueryItem(name: "q", value: "after:\(afterInternalDate / 1000)"))
            }
            if let pageToken { q.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            c.queryItems = q

            let data = try await get(c.url!, token: token)
            let list = try JSONDecoder().decode(ListResponse.self, from: data)

            for ref in list.messages ?? [] {
                if let d = try await fetchMessage(id: ref.id, token: token) {
                    drafts.append(d)
                }
            }
            pageToken = list.nextPageToken
        } while pageToken != nil && drafts.count < maxMessages

        return drafts
    }

    private static func fetchMessage(id: String, token: String) async throws -> InboxItemDraft? {
        var c = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        c.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "From")
        ]
        let data = try await get(c.url!, token: token)
        let msg = try JSONDecoder().decode(Message.self, from: data)
        let headers = Dictionary(
            uniqueKeysWithValues: (msg.payload?.headers ?? []).compactMap { h -> (String, String)? in
                guard let n = h.name?.lowercased(), let v = h.value else { return nil }
                return (n, v)
            }
        )
        let ms = Int64(msg.internalDate ?? "0") ?? 0
        return InboxItemDraft(
            externalId: id,
            title: headers["subject"] ?? "(No subject)",
            sender: headers["from"],
            snippet: msg.snippet,
            url: URL(string: "https://mail.google.com/mail/u/0/#inbox/\(id)"),
            publishedAt: Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        )
    }

    private static func get(_ url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
        let nextPageToken: String?
    }

    private struct Message: Decodable {
        struct Header: Decodable { let name: String?; let value: String? }
        struct Payload: Decodable { let headers: [Header]? }
        let snippet: String?
        let internalDate: String?
        let payload: Payload?
    }
}
