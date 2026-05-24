import Foundation
import SwiftData

@Observable
@MainActor
final class InboxViewModel {
    var searchText = ""
    var filter: InboxFilter = .all
    var isRefreshing = false
    var errorMessage: String?

    private let auth = GoogleAuthService()

    func refresh(context: ModelContext) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            _ = try await SyncService.refresh(context: context, auth: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markRead(_ item: InboxItem, context: ModelContext) {
        item.isRead = true
        try? context.save()
        if APIConfig.isConfigured, BackendSessionStore.load() != nil {
            Task { try? await BackendAPI.patchItem(id: item.id, isRead: true) }
        }
    }

    func delete(_ item: InboxItem, context: ModelContext) {
        context.delete(item)
        try? context.save()
    }

    func matchesFilter(_ item: InboxItem) -> Bool {
        if AppSettings.hideLowPriority && item.priority == .low { return false }
        if item.isMuted { return false }
        switch filter {
        case .all: break
        case .unread: if item.isRead { return false }
        case .careers:
            if !PriorityService.isCareers(categoryRaw: item.rankCategoryRaw) { return false }
        case .critical: if item.priority != .critical { return false }
        case .high: if item.priority != .high { return false }
        case .medium: if item.priority != .medium { return false }
        case .low: if item.priority != .low { return false }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return item.title.localizedCaseInsensitiveContains(q)
            || (item.sender?.localizedCaseInsensitiveContains(q) ?? false)
            || (item.snippet?.localizedCaseInsensitiveContains(q) ?? false)
    }
}

enum AppSettings {
    private static let hideLowKey = "hideLow"
    private static let retentionKey = "retentionDays"
    private static let backendEmailKey = "backendEmail"

    static var backendEmail: String {
        get {
            if let e = UserDefaults.standard.string(forKey: backendEmailKey), !e.isEmpty { return e }
            return "dev@unifiedinbox.local"
        }
        set { UserDefaults.standard.set(newValue, forKey: backendEmailKey) }
    }

    static var hideLowPriority: Bool {
        get { UserDefaults.standard.bool(forKey: hideLowKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideLowKey) }
    }

    static var retentionDays: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: retentionKey)
            return v > 0 ? v : 90
        }
        set { UserDefaults.standard.set(newValue, forKey: retentionKey) }
    }

    static func prune(context: ModelContext) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let c = cutoff
        let desc = FetchDescriptor<InboxItem>(predicate: #Predicate { $0.publishedAt < c })
        (try? context.fetch(desc))?.forEach { context.delete($0) }
        try? context.save()
    }
}
