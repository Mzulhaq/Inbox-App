from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str = "postgresql://postgres:postgres@localhost:5432/unified_inbox"
    secret_key: str = "dev-secret"
    access_token_expire_minutes: int = 60 * 24 * 7
    api_prefix: str = "/api"
    cors_origins: str = "*"

    google_client_id: str = ""
    google_client_secret: str = ""
    google_web_redirect_uri: str = "http://localhost:8000/api/auth/google/callback"

    @property
    def cors_origin_list(self) -> list[str]:
        if self.cors_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
