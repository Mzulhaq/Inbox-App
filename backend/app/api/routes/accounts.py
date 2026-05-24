from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from app.api.dependencies import CurrentUser, DbSession
from app.models.connected_account import ConnectedAccount
from app.models.feed_item import FeedItem
from app.models.source import Source
from app.schemas.account_schema import GmailLinkIn, SourceOut
from app.services.gmail_service import GmailService

router = APIRouter(prefix="/accounts", tags=["accounts"])
gmail = GmailService()


@router.get("/sources", response_model=list[SourceOut])
def list_sources(user: CurrentUser, db: DbSession) -> list[SourceOut]:
    sources = db.query(Source).filter_by(user_id=user.id).all()
    out = []
    for s in sources:
        email = s.account.email if s.account else None
        out.append(
            SourceOut(
                id=s.id,
                name=s.name,
                type=s.type,
                is_enabled=s.is_enabled,
                last_synced_at=s.last_synced_at,
                email=email,
            )
        )
    return out


@router.post("/gmail/link", response_model=SourceOut)
def link_gmail(body: GmailLinkIn, user: CurrentUser, db: DbSession) -> SourceOut:
    account = db.query(ConnectedAccount).filter_by(user_id=user.id, provider="google").first()
    if not account:
        account = ConnectedAccount(user_id=user.id, provider="google")
        db.add(account)

    account.access_token = body.access_token
    account.refresh_token = body.refresh_token or account.refresh_token
    account.token_expires_at = body.expires_at
    account.email = body.email
    db.flush()

    source = db.query(Source).filter_by(user_id=user.id, type="gmail").first()
    if not source:
        source = Source(
            user_id=user.id,
            name=body.email or "Gmail",
            type="gmail",
            connected_account_id=account.id,
        )
        db.add(source)
    else:
        source.connected_account_id = account.id
        source.is_enabled = True
        if body.email:
            source.name = body.email

    db.commit()
    db.refresh(source)
    return SourceOut(
        id=source.id,
        name=source.name,
        type=source.type,
        is_enabled=source.is_enabled,
        last_synced_at=source.last_synced_at,
        email=account.email,
    )


@router.delete("/gmail", status_code=status.HTTP_204_NO_CONTENT)
def unlink_gmail(user: CurrentUser, db: DbSession) -> None:
    account = db.query(ConnectedAccount).filter_by(user_id=user.id, provider="google").first()
    if not account:
        return
    source_ids = [s.id for s in db.query(Source).filter_by(user_id=user.id, type="gmail").all()]
    if source_ids:
        db.query(FeedItem).filter(FeedItem.source_id.in_(source_ids)).delete(synchronize_session=False)
        db.query(Source).filter(Source.id.in_(source_ids)).delete(synchronize_session=False)
    db.delete(account)
    db.commit()
