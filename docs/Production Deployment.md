# MedBuddy Production Deployment

## Production Topology

MedBuddy production runs on a dedicated Ubuntu mini PC.

```text
Android client
    |
    | HTTPS / WSS
    v
api.medbuddy.pp.ua
    |
    v
Cloudflare
    |
    | Cloudflare Tunnel
    v
cloudflared
    |
    | http://backend:8080
    v
FastAPI
    |
    +-- PostgreSQL
    +-- Redis
```

The production ingress is Cloudflare Tunnel only.

- Public hostname: `api.medbuddy.pp.ua`
- Cloudflare Tunnel: `medbuddy-production`
- Tunnel service target: `http://backend:8080`
- No router port forwarding is required.
- Tailscale Funnel is not used.
- Caddy direct-public ingress is not used.
- PostgreSQL and Redis remain on the private Docker network.
- FastAPI port `8000` is bound only to host loopback for local diagnostics.

## Local Production Configuration

The following real configuration files stay outside Git:

```text
deploy/.env
deploy/backend.env
```

Host-side secrets are stored outside the repository:

```text
~/.config/medbuddy/secrets/firebase-admin.json
~/.config/medbuddy/secrets/cloudflare-tunnel-token
```

Tracked templates are:

```text
deploy/.env.example
deploy/backend.env.example
```

Never commit the real `.env` files, Firebase Admin credential, Cloudflare Tunnel
token, API keys, database passwords, or Android signing material.

The backend environment must include one public-data credential authorized for
the configured medication services and the National Emergency Medical Center
pharmacy service. Keep the pharmacy endpoint on the backend only:

```text
PUBLIC_DATA_API_KEY=...
PHARMACY_API_BASE_URL=https://apis.data.go.kr/B552657/ErmctInsttInfoInqireService
PHARMACY_API_TIMEOUT_SECONDS=12
```

Do not place the public-data key in Flutter compile-time values. The client
sends only its current coordinates to the authenticated `/api/v1/pharmacy`
boundary when the user explicitly opens the laboratory feature.

The nearby endpoint accepts `search_mode` (`open_at_time`, `late_hours`,
`official_late_night`, `weekend_holiday`, or `all`) and an ISO-8601
`target_datetime`. Filtering happens before the response limit. Legal-holiday
months and exact-date NEMC holiday pharmacy rosters are cached in PostgreSQL;
the response reports catalog staleness and any bounded fallback. The versioned
Seoul public late-night designation overlay records its official source and
verification date and is refreshed during both bootstrap and periodic catalog
synchronization.

Set `POSTGRES_PASSWORD` once in `deploy/.env` as the raw PostgreSQL password.
The backend receives structured host/user/password fields and lets SQLAlchemy
encode the connection URL, so passwords containing URL-reserved characters
such as `@`, `:`, `/`, `?`, or `#` work without a second encoded secret.

## Start or Update Production

From the repository root:

```bash
docker compose \
  --env-file deploy/.env \
  -f compose.self-hosted.yml \
  up -d --build --wait
```

The five long-running production services must remain running or healthy:

- `postgres`
- `redis`
- `catalog-refresh`
- `backend`
- `cloudflared`

Before those services start, the one-shot `catalog-bootstrap` service applies
the Alembic migrations and seeds any empty shared medication and nationwide
pharmacy schedule catalogs. A
successful deployment therefore shows `catalog-bootstrap` as exited with code
0; it is not expected to remain running.

The separate `catalog-refresh` service performs a full atomic synchronization
every seven days by default. Each successful complete refresh removes basic,
approval, pill, and pharmacy records no longer returned by their government
sources while preserving local AI summaries for retained product identifiers.
Each catalog replacement is atomic. A failed full refresh keeps the last
committed catalog, and a deliberately page-limited maintenance job
never prunes unvisited rows. Production retries a failed full refresh after one
hour. Configure the two intervals in `deploy/.env`; do not add
`--only-if-empty` to this periodic service.

The pill catalog additionally requires complete upstream row accounting and an
exact persisted `item_seq` reconciliation. Keep
`PILL_IDENTIFICATION_KPIC_PRODUCT_FLOOR` aligned with the dated product count on
the public KPIC status dashboard before each release. A higher MFDS catalog
count is acceptable; a lower unique count fails closed and preserves the prior
generation.

The backend maintenance runner also removes linked-chat messages after the
configured retention period. The tracked production template uses 90 days:

```text
CHAT_MESSAGE_RETENTION_DAYS=90
```

Self-hosted production keeps Redis on the private Docker network and requires
it for shared request quotas. This makes API and chat limits consistent across
all backend workers instead of maintaining a separate counter per process.

## Verify

Verify the backend locally:

```bash
curl -i http://127.0.0.1:8000/ready
```

Verify the public Cloudflare path:

```bash
curl -i https://api.medbuddy.pp.ua/ready
```

Both must return HTTP 200 with the expected API contract.

Verify that the database reached the latest migration, including pharmacy
schedule provenance and structured linked-chat contexts:

```bash
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  exec -T backend alembic current
```

The reported head must be `b4e7c2d9a160`. The v0.2.0 tail adds the shared
pharmacy catalog (`8f2c6d4a1b90`), pharmacy schedule provenance and holiday
cache (`b6d14f8c2a70`), and structured chat message/context columns
(`b4e7c2d9a160`). Cloudflare Tunnel must also permit WebSocket upgrades for
`/api/v1/chat/links/*/stream`; no separate public port or second backend is
required.

Verify that the pill-identification and pharmacy catalogs were populated:

```bash
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  exec -T postgres psql -U medbuddy -d medbuddy -tAc \
  "SELECT 'pill_identification_references', COUNT(*) FROM pill_identification_references
   UNION ALL
   SELECT 'pharmacy_catalog_records', COUNT(*) FROM pharmacy_catalog_records;"
```

The pill result must also be at least `PILL_IDENTIFICATION_KPIC_PRODUCT_FLOOR`;
the pharmacy result must be greater than zero before physical-device pill
identification and nearby-pharmacy testing are considered ready.

Verify that periodic refresh is running and inspect its last synchronization:

```bash
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  ps catalog-refresh
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  logs --tail=100 catalog-refresh
```

The drug refresh log must contain `pill catalog reconciliation` with equal
`advertised_rows`/`fetched_rows` and `accepted_unique_rows`/`persisted_rows`,
zero missing or unexpected persisted rows, and a unique count at or above the
configured KPIC floor. Rejected and duplicate counts describe upstream data and
must be reviewed when they change materially.

To request an immediate, atomic refresh without waiting for the next interval:

```bash
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  run --rm catalog-bootstrap \
  python scripts/sync_drug_catalog.py --dataset all --page-size 500 --max-retries 5
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  run --rm catalog-bootstrap \
  python scripts/sync_pharmacy_catalog.py --page-size 1000 --max-retries 5
```

## Android API Endpoint

The production Android API base URL is:

```text
https://api.medbuddy.pp.ua/api/v1/medication
```

Flutter derives sibling authenticated endpoints from that trusted origin:

```text
https://api.medbuddy.pp.ua/api/v1/pharmacy
https://api.medbuddy.pp.ua/api/v1/chat
wss://api.medbuddy.pp.ua/api/v1/chat
```

Nearby-pharmacy and linked medication chat are disabled by default in user
settings. Enabling the UI does not weaken backend authentication, active-link
authorization, location minimization, or chat medication-context validation.

ADB, Flutter hot reload, breakpoints, and physical-device debugging do not
require the backend to run on the development laptop or on the same LAN.
