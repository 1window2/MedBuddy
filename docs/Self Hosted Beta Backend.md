# MedBuddy Self-Hosted Beta Backend

## Decision

The beta backend runs FastAPI, PostgreSQL, and Redis on a team-controlled
computer. Firebase remains on the no-cost plan for Authentication, App Check,
and FCM. Real phone-number sign-in and SMS MFA stay disabled because SMS
verification requires billable Firebase service access.

The repository retains the former Google Cloud workflows for architecture
history, but every GCP job is disabled. Self-hosted maintenance runs inside the
FastAPI process.

## Runtime topology

~~~text
Android application
        |
        | HTTPS
        v
Tailscale Funnel or router TCP 443 forwarding
        |
        v
Caddy (direct-public profile only)
        |
        v
FastAPI :8080 ---- PostgreSQL :5432
        |
        +---------- Redis :6379
        |
        +---------- Firebase Auth / App Check / FCM
~~~

Only the HTTPS entry point is public. PostgreSQL and Redis never publish host
ports. The FastAPI host port binds to loopback so Tailscale Funnel can proxy it
without exposing port 8000 to the LAN.

## First-time configuration

1. Install Docker Desktop or Docker Engine with the Compose plugin.
2. Copy backend/.env.self-hosted.example to backend/.env.self-hosted.
3. Replace every placeholder. Use a long URL-safe PostgreSQL password because
   Compose inserts it into a SQLAlchemy URL.
4. Keep the Firebase Admin JSON outside the repository and set its absolute path
   in FIREBASE_ADMIN_CREDENTIALS_PATH.
5. Keep FIREBASE_ALLOW_PHONE_AUTH=false; the Compose file enforces it.

Start the private stack:

~~~powershell
docker compose --env-file backend/.env.self-hosted -f compose.self-hosted.yml up -d --build
docker compose --env-file backend/.env.self-hosted -f compose.self-hosted.yml ps
Invoke-RestMethod http://127.0.0.1:8000/ready
~~~

The backend container waits for PostgreSQL and Redis, applies the versioned
Alembic migrations, then starts the API. Production readiness fails closed if
the database revision, Firebase verifier, App Check verifier, or Redis is not
ready.

## Option A: temporary Tailscale Funnel

Tailscale Funnel is suitable for the approximately two-week bridge before the
dedicated server arrives. It provides a public HTTPS ts.net address without
router changes or a Cloudflare subscription.

~~~powershell
tailscale funnel --bg http://127.0.0.1:8000
tailscale funnel status
~~~

Compile the exact HTTPS URL into MEDBUDDY_API_BASE_URL, including
/api/v1/medication. Test it with the phone on cellular data. Funnel is still a
beta service and has non-configurable bandwidth limits, so it is a bridge rather
than the permanent ingress.

## Option B: direct router port forwarding

Direct forwarding works only when all of the following are true:

- The router receives a publicly reachable IPv4 address instead of CGNAT.
- The ISP permits inbound TCP 80 and 443.
- The server has a DHCP reservation or static LAN address.
- A domain or dynamic-DNS hostname resolves to the router's public address.
- Windows Firewall or the Linux firewall allows only the intended web ports.
- The server stays connected to that router and does not sleep.

Do not forward ports 8000, 5432, or 6379. Start the optional Caddy profile and
forward router TCP 80 and 443 to the server's corresponding ports:

~~~powershell
docker compose --env-file backend/.env.self-hosted -f compose.self-hosted.yml --profile direct-public up -d --build
~~~

Caddy obtains and renews the TLS certificate and proxies only HTTPS traffic to
FastAPI. Set MEDBUDDY_PUBLIC_HOSTNAME to the real DNS name before startup.
The Android release client rejects raw HTTP, localhost, private IP addresses,
credentials, query strings, and non-contract paths.

If the router WAN address differs from the public address reported by an
external IP-check service, or lies in a private/shared range such as
100.64.0.0/10, direct forwarding is not reliable; use Funnel instead.

## Moving to the dedicated mini PC

1. Stop writes to the temporary backend.
2. Create a PostgreSQL pg_dump backup and verify that it can be listed or
   restored into a temporary database.
3. Install the same repository revision and Docker Compose configuration on the
   mini PC.
4. Restore PostgreSQL, copy only required catalog/runtime data, and start the
   stack.
5. Move the stable DNS hostname to the new router/server or enable a new
   temporary Funnel hostname.
6. Verify /health, /ready, authentication, prescription upload, saved
   medication, schedules, reminders, caregiver links, and FCM from cellular
   data before retiring the temporary host.

The N95/8 GB system should use one API container and bounded image-processing
concurrency. Configure automatic restart after power loss, disable sleep, apply
security updates, keep external backups, and use a small UPS if availability
matters.

## Meaning of standalone

For this beta, standalone means that the installed Android application needs no
USB cable, ADB session, developer computer connection, or same-LAN address. It
still requires Internet access to the self-hosted API, Firebase, Gemini, and the
Korean public-data APIs; it is not an offline application.
