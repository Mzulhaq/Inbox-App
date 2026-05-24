# Gmail ranking

Unified Inbox scores each message at sync time using **keyword + sender domain** rules. The highest-scoring match wins.

## Priority levels

| Level | Value | Typical use |
|-------|-------|-------------|
| Critical | 0 | Interviews, offers, bank/security |
| High | 1 | Rejections, job updates |
| Medium | 2 | Application confirmations, default |
| Low | 3 | Newsletters, marketing |

## Careers categories

| Label | Category | Priority | Example signals |
|-------|----------|----------|-----------------|
| Interview | `job_interview` | Critical | "phone screen", "interview scheduled", Greenhouse/Lever |
| Application update | `job_rejection` | High | "regret to inform", "not moving forward" |
| Job offer | `job_offer` | Critical | "offer letter", "pleased to offer" |
| Application | `job_application` | Medium | "thank you for applying" |
| Job update | `job_update` | High | recruiter, hiring team, ATS senders |

Use the **Careers** inbox filter to show only `job_*` categories.

## Other categories

- **Finance** — bank, payment alerts
- **Security** — sign-in alerts, password reset
- **Newsletter** — unsubscribe, digest, promotional

## Where rules live

- Backend: `backend/app/services/ranking_service.py`
- iOS (local sync): `UnifiedInbox/Services/PriorityService.swift`

Keep these in sync when adding keywords.

## API

- New messages ranked on `POST /api/feed/sync`
- Re-score all stored mail: `POST /api/feed/rerank` (iOS calls this after each sync)
- Filter careers feed: `GET /api/feed?careers_only=true`

## Database

New columns on `feed_items`: `rank_category`, `rank_label`.

If Postgres was created before this change:

```sql
ALTER TABLE feed_items ADD COLUMN IF NOT EXISTS rank_category VARCHAR(64);
ALTER TABLE feed_items ADD COLUMN IF NOT EXISTS rank_label VARCHAR(64);
```

Or reset dev DB: `docker compose down -v && docker compose up -d`

## Customizing

1. Add keywords to `RULES` in `ranking_service.py`
2. Mirror in `PriorityService.swift`
3. Run sync, or call `POST /api/feed/rerank`, or pull-to-refresh on iOS

## Not built yet

- Per-user editable rules in the app
- ML / LLM classification
- Push notifications for Critical careers items
