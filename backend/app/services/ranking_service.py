"""Keyword + sender ranking for feed items. Lower priority int = more urgent."""

from dataclasses import dataclass
from enum import StrEnum


class RankCategory(StrEnum):
    JOB_INTERVIEW = "job_interview"
    JOB_REJECTION = "job_rejection"
    JOB_APPLICATION = "job_application"
    JOB_OFFER = "job_offer"
    JOB_UPDATE = "job_update"
    FINANCE = "finance"
    SECURITY = "security"
    NEWSLETTER = "newsletter"
    GENERAL = "general"


@dataclass(frozen=True)
class RankRule:
    keywords: tuple[str, ...]
    priority: int
    category: RankCategory
    score: int
    sender_domains: tuple[str, ...] = ()
    label: str = ""


# Higher score wins when multiple rules match. priority 0 = critical … 3 = low.
RULES: tuple[RankRule, ...] = (
    # --- Careers (critical / high) ---
    RankRule(
        (
            "interview scheduled",
            "schedule your interview",
            "invite you to interview",
            "invited you to interview",
            "phone screen",
            "video interview",
            "onsite interview",
            "on-site interview",
            "technical interview",
            "interview confirmation",
            "interview invitation",
            "interview with",
            "calendar invite for interview",
        ),
        priority=0,
        category=RankCategory.JOB_INTERVIEW,
        score=100,
        sender_domains=(
            "greenhouse.io",
            "lever.co",
            "myworkday.com",
            "workday.com",
            "icims.com",
            "ashbyhq.com",
            "smartrecruiters.com",
        ),
        label="Interview",
    ),
    RankRule(
        (
            "regret to inform",
            "not moving forward",
            "will not be moving forward",
            "not be moving forward",
            "other candidates",
            "other qualified candidates",
            "not selected",
            "application rejected",
            "rejected your application",
            "unable to offer you",
            "decided not to proceed",
            "not proceeding with your application",
            "unfortunately",
            "we will not be offering",
            "position has been filled",
        ),
        priority=1,
        category=RankCategory.JOB_REJECTION,
        score=90,
        sender_domains=("greenhouse.io", "lever.co", "myworkday.com", "indeed.com", "linkedin.com"),
        label="Application update",
    ),
    RankRule(
        (
            "offer letter",
            "pleased to offer",
            "job offer",
            "extend an offer",
            "extended an offer",
            "congratulations on your offer",
        ),
        priority=0,
        category=RankCategory.JOB_OFFER,
        score=95,
        label="Job offer",
    ),
    RankRule(
        (
            "thank you for applying",
            "application received",
            "received your application",
            "we received your application",
            "thanks for applying",
            "confirm we received",
        ),
        priority=2,
        category=RankCategory.JOB_APPLICATION,
        score=50,
        sender_domains=("greenhouse.io", "lever.co", "myworkday.com", "workday.com"),
        label="Application",
    ),
    RankRule(
        (
            "recruiter",
            "talent team",
            "hiring manager",
            "hiring team",
            "next steps in the process",
            "status of your application",
            "update on your application",
            "your application to",
        ),
        priority=1,
        category=RankCategory.JOB_UPDATE,
        score=70,
        sender_domains=(
            "greenhouse.io",
            "lever.co",
            "linkedin.com",
            "indeed.com",
            "glassdoor.com",
            "ziprecruiter.com",
        ),
        label="Job update",
    ),
    # --- Finance & security ---
    RankRule(
        ("bank", "payment failed", "overdraft", "wire transfer", "account alert"),
        priority=0,
        category=RankCategory.FINANCE,
        score=85,
        label="Finance",
    ),
    RankRule(
        (
            "security alert",
            "suspicious sign-in",
            "unusual sign-in",
            "verify your identity",
            "password reset",
            "two-factor",
            "2-step verification",
        ),
        priority=0,
        category=RankCategory.SECURITY,
        score=88,
        label="Security",
    ),
    # --- Low signal ---
    RankRule(
        ("unsubscribe", "newsletter", "weekly digest", "marketing", "promotional"),
        priority=3,
        category=RankCategory.NEWSLETTER,
        score=10,
        label="Newsletter",
    ),
)


@dataclass(frozen=True)
class RankResult:
    priority: int
    category: RankCategory
    label: str


class RankingService:
    def resolve(self, title: str, body: str | None, sender: str | None, default: int = 2) -> RankResult:
        text = " ".join(filter(None, [title, body or "", sender or ""])).lower()
        sender_l = (sender or "").lower()

        best: RankRule | None = None
        best_score = -1

        for rule in RULES:
            if not self._matches(rule, text, sender_l):
                continue
            if rule.score > best_score:
                best = rule
                best_score = rule.score

        if best is None:
            return RankResult(
                priority=default,
                category=RankCategory.GENERAL,
                label="",
            )

        return RankResult(
            priority=best.priority,
            category=best.category,
            label=best.label or best.category.replace("_", " ").title(),
        )

    @staticmethod
    def _matches(rule: RankRule, text: str, sender_l: str) -> bool:
        if any(kw in text for kw in rule.keywords):
            return True
        if rule.sender_domains and any(d in sender_l for d in rule.sender_domains):
            # Sender-only match for ATS domains still needs a job-ish signal in subject/body
            job_hint = any(
                h in text
                for h in (
                    "interview",
                    "application",
                    "position",
                    "role",
                    "candidate",
                    "recruit",
                    "hiring",
                    "offer",
                    "regret",
                    "thank you for applying",
                )
            )
            return job_hint
        return False

    def is_careers(self, category: str | RankCategory | None) -> bool:
        if category is None:
            return False
        c = category.value if isinstance(category, RankCategory) else str(category)
        return c.startswith("job_")
