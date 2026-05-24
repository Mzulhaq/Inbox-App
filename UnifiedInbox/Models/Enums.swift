import Foundation

enum SourceType: String, Codable {
    case gmail
}

enum ItemPriority: Int, Codable, CaseIterable, Comparable {
    case critical = 0
    case high = 1
    case medium = 2
    case low = 3

    var label: String {
        switch self {
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    static func < (lhs: ItemPriority, rhs: ItemPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum InboxFilter: String, CaseIterable, Identifiable {
    case all, unread, careers, critical, high, medium, low
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "All"
        case .unread: "Unread"
        case .careers: "Careers"
        case .critical: "Critical"
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}

struct GmailConfig: Codable {
    var email: String?
    var lastInternalDate: Int64?
    var backendSourceId: UUID?
}

struct InboxItemDraft {
    var externalId: String
    var title: String
    var sender: String?
    var snippet: String?
    var url: URL?
    var publishedAt: Date
}
