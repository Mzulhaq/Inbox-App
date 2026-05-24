from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class GmailLinkIn(BaseModel):
    access_token: str
    refresh_token: str | None = None
    expires_at: datetime | None = None
    email: str | None = None


class SourceOut(BaseModel):
    id: UUID
    name: str
    type: str
    is_enabled: bool
    last_synced_at: datetime | None
    email: str | None = None

    model_config = {"from_attributes": True}
