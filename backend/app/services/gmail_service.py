from datetime import UTC, datetime

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.models.connected_account import ConnectedAccount
from app.models.feed_item import FeedItem
from app.models.source import Source
from app.services.prioritization_service import PrioritizationService

settings = get_settings()


class GmailService:
    def __init__(self) -> None:
        self.prioritizer = PrioritizationService()

    def _credentials(self, account: ConnectedAccount) -> Credentials:
        return Credentials(
            token=account.access_token,
            refresh_token=account.refresh_token,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=settings.google_client_id,
            client_secret=settings.google_client_secret,
        )

    def sync_source(self, db: Session, source: Source, account: ConnectedAccount, limit: int = 50) -> int:
        creds = self._credentials(account)
        if creds.expired and creds.refresh_token:
            from google.auth.transport.requests import Request

            creds.refresh(Request())
            account.access_token = creds.token
            account.token_expires_at = creds.expiry
            db.commit()

        service = build("gmail", "v1", credentials=creds, cache_discovery=False)
        config = source.config or {}
        list_kwargs: dict = {"userId": "me", "labelIds": ["INBOX"], "maxResults": limit}
        if config.get("last_internal_date"):
            list_kwargs["q"] = f"after:{int(config['last_internal_date']) // 1000}"

        result = service.users().messages().list(**list_kwargs).execute()
        inserted = 0
        latest_internal = config.get("last_internal_date")

        for ref in result.get("messages", []):
            msg_id = ref["id"]
            existing = db.query(FeedItem).filter_by(source_id=source.id, external_id=msg_id).first()

            msg = (
                service.users()
                .messages()
                .get(
                    userId="me",
                    id=msg_id,
                    format="metadata",
                    metadataHeaders=["Subject", "From"],
                )
                .execute()
            )
            headers = {
                h["name"].lower(): h["value"]
                for h in msg.get("payload", {}).get("headers", [])
            }
            internal = int(msg.get("internalDate", 0))
            latest_internal = max(latest_internal or 0, internal)
            published = datetime.fromtimestamp(internal / 1000, tz=UTC)
            subject = headers.get("subject", "(No subject)")
            sender = headers.get("from")
            rank = self.prioritizer.resolve_full(subject, msg.get("snippet"), sender)

            if existing:
                existing.title = subject[:500]
                existing.sender = sender
                existing.body = msg.get("snippet")
                existing.published_at = published
                existing.priority = rank.priority
                existing.rank_category = rank.category.value
                existing.rank_label = rank.label or None
                continue

            item = FeedItem(
                user_id=source.user_id,
                source_id=source.id,
                external_id=msg_id,
                title=subject[:500],
                sender=sender,
                body=msg.get("snippet"),
                url=f"https://mail.google.com/mail/u/0/#inbox/{msg_id}",
                published_at=published,
                priority=rank.priority,
                rank_category=rank.category.value,
                rank_label=rank.label or None,
            )
            db.add(item)
            inserted += 1

        config["last_internal_date"] = latest_internal
        source.config = config
        source.last_synced_at = datetime.now(UTC)
        if account.email:
            source.name = account.email
        db.commit()
        return inserted
