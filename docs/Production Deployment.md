# MedBuddy Production Deployment

## Production Topology

MedBuddy production runs on a dedicated Ubuntu mini PC.

```text
Android client
    |
    | HTTPS
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

## Start or Update Production

From the repository root:

```bash
docker compose \
  --env-file deploy/.env \
  -f compose.self-hosted.yml \
  up -d --build --wait
```

The four long-running production services must become healthy:

- `postgres`
- `redis`
- `backend`
- `cloudflared`

Before those services start, the one-shot `catalog-bootstrap` service applies
the Alembic migrations and seeds any empty shared medication catalog. A
successful deployment therefore shows `catalog-bootstrap` as exited with code
0; it is not expected to remain running.

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

Verify that the pill-identification catalog was populated:

```bash
docker compose --env-file deploy/.env -f compose.self-hosted.yml \
  exec -T postgres psql -U medbuddy -d medbuddy -tAc \
  "SELECT COUNT(*) FROM pill_identification_references;"
```

The result must be greater than zero before physical-device pill
identification is considered ready.

## Android API Endpoint

The production Android API base URL is:

```text
https://api.medbuddy.pp.ua/api/v1/medication
```

ADB, Flutter hot reload, breakpoints, and physical-device debugging do not
require the backend to run on the development laptop or on the same LAN.
