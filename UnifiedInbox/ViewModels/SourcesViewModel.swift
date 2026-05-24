import Foundation
import SwiftData

@Observable
@MainActor
final class SourcesViewModel {
    var isLoading = false
    var errorMessage: String?
    private let auth = GoogleAuthService()

    var isConnected: Bool { auth.isSignedIn }

    func connect(context: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.signIn()
            if let email = try? await GmailService.fetchProfileEmail(token: try await auth.validAccessToken()) {
                AppSettings.backendEmail = email
            }
            _ = try await SyncService.refresh(context: context, auth: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect(context: ModelContext) {
        try? auth.signOut()
        if APIConfig.isConfigured {
            Task { try? await BackendAPI.unlinkGmail() }
            try? BackendSessionStore.delete()
        }
        let desc = FetchDescriptor<ConnectedSource>()
        (try? context.fetch(desc))?.forEach { context.delete($0) }
        let items = FetchDescriptor<InboxItem>()
        (try? context.fetch(items))?.forEach { context.delete($0) }
        try? context.save()
    }

    func sync(context: ModelContext) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await SyncService.refresh(context: context, auth: auth)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
