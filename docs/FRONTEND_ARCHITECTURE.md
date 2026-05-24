# iOS frontend architecture

This document describes every Swift source file in **UnifiedInbox**, what it does, and how data flows between layers.

Related: [BACKEND_ARCHITECTURE.md](BACKEND_ARCHITECTURE.md) · [BACKEND_INTEGRATION.md](BACKEND_INTEGRATION.md) · [RANKING.md](RANKING.md)

---

## Layer overview

```text
┌─────────────────────────────────────────────────────────────────┐
│  Views (SwiftUI)          Onboarding, Inbox, Sources, Settings    │
└───────────────────────────────┬─────────────────────────────────┘
                                │ binds to
┌───────────────────────────────▼─────────────────────────────────┐
│  ViewModels (@Observable)   Inbox, Sources, Settings logic      │
└───────────────────────────────┬─────────────────────────────────┘
                                │ calls
┌───────────────────────────────▼─────────────────────────────────┐
│  Services                   Sync, API, Gmail, Auth, Priority      │
└───────────────┬─────────────────────────────┬───────────────────┘
                │                             │
┌───────────────▼──────────────┐   ┌──────────▼────────────────────┐
│  SwiftData (Models)          │   │  Keychain + bundle .env files │
│  InboxItem, ConnectedSource  │   │  OAuth.env, API.env           │
└──────────────────────────────┘   └───────────────────────────────┘
                │
                │  optional HTTP (when API.env present)
                ▼
         FastAPI backend (see BACKEND_ARCHITECTURE.md)
```

---

## App entry

### `App/UnifiedInboxApp.swift`

- `@main` entry point.
- Creates `WindowGroup` with `RootView()`.
- Registers SwiftData **`modelContainer`** for `InboxItem` and `ConnectedSource` (persistent on device).

### `App/RootView.swift`

- Reads `@AppStorage("hasOnboarded")`.
- If false → `OnboardingView`; if true → `MainTabView` (three tabs).
- **`MainTabView`**: hosts `InboxView`, `SourcesView`, `SettingsView`.

**Connects to:** all top-level views; owns no business logic.

---

## Models (`Models/`)

SwiftData `@Model` types and shared enums. These are the **local database schema**.

### `Models/InboxItem.swift`

One row in the unified feed (cached copy of a message).

| Field | Purpose |
|-------|---------|
| `id` | UUID; matches server `feed_items.id` when using backend |
| `externalId` | Gmail message id (dedup key with `sourceId`) |
| `sourceId` | Links to `ConnectedSource.id` |
| `title`, `sender`, `snippet` | Display fields (`snippet` = server `body`) |
| `urlString` | Gmail deep link |
| `publishedAt`, `isRead`, `isMuted` | Timeline state |
| `priorityRaw` | 0–3 (`ItemPriority`) |
| `rankCategoryRaw`, `rankLabel` | Career/ranking tags from rules |

**Connects to:** `@Query` in `InboxView`; written by `SyncService.mergeFeed`; read by views and `PriorityService`.

### `Models/ConnectedSource.swift`

Represents a connected account (today: one Gmail source).

| Field | Purpose |
|-------|---------|
| `name` | Usually Gmail address |
| `typeRaw` | `SourceType` (only `.gmail` today) |
| `configData` | JSON blob → `GmailConfig` |
| `lastSyncedAt` | Shown in Sources UI |

**`gmailConfig`** (decoded from `configData`):

- `email` — account address  
- `lastInternalDate` — incremental sync cursor (local-only path)  
- `backendSourceId` — server `sources.id` when using API  

**Connects to:** `SyncService` upserts after `BackendAPI.linkGmail`; `@Query` in `SourcesView`.

### `Models/Enums.swift`

Shared types (not SwiftData models):

- **`SourceType`** — `gmail` only  
- **`ItemPriority`** — critical / high / medium / low (lower int = more urgent)  
- **`InboxFilter`** — all, unread, **careers**, critical, high, medium, low  
- **`GmailConfig`** — codable config for `ConnectedSource`  
- **`InboxItemDraft`** — transient struct from `GmailService` before insert  

**Note:** `RankCategory` lives in `PriorityService.swift`, not here.

---

## ViewModels (`ViewModels/`)

`@Observable` + `@MainActor` state and actions. Views hold `@State private var vm = …` and call methods with `ModelContext`.

### `ViewModels/InboxViewModel.swift`

| Responsibility | Detail |
|----------------|--------|
| Refresh | `SyncService.refresh(context:auth:)` |
| Filter / search | `matchesFilter(_:)` — priority, careers (`job_*` category), unread, hide-low setting |
| Mark read | Local save + `BackendAPI.patchItem` when API + JWT exist |
| Delete | Local SwiftData delete only |

Also defines **`AppSettings`** (UserDefaults): `hideLowPriority`, `retentionDays`, `backendEmail` (used for `POST /auth/register`).

**Connects to:** `InboxView`, `ItemDetailView` (mark read), `SyncService`, `BackendAPI`, `PriorityService`.

### `ViewModels/SourcesViewModel.swift`

| Method | Flow |
|--------|------|
| `connect` | `GoogleAuthService.signIn()` → set `AppSettings.backendEmail` → `SyncService.refresh` |
| `sync` | `SyncService.refresh` only |
| `disconnect` | Google sign-out → `BackendAPI.unlinkGmail` + clear JWT → delete all local sources/items |

**Connects to:** `SourcesView`, `GoogleAuthService`, `SyncService`, `GmailService` (profile email).

### `ViewModels/SettingsViewModel.swift`

- Mirrors `AppSettings` into UI toggles/stepper.
- **`deleteAll`** — wipes SwiftData + `GoogleAuthService.signOut()` (does not always hit backend unless user used Sources disconnect).
- **`prune`** — deletes items older than retention via `AppSettings.prune`.

**Connects to:** `SettingsView`, `AppSettings`, SwiftData.

---

## Views (`Views/`)

SwiftUI only; minimal logic.

### `Views/Onboarding/OnboardingView.swift`

Multi-step intro → step 2 triggers **Google sign-in** + `SyncService.refresh` → sets `hasOnboarded` via callback.

**Connects to:** `GoogleAuthService`, `SyncService`, `GoogleConfig` hints.

### `Views/Inbox/InboxView.swift`

- `@Query` all `InboxItem` sorted by priority then date.
- Filters through `InboxViewModel.matchesFilter`.
- List → `ItemDetailView`; swipe read/unread/delete.
- Pull-to-refresh + toolbar → `vm.refresh`.

**Connects to:** `InboxViewModel`, `InboxRowView`, `ItemDetailView`.

### `Views/Inbox/InboxRowView.swift`

Single row UI: unread dot, title, **rank label** chip, priority chip, sender, snippet, date.

**Connects to:** `InboxItem`, `Formatters`, `ItemPriority.color`.

### `Views/Inbox/ItemDetailView.swift`

Full message: priority, rank label, body, “Open in Gmail”. On appear marks read (local + optional `BackendAPI.patchItem`). Toolbar mute toggle (local only).

### `Views/Sources/SourcesView.swift`

- Shows `APIConfig.hint` (backend URL status).
- Gmail connect / sync / disconnect UI.
- Placeholder “Coming later” for RSS/Reddit.

**Connects to:** `SourcesViewModel`, `@Query` `ConnectedSource`.

### `Views/Settings/SettingsView.swift`

Form: hide low priority, retention days, delete-all confirmation.

**Connects to:** `SettingsViewModel`.

---

## Services (`Services/`)

Core behavior and external I/O.

### `Services/GoogleAuthService.swift`

**Also contains:** `GoogleConfig`, `EnvFile`, `AuthError`.

| Piece | Role |
|-------|------|
| `GoogleConfig` | Reads `OAuth.env` from bundle; builds Google OAuth URL |
| `EnvFile` | Parses `KEY=value` env files (`OAuth`, `API`) |
| `GoogleAuthService` | `ASWebAuthenticationSession` → exchange code for tokens → `KeychainStore` |

**Public API:** `signIn()`, `signOut()`, `validAccessToken()`, `isSignedIn`.

**Connects to:** `KeychainStore`, `SourcesViewModel`, `OnboardingView`, `SyncService`, `InboxViewModel` (refresh).

### `Services/KeychainStore.swift`

Stores Google **access/refresh token** and expiry under Keychain service `com.unifiedinbox.google`.

**Connects to:** `GoogleAuthService`, `SyncService` (token payload for backend link).

### `Services/GmailService.swift`

Direct **Gmail REST** (used in **local-only** mode and for profile email).

- `fetchProfileEmail(token:)`  
- `fetchInbox(token:afterInternalDate:)` — INBOX, metadata, ~50 msg cap, pagination  
- `fetchMessage` — subject, from, snippet, internal date  

**Connects to:** `SyncService.refreshLocalOnly`, `SourcesViewModel.connect`.

### `Services/APIConfig.swift`

Reads `API.env` → `API_BASE_URL`. Exposes `isConfigured`, `baseURL`, `hint`.

**Connects to:** `SyncService` (backend vs local branch), `BackendAPI`, `SourcesView` status line.

### `Services/BackendSessionStore.swift`

Keychain storage for backend **JWT** (`com.unifiedinbox.backend.session`).

**Connects to:** `BackendAPI` (Authorization header), `SyncService.ensureBackendSession`, disconnect flow.

### `Services/BackendAPI.swift`

HTTP client for FastAPI. DTOs: `FeedItemDTO`, `SourceDTO`, `SyncResultDTO`, `TokenResponse`.

| Method | Backend route |
|--------|----------------|
| `register(email:)` | `POST /api/auth/register` |
| `linkGmail(...)` | `POST /api/accounts/gmail/link` |
| `syncFeed()` | `POST /api/feed/sync` |
| `rerankFeed()` | `POST /api/feed/rerank` |
| `fetchFeed()` | `GET /api/feed?limit=200` |
| `patchItem(id:isRead:)` | `PATCH /api/feed/{id}` |
| `unlinkGmail()` | `DELETE /api/accounts/gmail` |

Uses `URLSession`, JSON encode/decode, flexible ISO8601 dates.

**Connects to:** `SyncService`, `InboxViewModel`, `ItemDetailView`, `SourcesViewModel`.

### `Services/SyncService.swift`

**Central orchestrator** for loading mail.

```text
refresh()
  ├─ APIConfig.isConfigured?
  │    YES → refreshViaBackend()
  │           1. ensureBackendSession (register if no JWT)
  │           2. BackendAPI.linkGmail (upload Google tokens)
  │           3. upsertLocalSource
  │           4. BackendAPI.syncFeed
  │           5. BackendAPI.rerankFeed
  │           6. BackendAPI.fetchFeed → mergeFeed
  │    NO  → refreshLocalOnly()
  │           GmailService.fetchInbox → insert InboxItem
  └─ rerankAllLocal() (PriorityService on all items)
```

**`mergeFeed`:** Upsert by `(externalId, sourceId)`; new items use **server UUID** as `InboxItem.id` so PATCH works.

**Connects to:** Everything above + SwiftData `ModelContext`.

### `Services/PriorityService.swift`

**Also contains:** `RankCategory`, `RankResult`, `RankRule`.

Keyword + sender-domain rules (interviews, rejections, offers, bank, security, newsletters, etc.). Returns priority, category, display label.

- Used on **local sync** ingest and **`rerankAllLocal`** after merge.  
- **`isCareers(categoryRaw:)`** — powers Careers filter in `InboxViewModel`.

Mirrors backend `ranking_service.py` (see [RANKING.md](RANKING.md)).

---

## Utilities (`Utilities/`)

### `Utilities/Formatters.swift`

- `Formatters.date(_:)` — relative/short dates for UI.  
- **`extension ItemPriority`** — `color` for chips.

### `Utilities/PreviewData.swift`

`#if DEBUG` in-memory SwiftData container with sample items for SwiftUI previews.

**Connects to:** `#Preview` in `RootView`, `InboxView`, etc.

---

## Resources & config (not Swift, but required)

| File | Role |
|------|------|
| `Resources/OAuth.env` | `GOOGLE_CLIENT_ID`, `GOOGLE_URL_SCHEME` — must be in **Copy Bundle Resources** |
| `Resources/API.env` | `API_BASE_URL` — enables backend mode |
| `Resources/Assets.xcassets` | App icon |
| `API.env.example` / `OAuth.env.example` (project root) | Templates |

**Xcode:** `UnifiedInbox.xcodeproj` — target membership, ATS `NSAllowsLocalNetworking` for `http://127.0.0.1`.

---

## End-to-end flows (frontend-only)

### First launch (onboarding)

```text
OnboardingView → GoogleAuthService.signIn → SyncService.refresh
  → [backend path] BackendAPI.register + link + sync + fetch → SwiftData
  → RootView.hasOnboarded = true → MainTabView
```

### Pull to refresh (inbox)

```text
InboxView → InboxViewModel.refresh → SyncService.refresh
  → same sync pipeline → @Query updates list
```

### Mark read (with backend)

```text
InboxViewModel.markRead / ItemDetailView.onAppear
  → item.isRead = true (SwiftData)
  → BackendAPI.patchItem (async, fire-and-forget)
```

### Disconnect Gmail

```text
SourcesView → SourcesViewModel.disconnect
  → Google sign-out, BackendAPI.unlinkGmail, clear JWT, wipe SwiftData
```

---

## File index (quick reference)

| File | One line |
|------|----------|
| `UnifiedInboxApp.swift` | App entry + SwiftData container |
| `RootView.swift` | Onboarding vs tabs |
| `InboxItem.swift` | Message model |
| `ConnectedSource.swift` | Gmail source model + config |
| `Enums.swift` | Priority, filters, drafts |
| `InboxViewModel.swift` | Inbox logic + AppSettings |
| `SourcesViewModel.swift` | Connect/disconnect/sync |
| `SettingsViewModel.swift` | Settings + delete all |
| `OnboardingView.swift` | First-run wizard |
| `InboxView.swift` | Feed list UI |
| `InboxRowView.swift` | Row UI |
| `ItemDetailView.swift` | Message detail |
| `SourcesView.swift` | Account management |
| `SettingsView.swift` | Preferences |
| `GoogleAuthService.swift` | OAuth + EnvFile |
| `KeychainStore.swift` | Google tokens |
| `GmailService.swift` | Direct Gmail API |
| `APIConfig.swift` | Backend base URL |
| `BackendSessionStore.swift` | JWT storage |
| `BackendAPI.swift` | REST client |
| `SyncService.swift` | Sync orchestration |
| `PriorityService.swift` | Ranking rules |
| `Formatters.swift` | Dates + priority colors |
| `PreviewData.swift` | Preview fixtures |

---

## What is not in the frontend yet

- RSS/Reddit connectors (UI placeholders only)  
- Mute/sync to server  
- Swipe-unread → server PATCH  
- Dedicated rules editor screen  
- Background fetch / push  

For server-side counterparts, see [BACKEND_ARCHITECTURE.md](BACKEND_ARCHITECTURE.md).
