from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status
from sqlalchemy import or_

from app.api.dependencies import CurrentUser, DbSession
from app.models.connected_account import ConnectedAccount
from app.models.feed_item import FeedItem
from app.models.source import Source
from app.schemas.feed_schema import FeedItemOut, FeedItemPatch, SyncResult
from app.services.gmail_service import GmailService
from app.services.ranking_service import RankingService

router = APIRouter(prefix="/feed", tags=["feed"])
gmail = GmailService()
ranking = RankingService()


@router.get("", response_model=list[FeedItemOut])
def list_feed(
    user: CurrentUser,
    db: DbSession,
    unread_only: bool = False,
    careers_only: bool = False,
    search: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    since: datetime | None = None,
) -> list[FeedItem]:
    q = db.query(FeedItem).filter_by(user_id=user.id, is_muted=False)
    if careers_only:
        q = q.filter(FeedItem.rank_category.like("job_%"))
    if unread_only:
        q = q.filter_by(is_read=False)
    if since:
        q = q.filter(FeedItem.published_at >= since)
    if search:
        term = f"%{search}%"
        q = q.filter(
            or_(FeedItem.title.ilike(term), FeedItem.body.ilike(term), FeedItem.sender.ilike(term))
        )
    return q.order_by(FeedItem.priority.asc(), FeedItem.published_at.desc()).limit(limit).all()


@router.patch("/{item_id}", response_model=FeedItemOut)
def patch_item(item_id: UUID, body: FeedItemPatch, user: CurrentUser, db: DbSession) -> FeedItem:
    item = db.query(FeedItem).filter_by(id=item_id, user_id=user.id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(item, field, value)
    db.commit()
    db.refresh(item)
    return item


@router.post("/rerank", response_model=SyncResult)
def rerank_feed(user: CurrentUser, db: DbSession) -> SyncResult:
    """Re-apply ranking rules to all stored messages (e.g. after rule updates)."""
    items = db.query(FeedItem).filter_by(user_id=user.id).all()
    for item in items:
        rank = ranking.resolve(item.title, item.body, item.sender)
        item.priority = rank.priority
        item.rank_category = rank.category.value
        item.rank_label = rank.label or None
    db.commit()
    total = len(items)
    return SyncResult(inserted=0, total=total)


@router.post("/sync", response_model=SyncResult)
def sync_feed(user: CurrentUser, db: DbSession) -> SyncResult:
    inserted = 0
    sources = db.query(Source).filter_by(user_id=user.id, is_enabled=True, type="gmail").all()
    for source in sources:
        if not source.connected_account_id:
            continue
        account = db.get(ConnectedAccount, source.connected_account_id)
        if account and account.access_token:
            inserted += gmail.sync_source(db, source, account)

    total = db.query(FeedItem).filter_by(user_id=user.id).count()
    return SyncResult(inserted=inserted, total=total)
