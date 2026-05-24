import SwiftUI

struct InboxRowView: View {
    let item: InboxItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .foregroundStyle(item.isRead ? .secondary : .primary)
                    Spacer()
                    HStack(spacing: 4) {
                        if let tag = item.rankLabel, !tag.isEmpty {
                            Text(tag)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }
                        Text(item.priority.label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.priority.color.opacity(0.2))
                            .foregroundStyle(item.priority.color)
                            .clipShape(Capsule())
                    }
                }
                if let sender = item.sender {
                    Text(sender).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let snippet = item.snippet {
                    Text(snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(Formatters.date(item.publishedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
