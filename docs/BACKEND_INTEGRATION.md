# Backend + iOS integration

## Architecture

```text
┌─────────────┐     JWT      ┌──────────────┐     Gmail API    ┌────────┐
│  iOS App    │ ◄──────────► │   FastAPI    │ ◄──────────────► │ Google │
│  SwiftData  │   REST       │  PostgreSQL  │                  └────────┘
└─────────────┘              └──────────────┘
```

- **iOS** = UI + local cache (offline-friendly)
- **Backend** = auth, Gmail tokens, sync, feed storage, priority rules (server-side later)
- **Gmail OAuth on device** still runs in iOS; tokens are **uploaded** to the backend (`POST /api/accounts/gmail/link`)

## Data flow

1. User signs in with Google on iOS (existing flow).
2. iOS registers with backend: `POST /api/auth/register` → JWT in Keychain.
3. iOS links Gmail: `POST /api/accounts/gmail/link` with Google access/refresh tokens.
4. On refresh:
   - `POST /api/feed/sync` — backend fetches new Gmail messages
   - `GET /api/feed` — iOS downloads items and merges into SwiftData
5. Mark read on iOS → `PATCH /api/feed/{id}` (when item id came from server).

## Run locally

### 1. Database

```bash
cd "Inbox App"
docker compose up -d
```

### 2. Backend

```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Add GOOGLE_CLIENT_ID + GOOGLE_CLIENT_SECRET (same Google Cloud project)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Docs: http://127.0.0.1:8000/docs

### 3. iOS

- `UnifiedInbox/Resources/API.env` → `API_BASE_URL=http://127.0.0.1:8000`
- Simulator: `127.0.0.1` works.
- **Physical iPhone**: use your Mac's LAN IP, e.g. `http://192.168.1.x:8000`, and run uvicorn with `--host 0.0.0.0`.

Clean build after adding `API.env` to Copy Bundle Resources.

## API summary

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/auth/register` | No | `{ "email" }` → JWT |
| GET | `/api/auth/me` | JWT | Current user |
| POST | `/api/accounts/gmail/link` | JWT | Store Google tokens |
| DELETE | `/api/accounts/gmail` | JWT | Disconnect |
| POST | `/api/feed/sync` | JWT | Pull Gmail → DB |
| GET | `/api/feed` | JWT | List items for iOS |
| PATCH | `/api/feed/{id}` | JWT | Update read/mute |

## What to build next

1. **Background sync worker** (`python -m app.workers.sync_worker`) on a schedule
2. **Conflict rules** — server wins for `is_read` vs local
3. **Rules API** — CRUD priority rules on backend, apply on ingest
4. **RSS connector** — second source type, same feed endpoints
5. **Remove local-only Gmail path** once backend is stable
6. **Server-side OAuth** — optional; stops sending tokens from iOS

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| API error connection refused | Backend not running or wrong `API_BASE_URL` |
| 401 on feed | Re-register: disconnect + connect again |
| Empty feed after sync | Gmail API credentials missing in backend `.env` |
| Device can't reach API | Use LAN IP, not `127.0.0.1` |
