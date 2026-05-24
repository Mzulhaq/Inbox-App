import Foundation
import SwiftData

@Model
final class InboxItem {
    @Attribute(.unique) var id: UUID
    var externalId: String
    var sourceId: UUID
    var title: String
    var sender: String?
    var snippet: String?
    var urlString: String?
    var publishedAt: Date
    var isRead: Bool
    var isMuted: Bool
    var priorityRaw: Int
    var rankCategoryRaw: String?
    var rankLabel: String?

    var url: URL? {
        get { urlString.flatMap(URL.init(string:)) }
        set { urlString = newValue?.absoluteString }
    }

    var priority: ItemPriority {
        get { ItemPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var rankCategory: RankCategory? {
        get {
            guard let rankCategoryRaw else { return nil }
            return RankCategory(rawValue: rankCategoryRaw)
        }
        set { rankCategoryRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        externalId: String,
        sourceId: UUID,
        title: String,
        sender: String? = nil,
        snippet: String? = nil,
        url: URL? = nil,
        publishedAt: Date,
        isRead: Bool = false,
        isMuted: Bool = false,
        priority: ItemPriority = .medium,
        rankCategory: RankCategory? = nil,
        rankLabel: String? = nil
    ) {
        self.id = id
        self.externalId = externalId
        self.sourceId = sourceId
        self.title = title
        self.sender = sender
        self.snippet = snippet
        self.urlString = url?.absoluteString
        self.publishedAt = publishedAt
        self.isRead = isRead
        self.isMuted = isMuted
        self.priorityRaw = priority.rawValue
        self.rankCategoryRaw = rankCategory?.rawValue
        self.rankLabel = rankLabel
    }
}
