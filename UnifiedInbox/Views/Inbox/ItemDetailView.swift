import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    let item: InboxItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    if let tag = item.rankLabel, !tag.isEmpty {
                        Text(tag)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    Text(item.priority.label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(item.priority.color.opacity(0.2))
                        .foregroundStyle(item.priority.color)
                        .clipShape(Capsule())
                }

                Text(item.title).font(.title2.bold())
                if let sender = item.sender {
                    Text(sender).font(.subheadline).foregroundStyle(.secondary)
                }
                if let snippet = item.snippet {
                    Text(snippet).font(.body)
                }
                Text(Formatters.date(item.publishedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if item.url != nil {
                    Button("Open in Gmail") {
                        if let url = item.url { openURL(url) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Message")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !item.isRead {
                item.isRead = true
                try? context.save()
                if APIConfig.isConfigured, BackendSessionStore.load() != nil {
                    Task { try? await BackendAPI.patchItem(id: item.id, isRead: true) }
                }
            }
        }
        .toolbar {
            Button(item.isMuted ? "Unmute" : "Mute") {
                item.isMuted.toggle()
                try? context.save()
            }
        }
    }
}
