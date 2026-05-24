import SwiftUI
import SwiftData

struct SourcesView: View {
    @Environment(\.modelContext) private var context
    @Query private var sources: [ConnectedSource]
    @State private var vm = SourcesViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Backend") {
                    Text(APIConfig.hint)
                        .font(.caption)
                        .foregroundStyle(APIConfig.isConfigured ? Color.secondary : Color.orange)
                }

                Section("Gmail") {
                    if vm.isConnected {
                        if let s = sources.first {
                            LabeledContent("Account", value: s.name)
                            if let d = s.lastSyncedAt {
                                LabeledContent("Last sync", value: Formatters.date(d))
                            }
                        }
                        Button("Sync now") { Task { await vm.sync(context: context) } }
                            .disabled(vm.isLoading)
                        Button("Disconnect", role: .destructive) { vm.disconnect(context: context) }
                    } else {
                        Text("Read-only INBOX access. Data stays on your device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await vm.connect(context: context) }
                        } label: {
                            Label("Sign in with Google", systemImage: "envelope.badge")
                        }
                        .disabled(vm.isLoading || !GoogleConfig.isConfigured)
                    }
                    if !GoogleConfig.isConfigured {
                        Text(GoogleConfig.configurationHint)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("Coming later") {
                    Label("RSS", systemImage: "dot.radiowaves.left.and.right")
                    Label("Reddit", systemImage: "bubble.left.and.bubble.right")
                }
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Sources")
            .overlay(alignment: .bottom) {
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.caption)
                        .padding(8)
                        .background(.red.opacity(0.9))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
        }
    }
}
