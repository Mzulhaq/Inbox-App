"""Backward-compatible wrapper around RankingService."""

from app.services.ranking_service import RankResult, RankingService

__all__ = ["PrioritizationService", "RankResult", "RankingService"]


class PrioritizationService:
    def __init__(self) -> None:
        self._ranking = RankingService()

    def resolve(self, title: str, body: str | None, sender: str | None, default: int = 2) -> int:
        return self._ranking.resolve(title, body, sender, default).priority

    def resolve_full(self, title: str, body: str | None, sender: str | None, default: int = 2) -> RankResult:
        return self._ranking.resolve(title, body, sender, default)
