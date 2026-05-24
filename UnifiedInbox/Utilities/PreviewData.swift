import SwiftData
import SwiftUI

#if DEBUG
enum PreviewData {
    @MainActor
    static var container: ModelContainer = {
        let schema = Schema([InboxItem.self, ConnectedSource.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let source = ConnectedSource(name: "you@gmail.com")
        context.insert(source)

        context.insert(InboxItem(
            externalId: "1",
            sourceId: source.id,
            title: "Bank alert: unusual activity",
            sender: "alerts@bank.com",
            snippet: "Please review recent transactions…",
            publishedAt: Date(),
            priority: .critical
        ))
        context.insert(InboxItem(
            externalId: "2",
            sourceId: source.id,
            title: "Interview scheduled — Software Engineer",
            sender: "noreply@greenhouse.io",
            snippet: "We would like to invite you to a video interview…",
            publishedAt: Date().addingTimeInterval(-1800),
            priority: .critical,
            rankCategory: .jobInterview,
            rankLabel: "Interview"
        ))
        context.insert(InboxItem(
            externalId: "3",
            sourceId: source.id,
            title: "Update on your application",
            sender: "talent@company.com",
            snippet: "Regret to inform you we will not be moving forward…",
            publishedAt: Date().addingTimeInterval(-3600),
            isRead: true,
            priority: .high,
            rankCategory: .jobRejection,
            rankLabel: "Application update"
        ))
        context.insert(InboxItem(
            externalId: "4",
            sourceId: source.id,
            title: "Weekly newsletter",
            sender: "news@site.com",
            snippet: "Top stories this week…",
            publishedAt: Date().addingTimeInterval(-7200),
            isRead: true,
            priority: .low,
            rankCategory: .newsletter,
            rankLabel: "Newsletter"
        ))
        try? context.save()
        return container
    }()
}
#endif
