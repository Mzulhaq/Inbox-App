import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    let onDone: () -> Void

    @State private var step = 0
    @State private var isLoading = false
    @State private var error: String?
    private let auth = GoogleAuthService()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Group {
                switch step {
                case 0:
                    page("Unified Inbox", "One timeline for email you connect — not system notifications.", "tray.fill")
                case 1:
                    page("Private & read-only", "Gmail access is read-only. Your data stays on this device.", "lock.shield")
                case 2:
                    VStack(spacing: 12) {
                        page("Connect Gmail", "Sync your INBOX (up to 50 messages per refresh).", "envelope.badge")
                        if !GoogleConfig.isConfigured {
                            Text(GoogleConfig.configurationHint)
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    }
                default:
                    page("You're set", "Pull down to refresh anytime.", "checkmark.circle")
                }
            }
            Spacer()
            Button(action: next) {
                if isLoading { ProgressView() } else { Text(buttonTitle) }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(isLoading || (step == 2 && !GoogleConfig.isConfigured))
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var buttonTitle: String {
        switch step {
        case 0, 1: "Continue"
        case 2: "Sign in with Google"
        default: "Open Inbox"
        }
    }

    private func next() {
        switch step {
        case 0, 1: step += 1
        case 2:
            Task {
                isLoading = true
                error = nil
                defer { isLoading = false }
                do {
                    try await auth.signIn()
                    _ = try await SyncService.refresh(context: context, auth: auth)
                    step = 3
                } catch {
                    self.error = error.localizedDescription
                }
            }
        default: onDone()
        }
    }

    private func page(_ title: String, _ msg: String, _ icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 52)).foregroundStyle(.tint)
            Text(title).font(.largeTitle.bold())
            Text(msg).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding()
    }
}
