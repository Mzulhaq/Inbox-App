import Foundation
import SwiftData

@Observable
@MainActor
final class SettingsViewModel {
    var hideLowPriority: Bool
    var retentionDays: Int

    init() {
        hideLowPriority = AppSettings.hideLowPriority
        retentionDays = AppSettings.retentionDays
    }

    func save() {
        AppSettings.hideLowPriority = hideLowPriority
        AppSettings.retentionDays = retentionDays
    }

    func deleteAll(context: ModelContext) {
        try? context.delete(model: InboxItem.self)
        try? context.delete(model: ConnectedSource.self)
        try? GoogleAuthService().signOut()
        try? context.save()
    }

    func prune(context: ModelContext) {
        AppSettings.prune(context: context)
    }
}
