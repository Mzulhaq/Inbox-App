# Unified Inbox

SwiftUI app + FastAPI backend — one prioritized timeline for Gmail (MVP).

## Open the app

```bash
open UnifiedInbox.xcodeproj
```

Requires **Xcode 15+**, **iOS 17+**.

## Run backend + app (dev)

**Terminal 1 — database + API**

```bash
cd "Inbox App"
docker compose up -d
cd backend && source .venv/bin/activate  # create venv first — see backend/README.md
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**Terminal 2 — iOS**

1. `UnifiedInbox/Resources/OAuth.env` — Google iOS client (see below)
2. `UnifiedInbox/Resources/API.env` — `API_BASE_URL=http://127.0.0.1:8000`
3. Clean build (⇧⌘K) → Run on simulator
4. **Sources** tab → Connect Gmail → pull to refresh inbox

Full integration notes: [docs/BACKEND_INTEGRATION.md](docs/BACKEND_INTEGRATION.md)

**Code walkthroughs (file-by-file):**

- [docs/FRONTEND_ARCHITECTURE.md](docs/FRONTEND_ARCHITECTURE.md) — iOS app structure and how files connect
- [docs/BACKEND_ARCHITECTURE.md](docs/BACKEND_ARCHITECTURE.md) — FastAPI backend structure and how files connect

## Google OAuth (iOS)

1. [Google Cloud Console](https://console.cloud.google.com/) → enable **Gmail API**
2. Create **iOS** OAuth client with bundle ID: `com.unifiedinbox.app`
3. Copy into **`OAuth.env`** (also `UnifiedInbox/Resources/OAuth.env`):

```env
GOOGLE_CLIENT_ID=your-id.apps.googleusercontent.com
GOOGLE_URL_SCHEME=com.googleusercontent.apps.your-id-prefix
```

4. **Copy Bundle Resources** must include `OAuth.env` and `API.env`.

For **server-side Gmail sync**, add a **Web** OAuth client to `backend/.env` (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`).

## Architecture

| Layer | Role |
|-------|------|
| iOS | UI, Google sign-in, SwiftData cache, calls REST API |
| Backend | JWT users, stores Gmail tokens, syncs Gmail, serves feed |
| Postgres | Users, sources, feed items |

Without `API.env`, the app falls back to **local-only** Gmail sync (no backend).

## Structure

```
UnifiedInbox/     SwiftUI app
backend/          FastAPI + SQLAlchemy
docs/             Integration guide
docker-compose.yml
```

## MVP features

- Gmail inbox sync (via backend when configured)
- Priority rules (hardcoded on server + client)
- Filters, search, read/unread (synced to server when using backend)
- Onboarding, settings, delete all data

## Deferred

AI, RSS, Reddit, push notifications, production deploy
