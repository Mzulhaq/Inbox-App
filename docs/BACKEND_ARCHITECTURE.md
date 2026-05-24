# Backend architecture

This document describes every Python module under **`backend/app`**, what it does, and how requests flow through the API to PostgreSQL and Gmail.

Related: [FRONTEND_ARCHITECTURE.md](FRONTEND_ARCHITECTURE.md) · [BACKEND_INTEGRATION.md](BACKEND_INTEGRATION.md) · [RANKING.md](RANKING.md)

---

## Layer overview

```text
                    HTTP (iOS / curl / /docs)
                              │
┌─────────────────────────────▼─────────────────────────────┐
│  app/main.py          FastAPI app, CORS, router mount      │
│  app/api/routes/*     auth, accounts, feed, settings       │
│  app/api/dependencies.py   JWT → User, DB session          │
└─────────────────────────────┬─────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────┐
│  app/schemas/*        Pydantic request/response models     │
└─────────────────────────────┬─────────────────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────┐
│  app/services/*       Gmail sync, ranking                  │
└───────────────┬─────────────────────────────┬─────────────┘
                │                             │
┌───────────────▼──────────────┐   ┌──────────▼──────────────┐
│  app/models/* (SQLAlchemy)   │   │  Google Gmail API       │
│  PostgreSQL                  │   │  (google-api-python)    │
└──────────────────────────────┘   └─────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  app/core/*               config, DB engine, JWT helpers     │
└─────────────────────────────────────────────────────────────┘
```

**Infrastructure (repo root):**

- `docker-compose.yml` — Postgres 16 on port 5432, database `unified_inbox`
- `backend/.env` — secrets (from `.env.example`)
- `backend/requirements.txt` — Python dependencies
- `backend/tests/test_ranking.py` — unit tests for ranking rules

---

## Application entry

### `app/main.py`

| Responsibility | Detail |
|----------------|--------|
| Lifespan | Calls `init_db()` on startup (creates tables from models) |
| Middleware | CORS from `settings.cors_origin_list` |
| Routers | Mounts `auth`, `accounts`, `feed`, `settings` under `settings.api_prefix` (`/api`) |
| Health | `GET /health` → `{"status": "ok"}` |

**Connects to:** all route modules, `core.config`, `core.database`.

---

## Core (`app/core/`)

### `app/core/config.py`

Pydantic **`Settings`** loaded from `backend/.env`:

| Setting | Purpose |
|---------|---------|
| `database_url` | SQLAlchemy Postgres URL |
| `secret_key` | JWT signing |
| `access_token_expire_minutes` | JWT TTL (default 7 days) |
| `api_prefix` | `/api` |
| `cors_origins` | CORS allowlist |
| `google_client_id` / `google_client_secret` | Refresh Gmail tokens on server |
| `google_web_redirect_uri` | Reserved for future web OAuth |

`get_settings()` is cached with `@lru_cache`.

**Used by:** `database.py`, `security.py`, `gmail_service.py`, `main.py`.

### `app/core/database.py`

| Piece | Role |
|-------|------|
| `engine` | SQLAlchemy engine with `pool_pre_ping` |
| `SessionLocal` | Session factory |
| `Base` | Declarative base for models |
| `get_db()` | FastAPI dependency — yields session, closes in `finally` |
| `init_db()` | `create_all` after importing models |

**Connects to:** every route via `DbSession`, all ORM models.

### `app/core/security.py`

| Function | Role |
|----------|------|
| `create_access_token(user_id)` | JWT with `sub` = user UUID |
| `decode_token(token)` | Returns `UUID` or `None` |

Algorithm: **HS256** with `settings.secret_key`.

**Connects to:** `auth` routes (issue token), `dependencies.get_current_user` (validate).

---

## API dependencies

### `app/api/dependencies.py`

| Symbol | Role |
|--------|------|
| `get_current_user` | `HTTPBearer` → decode JWT → load `User` from DB |
| `CurrentUser` | Annotated alias for route injection |
| `DbSession` | Annotated `Session` from `get_db` |

**Connects to:** all protected routes (`accounts`, `feed`, `auth/me`).

---

## Routes (`app/api/routes/`)

### `app/api/routes/auth.py`

| Endpoint | Auth | Behavior |
|----------|------|----------|
| `POST /auth/register` | No | Find or create `User` by email → return JWT |
| `GET /auth/me` | JWT | Return current user |

**Schemas:** `RegisterIn`, `TokenOut`, `UserOut` from `schemas/auth_schema.py`.

**iOS calls:** `BackendAPI.register` on first sync (email from Gmail profile or `AppSettings.backendEmail`).

### `app/api/routes/accounts.py`

| Endpoint | Auth | Behavior |
|----------|------|----------|
| `GET /accounts/sources` | JWT | List user's sources + account email |
| `POST /accounts/gmail/link` | JWT | Upsert `ConnectedAccount` + `Source` with Google tokens from iOS |
| `DELETE /accounts/gmail` | JWT | Delete Gmail sources' feed items, sources, and Google account |

**Schemas:** `GmailLinkIn`, `SourceOut` from `schemas/account_schema.py`.

**iOS calls:** `linkGmail` after Google sign-in; `unlinkGmail` on disconnect.

**Data flow:**

```text
iOS Google tokens → ConnectedAccount (access/refresh/expiry/email)
                 → Source (type=gmail, linked to account)
```

### `app/api/routes/feed.py`

| Endpoint | Auth | Behavior |
|----------|------|----------|
| `GET /feed` | JWT | List items (filters: unread, careers_only, search, since, limit) |
| `PATCH /feed/{item_id}` | JWT | Update read/mute/priority |
| `POST /feed/sync` | JWT | For each enabled Gmail source → `GmailService.sync_source` |
| `POST /feed/rerank` | JWT | Re-run `RankingService` on all user's items |

**Schemas:** `FeedItemOut`, `FeedItemPatch`, `SyncResult` from `schemas/feed_schema.py`.

**Services:** module-level `gmail = GmailService()`, `ranking = RankingService()`.

**iOS calls:** `syncFeed` → `rerankFeed` → `fetchFeed` on each refresh; `patchItem` on mark read.

**Query ordering:** `priority ASC`, `published_at DESC` (lower priority int = more urgent).

**`careers_only`:** filters `rank_category LIKE 'job_%'` (server-side Careers filter).

### `app/api/routes/settings.py`

**Stub only** — returns a placeholder message. User prefs (retention, hide low) still live on iOS (`AppSettings`).

---

## Schemas (`app/schemas/`)

Pydantic v2 models for API I/O (not database tables).

### `app/schemas/auth_schema.py`

- `RegisterIn` — `email`  
- `TokenOut` — `access_token`, `token_type`  
- `UserOut` — `id`, `email`  

### `app/schemas/account_schema.py`

- `GmailLinkIn` — `access_token`, optional `refresh_token`, `expires_at`, `email`  
- `SourceOut` — source metadata + optional `email` for display  

### `app/schemas/feed_schema.py`

- `FeedItemOut` — full item including `rank_category`, `rank_label`  
- `FeedItemPatch` — optional `is_read`, `is_muted`, `priority`  
- `SyncResult` — `inserted`, `total` counts  

**Connects to:** route `response_model` / request bodies; mirrors iOS `FeedItemDTO`.

---

## Models (`app/models/`)

SQLAlchemy ORM tables. Imported in `models/__init__.py` so `init_db()` registers them.

### `app/models/user.py` — `users`

| Column | Purpose |
|--------|---------|
| `id` | UUID PK |
| `email` | Unique login identity for JWT registration |
| `created_at` | Timestamp |

**Relationships:** `sources`, `accounts`, `feed_items` (cascade delete).

### `app/models/connected_account.py` — `connected_accounts`

Stores **OAuth credentials** from iOS (provider `google`).

| Column | Purpose |
|--------|---------|
| `access_token`, `refresh_token` | Gmail API |
| `token_expires_at` | Refresh logic |
| `email` | Profile address |

**Relationships:** `user`, `sources` using this account.

### `app/models/source.py` — `sources`

A **connector instance** (e.g. one Gmail inbox per user).

| Column | Purpose |
|--------|---------|
| `type` | `"gmail"` |
| `config` | JSONB — e.g. `last_internal_date` for incremental sync |
| `connected_account_id` | FK to tokens |
| `last_synced_at` | Updated after Gmail pull |

**Relationships:** `user`, `account`, `feed_items`.

### `app/models/feed_item.py` — `feed_items`

Canonical **unified inbox row** on the server.

| Column | Purpose |
|--------|---------|
| `external_id` | Gmail message id |
| Unique `(source_id, external_id)` | Dedup |
| `title`, `sender`, `body`, `url` | Content |
| `published_at`, `ingested_at` | Timeline |
| `is_read`, `is_muted`, `priority` | State (0–3) |
| `rank_category`, `rank_label` | Rule engine output |

**Relationships:** `user`, `source`.

---

## Services (`app/services/`)

### `app/services/gmail_service.py`

**`GmailService`** — talks to Gmail API using stored `ConnectedAccount` tokens.

| Method | Behavior |
|--------|----------|
| `_credentials(account)` | `google.oauth2.credentials.Credentials` from env client id/secret |
| `sync_source(db, source, account, limit=50)` | List INBOX messages, fetch metadata, upsert `FeedItem` |

**Sync details:**

- Label: `INBOX` only (read-only).  
- Incremental: `source.config["last_internal_date"]` → Gmail `q=after:…`.  
- Refreshes expired access token when refresh token present.  
- New/updated items scored via **`PrioritizationService.resolve_full`**.  
- Updates `source.config` and `source.last_synced_at`.

**Connects to:** `feed.sync_feed` route, `ConnectedAccount`, `Source`, `FeedItem`, `prioritization_service`.

### `app/services/ranking_service.py`

**`RankingService`** — keyword + sender-domain rules (careers, finance, security, newsletters, etc.).

| Type | Role |
|------|------|
| `RankCategory` | Enum: `job_interview`, `job_rejection`, … |
| `RankRule` | keywords, optional domains, priority, category, score, label |
| `RankResult` | `priority`, `category`, `label` |
| `resolve(title, body, sender)` | Best matching rule (highest score wins) |

**Connects to:** `feed.rerank_feed`, `prioritization_service`, `gmail_service` on ingest.

See [RANKING.md](RANKING.md) for rule list and examples.

### `app/services/prioritization_service.py`

Thin **wrapper** around `RankingService` for backward compatibility:

- `resolve(...)` → priority int only  
- `resolve_full(...)` → full `RankResult`  

**Used by:** `GmailService` during sync.

---

## Request lifecycle examples

### iOS connect + first sync

```text
POST /api/auth/register          → User row + JWT
POST /api/accounts/gmail/link    → ConnectedAccount + Source
POST /api/feed/sync              → GmailService.sync_source → FeedItem rows
POST /api/feed/rerank            → RankingService on all FeedItems
GET  /api/feed?limit=200         → FeedItemOut[] → iOS SwiftData
```

### Mark read from iOS

```text
PATCH /api/feed/{uuid}  { "is_read": true }
  → feed.py patch_item → commit → FeedItemOut
```

### Disconnect

```text
DELETE /api/accounts/gmail
  → delete feed items for Gmail sources → delete sources → delete ConnectedAccount
```

---

## Database relationships

```text
User
 ├── ConnectedAccount (google tokens)
 ├── Source (gmail) ──► ConnectedAccount
 │        └── FeedItem (many)
 └── FeedItem (also linked to User for queries)
```

---

## File index (quick reference)

| File | One line |
|------|----------|
| `main.py` | FastAPI app factory + routers |
| `core/config.py` | Environment settings |
| `core/database.py` | Engine, sessions, `init_db` |
| `core/security.py` | JWT create/decode |
| `api/dependencies.py` | Auth + DB injection |
| `api/routes/auth.py` | Register + me |
| `api/routes/accounts.py` | Gmail link/unlink, list sources |
| `api/routes/feed.py` | List, patch, sync, rerank |
| `api/routes/settings.py` | Stub |
| `schemas/auth_schema.py` | Auth DTOs |
| `schemas/account_schema.py` | Gmail link DTOs |
| `schemas/feed_schema.py` | Feed DTOs |
| `models/user.py` | User table |
| `models/connected_account.py` | OAuth tokens |
| `models/source.py` | Connector config |
| `models/feed_item.py` | Inbox messages |
| `models/__init__.py` | Model exports for metadata |
| `services/gmail_service.py` | Gmail pull + upsert |
| `services/ranking_service.py` | Rule engine |
| `services/prioritization_service.py` | Ranking wrapper |

---

## iOS ↔ backend contract

| iOS | Backend |
|-----|---------|
| `BackendAPI.register` | `POST /api/auth/register` |
| `Authorization: Bearer` | `dependencies.get_current_user` |
| `BackendAPI.linkGmail` | `POST /api/accounts/gmail/link` |
| `BackendAPI.syncFeed` | `POST /api/feed/sync` |
| `BackendAPI.rerankFeed` | `POST /api/feed/rerank` |
| `BackendAPI.fetchFeed` | `GET /api/feed` |
| `BackendAPI.patchItem` | `PATCH /api/feed/{id}` |
| `FeedItemDTO.body` | `FeedItem.body` |
| `InboxItem.snippet` | same field, renamed on client |
| `FeedItemDTO.rank_*` | `FeedItem.rank_category/label` |

---

## What is not implemented on the backend yet

- Persistent user settings API (`settings.py` stub)  
- RSS / Reddit / other `Source.type` handlers  
- Background worker / scheduled sync  
- Server-hosted Google OAuth redirect (tokens come from iOS today)  
- Alembic migrations (uses `create_all` on startup)  
- Push notifications  

For the Swift side of the same flows, see [FRONTEND_ARCHITECTURE.md](FRONTEND_ARCHITECTURE.md).
