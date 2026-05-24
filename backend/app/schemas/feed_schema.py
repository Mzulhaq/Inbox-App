from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class FeedItemOut(BaseModel):
    id: UUID
    source_id: UUID
    external_id: str
    title: str
    sender: str | None
    body: str | None
    url: str | None
    published_at: datetime
    ingested_at: datetime
    is_read: bool
    is_muted: bool
    priority: int
    rank_category: str | None = None
    rank_label: str | None = None

    model_config = {"from_attributes": True}


class FeedItemPatch(BaseModel):
    is_read: bool | None = None
    is_muted: bool | None = None
    priority: int | None = Field(None, ge=0, le=3)


class SyncResult(BaseModel):
    inserted: int
    total: int
