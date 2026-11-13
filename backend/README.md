# MedBuddy Backend

FastAPI service for the MedBuddy Android app. Production runs on a dedicated
Ubuntu host behind Cloudflare Tunnel; see
[Production Deployment](../docs/Production%20Deployment.md).

## Prerequisites

- Python 3.11 (the CI target)
- Gemini API key
- Korean public data portal API key authorized for the drug, NEMC pharmacy/hospital, and KASI holiday services listed below
- Redis server, optional for local cache and rate-limit testing; required for distributed production quotas
- Optional local medication catalog database at `backend/medbuddy.db`

## Local Setup

From the repository root:

```powershell
cd backend
py -3.11 -m venv ..\.venv
..\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
Copy-Item .env.example .env
```

Open `backend/.env` and set at least:

```dotenv
GEMINI_API_KEY=your_gemini_api_key
PUBLIC_DATA_API_KEY=your_public_data_api_key
# Optional: leave blank to reuse PUBLIC_DATA_API_KEY for hospital requests.
HOSPITAL_API_KEY=
APP_ENV=development
AUTH_MODE=disabled
AUTO_CREATE_SCHEMA=true
PILL_IMAGE_API_ENABLED=true
PILL_IMAGE_API_TIMEOUT_SECONDS=8
PILL_IDENTIFICATION_MODEL_NAME=gemini-3.1-flash-lite
PILL_IDENTIFICATION_TIMEOUT_SECONDS=20
PILL_IDENTIFICATION_CATALOG_TTL_HOURS=168
PILL_IDENTIFICATION_CATALOG_REFRESH_TIMEOUT_SECONDS=30
```

The public-data key must be authorized for the `e약은요`, medication approval,
medication pill-identification, and pharmacy-location APIs. Pill images are optional; lookups keep
working with the existing placeholder when that API is unavailable or the dosage
form has no public pill image. Set `PILL_IMAGE_API_ENABLED=false` only when the
optional saved-medication image enrichment must be disabled. The experimental
loose-pill flow still requires the MFDS identification catalog.

Start the API server:

```powershell
python -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

API documentation is available at `http://127.0.0.1:8000/docs`. This
loopback-only server is for backend development and automated testing; the
Android application does not use it as its default API endpoint.

## Nearby Care API Credentials

The values above are placeholders, not working credentials. Enter your own keys
only in the ignored `backend/.env` (or `deploy/backend.env` on the server).
Do not commit either file, service-account JSON, Firebase configuration originals,
local demo settings, or logs containing credentials. Never put public-data or
Gemini keys in Flutter `--dart-define` values or client source.

| Service to apply for | Used for | Backend setting |
| --- | --- | --- |
| [국립중앙의료원 전국 병·의원 찾기 서비스](https://www.data.go.kr/data/15000736/openapi.do) | Hospital coordinates, departments, contact information and weekly consultation hours | `HOSPITAL_API_KEY`; when blank, reuses `PUBLIC_DATA_API_KEY` |
| [한국천문연구원 특일 정보](https://www.data.go.kr/data/15012690/openapi.do) | Determines whether a selected Korean date is a legal holiday, for both hospital and pharmacy hours | `PUBLIC_DATA_API_KEY` |
| 국립중앙의료원 전국 약국 정보 조회 서비스 (`ErmctInsttInfoInqireService`) | Pharmacy catalog and weekly business hours | `PUBLIC_DATA_API_KEY` |
| [국립중앙의료원 명절 비상진료기관 및 약국 조회 서비스](https://www.data.go.kr/data/15000480/openapi.do) | Exact-date holiday pharmacy rosters | `PUBLIC_DATA_API_KEY` |

Apply for each service separately in the Public Data Portal and check approval
for the key used by the running backend. A key that works for medication or
hospital data does not automatically authorize holiday queries. `HOSPITAL_API_KEY`
does not override the key used by the KASI calendar or pharmacy services.
The backend URL-encodes request parameters; use the portal's decoded key value.

Restart the backend after editing its local environment. For a 403 or
`SERVICE_KEY_IS_NOT_REGISTERED_ERROR`, check service approval and the configured
key without copying the real key or a credential-bearing request URL into an
issue. Public-data failures are not treated as proof that a hospital is closed
or that a date is an ordinary weekday. Visit-time availability still requires
confirmation with the institution.

The hospital request/cache limits and service base URLs are documented in
`backend/.env.example`; retain those defaults for initial testing. Map rendering
uses the Naver client-ID setup in the [frontend README](../frontend/README.md),
independently of backend data keys.

## Database Schema and Upgrades

DB 초기화 및 갱신 정책:

- `AUTO_CREATE_SCHEMA=true`는 **빈 DB만** Alembic `head`로 초기화한다.
  기존 DB에 `create_all()`이나 임의의 컬럼 보정을 적용하지 않는다.
- 이미 Alembic으로 관리되는 DB는 Backend/worker를 중지하고 백업한 뒤,
  `backend/`에서 아래 명령으로 갱신한다. 개발·staging·production 모두 같은
  migration 체인을 사용하며, 운영에서는 `AUTO_CREATE_SCHEMA=false`를 유지한다.

```powershell
python -m alembic current
python -m alembic heads
python -m alembic upgrade head
```

- 기존 테이블은 있지만 `alembic_version`이 없는 구형 로컬 DB는 자동 변환하지 않는다.
  먼저 SQLite backup API로 WAL까지 포함한 일관된 백업을 만들고, 복사본의
  테이블·컬럼·제약조건·데이터 무결성을 특정 migration revision과 대조한다.
  확인된 baseline에만 `alembic stamp <검증한_revision>`을 수행하고
  `alembic upgrade head`를 적용해 데이터 보존을 확인한 후 실제 DB에 적용한다.
  다른 DB의 revision을 그대로 사용하거나 `stamp head`로 누락된 migration을
  건너뛰지 않는다. DB 삭제·수동 `ALTER TABLE`은 필요하지 않다.
- 앱은 migration revision 및 ORM 필수 컬럼 불일치 시 worker 시작 전에 중단한다.
  따라서 `AUTO_CREATE_SCHEMA=true`도 기존 DB의 migration을 대체하지 않는다.
- v0.2.2 통합 migration head는 `f2c8a6d4e901`이다. Catalog 갱신 상태
  `c5e1a7f3b902`와 ID·Push 등록 보호 `d19e7c4b2a60`을 합치며 기존 revision을 바꾸지 않는다.
- `d19e7c4b2a60` 적용 전 각 기기의 복용 대기 기록 동기화를 완료하고 실패·보류
  항목을 확인한다. 기록을 일괄 폐기하거나 조용히 삭제하지 않으며, 대상이 불명확하면
  자동 재전송하지 않고 사용자 확인 후 진행한다. 앱과 Backend/worker를 중지하고
  일관된 백업 및 복사본 검증 후 전용 Alembic 연결로 갱신한다.
  SQLite의 `foreign_keys=OFF`는 이 전용 migration 연결에만 해당하며 서비스 연결은 끄지 않는다.
  SQLite 약·채팅 ID의 현재 행과 적용 후 발급 이력은 재사용을 방지하지만,
  적용 전 이미 삭제된 최고 ID는 복원할 수 없다. 큰 timestamp ID를 시딩하거나
  기존 ID를 바꾸지 않는다. 상세 절차와 rollback 제한은
  [운영 갱신 안내](../docs/Production%20Deployment.md#delayed-request-rollout-d19e7c4b2a60)를 따른다.

## Optional Local Public-Data Catalogs

Local development stores medication, pill-reference, and weekly pharmacy schedule rows in `backend/medbuddy.db`. Production uses the same ORM mappings in Alembic-managed PostgreSQL, and the catalog synchronization job is the sole production writer. Generated `.db` files are intentionally ignored by Git.

Build or refresh the optional local medication catalog from the public drug APIs:

```powershell
python scripts/sync_drug_catalog.py --dataset all --page-size 500 --max-retries 5
python scripts/sync_pharmacy_catalog.py --page-size 1000 --max-retries 5
```

Resume an interrupted long-running sync from a known API page:

```powershell
python scripts/sync_drug_catalog.py --dataset approval --page-size 500 --start-page 120 --max-retries 5
```
