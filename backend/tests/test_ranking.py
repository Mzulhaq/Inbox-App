from app.services.ranking_service import RankCategory, RankingService

ranking = RankingService()


def test_interview_is_critical():
    r = ranking.resolve(
        "Interview scheduled — Backend Engineer",
        "Please join your video interview on Friday",
        "noreply@greenhouse.io",
    )
    assert r.category == RankCategory.JOB_INTERVIEW
    assert r.priority == 0
    assert r.label == "Interview"


def test_rejection_is_high():
    r = ranking.resolve(
        "Update on your application",
        "Regret to inform you we will not be moving forward with your candidacy",
        "talent@acme.com",
    )
    assert r.category == RankCategory.JOB_REJECTION
    assert r.priority == 1


def test_newsletter_is_low():
    r = ranking.resolve("Weekly digest", "Unsubscribe here", "news@site.com")
    assert r.category == RankCategory.NEWSLETTER
    assert r.priority == 3
