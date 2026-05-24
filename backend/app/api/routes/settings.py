from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/settings", tags=["settings"])


class HealthSettings(BaseModel):
    message: str = "Settings API reserved for user prefs (retention, hide_low) in a later iteration."
