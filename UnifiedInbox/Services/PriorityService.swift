import Foundation

/// Keyword + sender ranking. Lower `ItemPriority` raw value = more urgent.
enum RankCategory: String, Codable {
    case jobInterview = "job_interview"
    case jobRejection = "job_rejection"
    case jobApplication = "job_application"
    case jobOffer = "job_offer"
    case jobUpdate = "job_update"
    case finance = "finance"
    case security = "security"
    case newsletter = "newsletter"
    case general = "general"

    var isCareers: Bool { rawValue.hasPrefix("job_") }
}

struct RankResult {
    let priority: ItemPriority
    let category: RankCategory
    let label: String
}

private struct RankRule {
    let keywords: [String]
    let senderDomains: [String]
    let priority: ItemPriority
    let category: RankCategory
    let score: Int
    let label: String
}

enum PriorityService {
    private static let rules: [RankRule] = [
        RankRule(
            keywords: [
                "interview scheduled", "schedule your interview", "invite you to interview",
                "invited you to interview", "phone screen", "video interview", "onsite interview",
                "on-site interview", "technical interview", "interview confirmation",
                "interview invitation", "interview with", "calendar invite for interview"
            ],
            senderDomains: [
                "greenhouse.io", "lever.co", "myworkday.com", "workday.com",
                "icims.com", "ashbyhq.com", "smartrecruiters.com"
            ],
            priority: .critical, category: .jobInterview, score: 100, label: "Interview"
        ),
        RankRule(
            keywords: [
                "regret to inform", "not moving forward", "will not be moving forward",
                "not be moving forward", "other candidates", "other qualified candidates",
                "not selected", "application rejected", "rejected your application",
                "unable to offer you", "decided not to proceed",
                "not proceeding with your application", "unfortunately", "we will not be offering",
                "position has been filled"
            ],
            senderDomains: ["greenhouse.io", "lever.co", "myworkday.com", "indeed.com", "linkedin.com"],
            priority: .high, category: .jobRejection, score: 90, label: "Application update"
        ),
        RankRule(
            keywords: [
                "offer letter", "pleased to offer", "job offer", "extend an offer",
                "extended an offer", "congratulations on your offer"
            ],
            senderDomains: [],
            priority: .critical, category: .jobOffer, score: 95, label: "Job offer"
        ),
        RankRule(
            keywords: [
                "thank you for applying", "application received", "received your application",
                "we received your application", "thanks for applying", "confirm we received"
            ],
            senderDomains: ["greenhouse.io", "lever.co", "myworkday.com", "workday.com"],
            priority: .medium, category: .jobApplication, score: 50, label: "Application"
        ),
        RankRule(
            keywords: [
                "recruiter", "talent team", "hiring manager", "hiring team",
                "next steps in the process", "status of your application",
                "update on your application", "your application to"
            ],
            senderDomains: [
                "greenhouse.io", "lever.co", "linkedin.com", "indeed.com",
                "glassdoor.com", "ziprecruiter.com"
            ],
            priority: .high, category: .jobUpdate, score: 70, label: "Job update"
        ),
        RankRule(
            keywords: ["bank", "payment failed", "overdraft", "wire transfer", "account alert"],
            senderDomains: [],
            priority: .critical, category: .finance, score: 85, label: "Finance"
        ),
        RankRule(
            keywords: [
                "security alert", "suspicious sign-in", "unusual sign-in", "verify your identity",
                "password reset", "two-factor", "2-step verification"
            ],
            senderDomains: [],
            priority: .critical, category: .security, score: 88, label: "Security"
        ),
        RankRule(
            keywords: ["unsubscribe", "newsletter", "weekly digest", "marketing", "promotional"],
            senderDomains: [],
            priority: .low, category: .newsletter, score: 10, label: "Newsletter"
        )
    ]

    private static let jobHints = [
        "interview", "application", "position", "role", "candidate",
        "recruit", "hiring", "offer", "regret", "thank you for applying"
    ]

    static func resolve(title: String, snippet: String?, sender: String?) -> RankResult {
        let text = [title, snippet ?? "", sender ?? ""].joined(separator: " ").lowercased()
        let senderL = (sender ?? "").lowercased()

        var best: RankRule?
        var bestScore = -1

        for rule in rules {
            guard matches(rule, text: text, sender: senderL) else { continue }
            if rule.score > bestScore {
                best = rule
                bestScore = rule.score
            }
        }

        guard let best else {
            return RankResult(priority: .medium, category: .general, label: "")
        }
        return RankResult(priority: best.priority, category: best.category, label: best.label)
    }

    private static func matches(_ rule: RankRule, text: String, sender: String) -> Bool {
        if rule.keywords.contains(where: { text.contains($0) }) { return true }
        guard !rule.senderDomains.isEmpty,
              rule.senderDomains.contains(where: { sender.contains($0) }) else { return false }
        return jobHints.contains(where: { text.contains($0) })
    }

    static func isCareers(category: RankCategory?) -> Bool {
        category?.isCareers ?? false
    }

    static func isCareers(categoryRaw: String?) -> Bool {
        guard let categoryRaw else { return false }
        return categoryRaw.hasPrefix("job_")
    }
}
