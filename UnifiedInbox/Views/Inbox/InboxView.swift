import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\InboxItem.priorityRaw), SortDescriptor(\InboxItem.publishedAt, order: .reverse)])
    private var allItems: [InboxItem]

    @State private var vm = InboxViewModel()

    private var items: [InboxItem] { allItems.filter { vm.matchesFilter($0) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if let err = vm.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
                if items.isEmpty {
                    ContentUnavailableView("No items", systemImage: "tray", description: Text("Connect Gmail or pull to refresh."))
                } else {
                    List(items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            InboxRowView(item: item)
                        }
                        .swipeActions(edge: .leading) {
                            Button(item.isRead ? "Unread" : "Read") {
                                item.isRead.toggle()
                                try? context.save()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { vm.delete(item, context: context) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Inbox")
            .searchable(text: $vm.searchText, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.refresh(context: context) } } label: {
                        if vm.isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .refreshable { await vm.refresh(context: context) }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(InboxFilter.allCases) { f in
                    Button(f.label) { vm.filter = f }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(vm.filter == f ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    InboxView()
        .modelContainer(PreviewData.container)
}
