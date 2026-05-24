# Unified Inbox API

FastAPI backend: user accounts, Gmail token storage, server-side sync, unified feed for the iOS app.

## Quick start

```bash
cd "Inbox App"
docker compose up -d

cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env: SECRET_KEY, DATABASE_URL, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

- Health: http://127.0.0.1:8000/health
- OpenAPI: http://127.0.0.1:8000/docs

## iOS connection

1. Set `UnifiedInbox/Resources/API.env` → `API_BASE_URL=http://127.0.0.1:8000` (simulator) or your Mac LAN IP (device).
2. Run the app → **Sources** → Connect Gmail.
3. Flow: Google OAuth on device → iOS registers user → links tokens → `POST /feed/sync` → `GET /feed` → SwiftData cache.

See [docs/BACKEND_INTEGRATION.md](../docs/BACKEND_INTEGRATION.md) for the full diagram and API table.

For a per-file map of the Python codebase, see [docs/BACKEND_ARCHITECTURE.md](../docs/BACKEND_ARCHITECTURE.md).

## Environment

| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL (default from docker-compose) |
| `SECRET_KEY` | JWT signing |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Server Gmail API (Web client in same GCP project) |
| `CORS_ORIGINS` | Optional, comma-separated |

## API routes (`/api`)

- `POST /auth/register` — `{ "email" }` → JWT
- `POST /accounts/gmail/link` — store Google tokens from iOS
- `POST /feed/sync` — pull Gmail into DB
- `GET /feed` — list items for the app
- `PATCH /feed/{id}` — read/mute updates

## Ranking

Careers-focused Gmail ranking (interviews, rejections, applications) — see [docs/RANKING.md](../docs/RANKING.md).

```bash
pytest tests/test_ranking.py
```

If upgrading an existing DB, add columns (see RANKING.md) or `docker compose down -v`.

## Next backend work

- Background sync worker (cron / Celery)
- User-editable rules API
- RSS source type
- Webhook or push to notify iOS
