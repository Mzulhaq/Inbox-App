import Foundation
import SwiftData

@MainActor
enum SyncService {
    /// Primary path: backend syncs Gmail, iOS pulls feed and caches locally.
    static func refresh(context: ModelContext, auth: GoogleAuthService) async throws -> Int {
        if APIConfig.isConfigured {
            return try await refreshViaBackend(context: context, auth: auth)
        }
        return try await refreshLocalOnly(context: context, auth: auth)
    }

    static func ensureBackendSession(email: String) async throws {
        if BackendSessionStore.load() != nil { return }
        try await BackendAPI.register(email: email)
    }

    // MARK: - Backend path

    private static func refreshViaBackend(context: ModelContext, auth: GoogleAuthService) async throws -> Int {
        guard auth.isSignedIn else {
            throw NSError(domain: "SyncService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Connect Gmail in Sources before syncing."
            ])
        }

        let googleTokens = try await authTokenPayload(auth)
        let email = googleTokens.email ?? AppSettings.backendEmail

        try await ensureBackendSession(email: email)

        if auth.isSignedIn {
            let source = try await BackendAPI.linkGmail(
                accessToken: googleTokens.access,
                refreshToken: googleTokens.refresh,
                expiresAt: googleTokens.expiresAt,
                email: googleTokens.email
            )
            try upsertLocalSource(context: context, source: source)
        }

        _ = try await BackendAPI.syncFeed()
        _ = try await BackendAPI.rerankFeed()
        let items = try await BackendAPI.fetchFeed()
        return try mergeFeed(items, context: context)
    }

    private static func authTokenPayload(_ auth: GoogleAuthService) async throws -> (access: String, refresh: String?, expiresAt: Date?, email: String?) {
        guard auth.isSignedIn else {
            return ("", nil, nil, nil)
        }
        let access = try await auth.validAccessToken()
        let tokens = KeychainStore.load()
        let email = try? await GmailService.fetchProfileEmail(token: access)
        return (access, tokens?.refreshToken, tokens?.expiresAt, email)
    }

    private static func upsertLocalSource(context: ModelContext, source: SourceDTO) throws {
        let desc = FetchDescriptor<ConnectedSource>()
        let local: ConnectedSource
        if let existing = try context.fetch(desc).first {
            local = existing
        } else {
            local = ConnectedSource()
            context.insert(local)
        }
        local.name = source.email ?? source.name
        var config = local.gmailConfig
        config.email = source.email
        config.backendSourceId = source.id
        local.gmailConfig = config
        local.lastSyncedAt = source.last_synced_at
        try context.save()
    }

    private static func mergeFeed(_ dtos: [FeedItemDTO], context: ModelContext) throws -> Int {
        let source = try localSource(context: context)
        var inserted = 0

        for dto in dtos {
            let sid = source.id
            let eid = dto.external_id
            var fd = FetchDescriptor<InboxItem>(predicate: #Predicate { $0.externalId == eid && $0.sourceId == sid })
            fd.fetchLimit = 1

            if let existing = try context.fetch(fd).first {
                existing.title = dto.title
                existing.sender = dto.sender
                existing.snippet = dto.body
                existing.urlString = dto.url
                existing.publishedAt = dto.published_at
                existing.isRead = dto.is_read
                existing.isMuted = dto.is_muted
                existing.priorityRaw = dto.priority
                existing.rankCategoryRaw = dto.rank_category
                existing.rankLabel = dto.rank_label
                continue
            }

            let item = InboxItem(
                id: dto.id,
                externalId: dto.external_id,
                sourceId: source.id,
                title: dto.title,
                sender: dto.sender,
                snippet: dto.body,
                url: URL(string: dto.url ?? ""),
                publishedAt: dto.published_at,
                isRead: dto.is_read,
                isMuted: dto.is_muted,
                priority: ItemPriority(rawValue: dto.priority) ?? .medium,
                rankCategory: dto.rank_category.flatMap(RankCategory.init(rawValue:)),
                rankLabel: dto.rank_label
            )
            context.insert(item)
            inserted += 1
        }

        source.lastSyncedAt = Date()
        try rerankAllLocal(context: context)
        try context.save()
        return inserted
    }

    private static func localSource(context: ModelContext) throws -> ConnectedSource {
        let desc = FetchDescriptor<ConnectedSource>()
        if let existing = try context.fetch(desc).first {
            return existing
        }
        let source = ConnectedSource()
        context.insert(source)
        return source
    }

    // MARK: - Local-only fallback (no API)

    private static func refreshLocalOnly(context: ModelContext, auth: GoogleAuthService) async throws -> Int {
        let token = try await auth.validAccessToken()
        let source: ConnectedSource
        let desc = FetchDescriptor<ConnectedSource>()
        if let existing = try context.fetch(desc).first {
            source = existing
        } else {
            source = ConnectedSource()
            context.insert(source)
        }

        var config = source.gmailConfig
        let drafts = try await GmailService.fetchInbox(token: token, afterInternalDate: config.lastInternalDate)

        if config.email == nil {
            config.email = try await GmailService.fetchProfileEmail(token: token)
            source.name = config.email ?? "Gmail"
        }

        var inserted = 0
        for draft in drafts {
            let sid = source.id
            let eid = draft.externalId
            var fd = FetchDescriptor<InboxItem>(predicate: #Predicate { $0.externalId == eid && $0.sourceId == sid })
            fd.fetchLimit = 1
            if try context.fetch(fd).first != nil { continue }

            let rank = PriorityService.resolve(title: draft.title, snippet: draft.snippet, sender: draft.sender)
            context.insert(InboxItem(
                externalId: draft.externalId,
                sourceId: source.id,
                title: draft.title,
                sender: draft.sender,
                snippet: draft.snippet,
                url: draft.url,
                publishedAt: draft.publishedAt,
                priority: rank.priority,
                rankCategory: rank.category,
                rankLabel: rank.label.isEmpty ? nil : rank.label
            ))
            inserted += 1
        }

        if let maxDate = drafts.map(\.publishedAt).max() {
            config.lastInternalDate = Int64(maxDate.timeIntervalSince1970 * 1000)
        }
        source.gmailConfig = config
        source.lastSyncedAt = Date()
        try rerankAllLocal(context: context)
        try context.save()
        return inserted
    }

    private static func rerankAllLocal(context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<InboxItem>())
        for item in items {
            let rank = PriorityService.resolve(title: item.title, snippet: item.snippet, sender: item.sender)
            item.priority = rank.priority
            item.rankCategory = rank.category
            item.rankLabel = rank.label.isEmpty ? nil : rank.label
        }
    }
}
