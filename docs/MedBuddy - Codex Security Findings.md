# MedBuddy Codex Security Finding Disposition

Audit date: 2026-08-21

Target: final v0.1.0 security branch from merged `main`

Scope: all 42 current Codex Security reports, every available Patch tab, and
the 19 resolved review threads from merged PR #74

## Method

Each report was read in the authenticated Codex Security UI and checked against
the current source, tests, `SECURITY.md`, and the beta security/class UML. Eight
findings exposed a Patch tab; those patches were reviewed as proposals rather
than applied blindly. The current implementation was then tested at its real
trust boundaries.

Twenty-five findings required a change and 17 had a reported vulnerable state
that was already removed by the recovered beta work. The later review threads
also required corrections before merge.
"Already resolved" means the current tree contains the relevant control; it
does not mean the original report was invalid.

## PR #74 post-scan review corrections

| Review concern | Final control |
| --- | --- |
| A device push token could survive sign-out | Strict sign-out unregisters the token while the Firebase bearer token is still valid. Provider sign-out and local listener teardown happen only after server confirmation; failure leaves the authenticated session retryable. |
| Production disabled inline pill-catalog refresh before a seed existed | A one-shot `catalog-bootstrap` service applies Alembic migrations and atomically seeds all three shared catalogs before FastAPI and Cloudflare Tunnel can become ready. `/ready` requires nonempty basic, approval, and pill-reference tables. |
| Catalog retry was blocked by the interactive negative cache | Full-catalog page fetches explicitly bypass the short interactive failure cache while retaining bounded retry counts, timeouts, and the cross-process sync lock. |
| DELETE request bodies bypassed the global size limit | `RequestBodyLimitMiddleware` now covers DELETE alongside POST, PUT, and PATCH; regression tests cover both content-length and streamed-body overflow. |
| Client-side deletion could purge data before Firebase recent-login failure | Credential-backed deletion now requires a recent server-verified `auth_time`. The backend records a retry-safe tombstone, purges data, and deletes the verified Firebase subject through Admin SDK under the same account transaction lock used by ordinary requests. |
| Push-token registration could finish after strict sign-out cleanup | Push startup and every token registration are tracked as lifecycle operations. Strict sign-out blocks new registrations, waits for in-flight registration, and only then unregisters the final token. |
| Production catalog data became stale after the one-time bootstrap | A dedicated `catalog-refresh` service performs a full atomic MFDS synchronization on a configurable weekly cadence, with bounded retries and an explicit failure backoff. |
| Clearing prescription state could leave app-created camera captures behind | Prescription image ownership is explicit: app-created camera files are deleted after active OCR completes, while user-owned gallery originals are never deleted. |
| Medication reminders could survive sign-out or account deletion | Session teardown cancels the authenticated replenishment task and all pending patient `schedule:` notifications before provider sign-out. Account deletion performs the same cleanup before its destructive backend request. |
| Long medication courses lost reminders after the 14-day device window | The bounded 14-day window is retained for OEM safety and is replenished twice daily by an authenticated Workmanager task using current server settings and schedules. |
| Full catalog refresh retained records withdrawn upstream | Complete basic and approval refreshes assign per-run generation tokens and atomically prune rows not observed in the successful MFDS response. Failed and page-limited jobs preserve the prior catalog. |
| Reserved characters in the PostgreSQL password broke Compose database URLs | Compose passes separate structured database fields. SQLAlchemy renders the URL and escapes the raw password, while PostgreSQL receives the same unmodified secret. |

## High severity

| ID | Finding | Disposition | Verified control |
| --- | --- | --- | --- |
| `4ee5cc54a6f08191b8c476879b01ded2` | Production deploy allows Firebase anonymous API access | Fixed on main before this audit | The dormant Cloud Run workflow rejects anonymous Firebase identities; self-hosted guest access remains an explicitly authenticated Firebase anonymous principal. |
| `72d651dbea5c8191ac42b085e871f5bc` | Concurrent prescription image preprocessing can exhaust resources | Fixed in this branch | Pillow header pixel limit runs before decode, and preprocessing uses a single-worker executor. |
| `cf40175dd2988191ac0b07349bcb36df` | Regex DoS in daily frequency parsing | Fixed in this branch | Numeric matching cannot restart inside an arbitrarily long digit run; regression test covers the adversarial input. |
| `f57513cdfd888191b3001364509782c4` | Unauthenticated reminder settings can be changed by hash | Already resolved in beta | Protected routes use verified authentication/App Check and server-derived ownership instead of accepting the hash as authority. |
| `f0105020e29c8191aa816d4c6aff4509` | Home link screen exposes unauthenticated caregiver linking | Already resolved in beta | The client no longer exposes an editable identity boundary; the physical-device anonymous view cannot create or register a link. |
| `be803f617cf481918039d89dab38015d` | Editable user hash exposes caregiver links | Already resolved in beta | User identity is derived from the verified principal; hash fields are no longer editable credentials. |
| `a73bc23032548191ba138f0dad71e6d9` | Unauthenticated users can mint caregiver link codes | Already resolved in beta | Link-code operations require authenticated, server-owned identity and retain expiry/single-use checks. |
| `478a041c00348191b8e534c2d885737d` | README exposes unauthenticated API on all interfaces | Fixed in this branch | Direct startup binds loopback; Android documentation and client configuration no longer permit private-LAN or clear-text API endpoints. |
| `c7884ee22fd48191aeaee21793044d59` | Backend PR CI can expose API secrets to PR code | Fixed in this branch | Pull-request import/tests receive fixed fake values and never interpolate repository secrets. |

## Medium severity

| ID | Finding | Disposition | Verified control |
| --- | --- | --- | --- |
| `a4f32bf8bd5081919241c84920994265` | Catalog refresh can prune on partial API data | Fixed in this branch | Full refresh refuses to prune an established catalog when the candidate retains less than 80 percent of the prior rows; the transaction rolls back for basic, approval, and pill catalogs. |
| `118bbbfa807c819181a0eb15cc30bd94` | Release workflow exposes signing secrets to broad refs | Fixed in this branch and GitHub environment | The workflow accepts only the protected `main` ref. The `beta-android` environment independently requires owner approval and an exact main-branch deployment policy; beta branches and tags cannot receive signing material. |
| `45b648cbdf348191b7145d3638ddbead` | Public readiness probe hits production dependencies | Fixed in this branch | `/ready` remains public for infrastructure probes, but requests are IP-rate-limited and dependency checks are coalesced behind a five-second process-local cache. |
| `6e79917f1d448191b88581c2c84e4030` | Saved-list reads now trigger third-party medication lookups | Fixed after verified review | Saved-list and caregiver reads return persisted image metadata only; they no longer call MFDS or commit enrichment as a GET side effect. |
| `8d0d695912108191a19a8311c5153486` | Unauthenticated health recommendation LLM endpoint | Already resolved in beta | Recommendation generation is protected by the verified request principal and bounded request policy. |
| `1b4134d204dc81918ea1d955c21b0c71` | Medication detail screen loads untrusted image URLs | Fixed in this branch | All medication images require HTTPS on the exact MFDS image host with no credentials or alternate port. |
| `1856320722e481918620380d6ae93f7c` | Saved-medication UI auto-loads untrusted image URLs | Fixed in this branch | Saved-list thumbnails and dialogs use the same centralized image trust policy. |
| `dcc311db1c688191a0a60c655156e67a` | Unbounded medication keyword expansion enables request amplification | Fixed in this branch | Normalized lookup variants are deduplicated and capped at 24. |
| `9baed3ca490881919a292eadd0a4b388` | Prescription upload logs leak user-controlled filenames | Already resolved in beta | Upload logs contain only the bounded byte count, not the client filename, media type, or OCR text. |
| `3e237f97ed488191b154269bc1574f93` | Release Android app enables cleartext medical-data API traffic | Already resolved in beta | Release manifest disables cleartext; release/profile URL validation requires a public HTTPS origin. |
| `6f09c0c2172c8191b2f60c29acc34a43` | Issue templates solicit unredacted medical data | Fixed in this branch | Templates prohibit real medical/personal data and route sensitive reports to the private security channel. |
| `d3b69f10ca4081919e13b6e8e230cdaa` | Oversized identify input bypasses raw length guard | Already resolved in beta | Request schemas and normalized-name validation bound the identify input. |
| `b4aa81a7f21c8191b78aac3b96dc79ba` | Hard-coded HTTP prescription image upload endpoint | Already resolved in beta | The client uses the validated shared API base URL; release/profile builds reject HTTP/local/private origins. |
| `5d22136034b08191a4f824ad7a061107` | Unbounded prescription image upload enables denial of service | Already resolved in beta | Middleware and route limits cap encoded upload bytes; this branch adds pre-decode pixel limits. |
| `25b51098fb208191a764db6402049558` | Unbounded unauthenticated OCR parsing endpoint | Already resolved in beta | Authentication, body bounds, and OCR execution controls cover the legacy JSON path. |
| `8d603b65ba6c8191937b4873d4c5ae7d` | Unauthenticated save endpoint allows unbounded DB writes | Already resolved in beta | Save uses verified ownership, bounded schemas, deduplication, and transaction controls. |
| `b81078e0fdd88191a5c1b3fd779dab71` | Unauthenticated identify endpoint can burn Gemini quota | Already resolved in beta | Protected identity, request bounds, timeouts, and capacity gates precede Gemini work. |

## Low severity

| ID | Finding | Disposition | Verified control |
| --- | --- | --- | --- |
| `8f183c08b844819185f2fadbf4f7da98` | Overdue-first dashboard can encourage dose stacking | Fixed in this branch | The dashboard prefers the next future dose whenever one remains. When every remaining slot is overdue, it shows the most recent missed slot with neutral guidance to check the prescription instead of directing immediate consumption. |
| `ef9f49949edc8191ae02743da8011a58` | Expired medication records are no longer purged on reads | Already resolved in beta | Retention/cleanup is explicit and no longer depends on a read-side destructive effect. |
| `c40e2f6828bc81918c1de15552fc5629` | Process-wide OCR fallback cache leaks recent medication lookups | Fixed in this branch | The bounded fallback cache is request-controller-instance state, not process-global state. |
| `70b229b197ac81918e43d0983ce8c8b4` | Upload endpoint no longer rejects non-image files | Fixed in this branch | Prescription upload rejects missing/non-image media types with HTTP 415 before reading the body. |
| `18a5b33a154c8191a0e2ff1baf584ca1` | Android release builds are signed with debug key | Already resolved in beta | Release signing is environment supplied and fail-closed in the signed-release workflow; debug signing is not the release default. |

## Informational

| ID | Finding | Disposition | Verified control |
| --- | --- | --- | --- |
| `9323ab8eaadc819186d95e88bed825b2` | SQLite account lock enables shared thread-pool exhaustion | Fixed in this branch | Development SQLite account serialization now waits on an async lock with the existing five-second bound, so contenders do not occupy Starlette/AnyIO worker threads. PostgreSQL advisory locking is unchanged. |
| `a176ccb5a38881918b91a2518615f022` | Crop failures leave full prescription photos on disk | Fixed in this branch | Guided-camera crop processing deletes the app-owned source in a failure-safe finalizer and removes a partial derived file when processing or source cleanup fails. |
| `63e2e184e1988191bbf5127a1a2778ab` | Patient aliases exposed in lock-screen caregiver alerts | Fixed in this branch | Completed-dose and missed-deadline system notifications use generic patient text even when a local alias exists; patient identity remains in the private authenticated tap payload. |
| `5df0a574c8148191b552d13f27a13fc0` | Unanchored APK cert parser allows digest spoofing | Fixed in this branch | The parser accepts only the anchored `Signer #N certificate SHA-256 digest` line and requires exactly 64 hexadecimal characters after normalization. |
| `707b27f248348191a49eebcfcc1927ee` | AAB verifier no longer fails on jarsigner warnings | Fixed in this branch | `jarsigner -verify -strict` makes unsigned entries and other security warnings release-blocking before the certificate comparison. |
| `a17d9ff1f0248191980988706f2afb33` | Patient labels exposed in caregiver notifications | Fixed in this branch | Background and foreground caregiver notifications use generic patient text; the patient hash remains only in the private navigation payload. |
| `59efa5d1bf2481919d37cfa7a5345b62` | OCR region text can expose patient identifiers | Fixed in this branch | OCR-region output contains only validated categories and coordinates; all model-returned region text is blanked before the API response. |
| `ec180b769a248191a20c1a52a60775e7` | Multiple-pill photos can bypass new quality gate | Fixed in this branch | Additional tablet/capsule plurality phrases are rejected; a synthetic non-pill image was rejected on device. |
| `f1768a8f0b1081919b095853798ef5c0` | Medication detail screen hides full usage instructions | Fixed in this branch | Detail values are no longer truncated to two items or three lines and render vertically at full width. |
| `65a2b25d93108191840b308c20954fb8` | Ambiguous OCR prefixes can canonicalize to wrong drug | Fixed in this branch | Prefix correction succeeds only when both catalogs produce exactly one distinct item name. |
| `558a62417c588191bf71fd1a41583f90` | Completed-only slots can overstate medication progress | Fixed in this branch | Explicit schedule slots and daily frequency determine the denominator before completion-state fallback. |
| `010fe22fbf4081919c315395ef8ad7e3` | Gradle wrapper lacks executable bit | Fixed in this branch | `frontend/android/gradlew` is tracked as executable (`100755`). |
| `8d6f689b0fc881919f9f3d6aa760a8a3` | Per-card save state permits overlapping saves | Fixed in this branch | View-model guard rejects overlapping card/all saves and all save controls disable while one is active. |
| `b32d0375a9d08191b20b5229a670f99c` | Gemini key validation removed instead of deferred | Already resolved in beta | Startup validation is environment/auth-mode aware, while CI uses non-secret placeholders. |
| `7a3a51700a1c81918301c1db292bff5f` | Malformed Flutter platform files break app builds | Already resolved in beta | Platform files are valid; Flutter analyze, tests, debug APK, and release-mode APK assembly all succeed. |

## Verification evidence

- Backend: 373 passed and 2 PostgreSQL-gated tests skipped.
- Flutter: 252 tests passed; `flutter analyze --no-pub` reported no issues.
- Focused security suites included 8 repository/deployment configuration
  tests, 134 medication-image boundary tests, 37 prescription OCR tests, and
  12 caregiver-notification tests.
- UML: PlantUML 1.2026.6 source validation and local rendering passed; the
  class and overall sequence PNGs were regenerated without uploading the UML.
- Android release-shaped build: unsigned v0.1.0 APK assembled with a public
  HTTPS placeholder; manifest reports `usesCleartextTraffic=false`.
- Prior physical-device beta: the user verified standalone startup on a
  network-separated Android device, guest and Google authentication,
  prescription analysis/masking/save, saved medication and schedules,
  completion/undo, reminders, health guidance, images, settings persistence,
  and force-stop session restoration. The feedback from that run is reflected
  in the current source and regression tests; the new signed artifact still
  requires a final repeat pass.
- Production ingress: `https://api.medbuddy.pp.ua` reaches the dedicated mini
  PC through Cloudflare Tunnel. PostgreSQL and Redis remain private, and the
  host loopback port is diagnostic only. Tailscale Funnel, Caddy, laptop LAN
  addresses, ADB forwarding, and user-specific endpoints are not part of the
  tracked production configuration.
- Local hygiene: real `.env`, Firebase JSON, Android local properties, signing
  keys, SQLite runtime databases, generated dependency caches, and APKs remain
  ignored and absent from the PR diff.

## Remaining release gates

No release was made. PR #74 has been normal-merged, but this final security
branch must still pass its own CI and Codex review and be normal-merged into
`main`. The resulting commit must then be deployed to the mini PC,
`pill_identification_references` must be populated and queried successfully,
and a newly signed artifact must complete the network transition/outage,
sign-out privacy, deletion, data-preserving update, and two-device caregiver
gates. These are deployment proofs, not reasons to weaken the fail-closed
controls.
