# MedBuddy Medication Intake Automation Roadmap

## Objective

Reduce the number of actions required to record medication intake without
allowing uncertain image recognition to silently create a medically incorrect
record.

## Current Baseline

- The schedule can update one medication dose or atomically check/uncheck every
  active medication in one time slot.
- The loose-pill flow accepts either per-pill front/back photos or one image with
  up to ten spatially distinct pills. One-image observations are numbered and
  ranked independently against one shared catalog snapshot.
- Every pill candidate requires confirmation before it becomes a saved schedule.

## Chat Intake Confirmation

- Medication selection retains each medication/time-slot pair and its schedule
  date. Morning and evening doses of the same medicine are independent; select-all
  includes every displayed dose, and reopening restores the exact selections.
- Patient quick reply `먹었어요` immediately records those selected doses without
  asking for the time slot again. Multiple slots are processed separately; only
  successfully queued/saved doses are removed from the selection. Retrying a
  partially failed send preserves the remaining slots and their request IDs.
- Changed dates or incompatible schedules require reselection instead of silently
  recording another time slot. Cancelling the medication picker records nothing.
- Recording writes dose state and a server-generated chat receipt in one
  transaction. Ordinary typed messages and caregiver questions never change
  completion state. This remains a patient-reported record, not proof of ingestion.
- The direct chat API verifies the active link, patient role, current date and active medicines.
  Queued operations validate the original date against the 30-day recovery window.
  A failed message save rolls back dose changes and the caregiver alert outbox.
- The production app now persists chat intake and schedule completion/undo in an
  encrypted device outbox. Stable operation IDs survive chat dismissal and app
  restart. Receipts do not reapply later-undone doses; pending status is distinct
  from server-confirmed state. See the [offline recovery contract](qa/v0.2.0-reboot-offline-recovery.md).
- Full-slot transitions reuse the existing caregiver outbox. The initiating
  conversation does not receive a second automatic full-slot message; other
  linked caregivers retain their existing notification flow.

## Android Home-Screen Widget

- 환경설정의 복약 및 알림에서 `홈 화면 복약 위젯 추가`를 선택하면
  Android의 추가 확인창을 연다. 앱 홈과 위젯 모두 기존 `홈 복약 일정` 설정의
  본인/연결된 환자 선택을 따른다. 연결된 환자의 기록은 읽기 전용으로 표시한다.
- 연결된 환자가 여러 명이면 앱 홈은 별칭 양옆 화살표로 한 명씩 전환한다.
  홈 미리보기의 슬라이드는 아침·점심·저녁·취침 전 요약만 바꾼다.
  위젯은 상단 환자 별칭 옆 화살표로 환자를 전환하고,
  하단 화살표·페이지 점으로 그 환자의 시간대별 복약 상태를 조회한다.
  보호자 화면에는 복용·취소 버튼을 제공하지 않으며, `일정 열기`로 해당 환자의
  상세 화면을 연다. 환자 알림 시각을 추정하거나 보호자 본인의 알림 시각을 사용하지 않는다.
- 환자 현황은 기존 보호자 조회 API로 받아 계정별 암호화 저장소에 보관한다.
  본인 복용 기록의 전송 큐와 분리하며, 계정·표시 대상·날짜 변경이나 연동 해제 시
  이전 선택과 버튼을 재검증한다. 늦게 도착한 조회가 최신 연동 상태를 덮어쓰지 않는다.
- 상단에 복약 기준 시간대의 오늘 날짜를 표시하고, 남은 복약 일정을 설정된
  시간 순서대로 표시하며 오늘 진행률을 함께 보여준다.
  `복용했어요`는 화면에 표시된 시간대의 미완료 약만 기록한다. 추가 확인창이나
  되돌리기 대기 없이 기기에 저장하는 즉시 다음 남은 일정으로 넘어간다.
  모두 기록하면 오늘 복약 기록 완료 상태가 된다. 개별 약 수정은 앱의 일정 화면에서 한다.
- 좌우 화살표와 페이지 점으로 등록된 시간대를 이동하며, 완료된 시간대도 조회한다.
  각 약에 복용 완료/미복용을 표시한다. 완료된 시간대에는 테두리형 `복용 취소`
  버튼으로 해당 시간대의 기록을 취소하고, 그 페이지를 유지해 다시 기록할 수 있다.
  취소 역시 확인창 없이 기기에 저장한 뒤 기존 전송 큐로 서버에 반영한다.
  조회 전환은 기기 안에서 즉시 처리하며 기록·전송을 만들지 않는다. 선택한 페이지의
  복용 버튼은 그 시간대의 미완료 약만 기록한다. 조회 위치는 위젯별로 유지하고 날짜나
  계정이 바뀌면 초기화한다. 안드로이드 홈 위젯은 좌우 스와이프를 지원하지 않으므로
  화살표와 점 선택을 사용한다.
- 위젯 버튼은 Android에서 먼저 비밀정보가 없는 요청 토큰을 저장한다.
  Flutter가 이를 암호화된 복약 저장소로 넘길 때 요청 검증과 전송 대기
  등록을 한 트랜잭션으로 처리한다. 여러 위젯·연속 클릭·작업 재실행도
  같은 기록을 중복 생성하지 않는다.
- 기기 저장과 서버 저장을 구분해 표시하며, 기존 오프라인 전송 큐를
  재사용한다. 앱이 종료된 뒤의 클릭도 백그라운드로 처리한다.
  로그아웃·계정 변경·자정·약 삭제·이미 완료된 항목은 저장소에서 다시
  검증한다. 취소는 화면에 표시했던 약 목록과 완료 상태가 일치할 때만 허용하며,
  취소 후 다시 복용한 기록에 이전 취소 버튼을 재사용할 수 없다.
  오래된 버튼으로 다른 날이나 다른 사람의 복약을 기록하지 않는다.
- 알림 내용 숨김 설정은 위젯 약 이름에도 적용한다. 위젯을 누르면 현재 표시 중인
  본인 또는 환자의 복약 일정으로 이동하며, 새로고침으로 최신 상태를 조회한다.
- Android의 절전·강제 종료 정책에 따라 갱신이나 백그라운드 전송은 지연될
  수 있다. 갱신은 앱 변경, 복용 기록, 사용자 새로고침, 주기 작업, 자정
  시점에 요청한다. iOS 위젯과 실제 약 복용 여부의 검증은 이번 범위가 아니다.

관련 설계: [오프라인 기록 흐름](UML/sequence/OfflineDoseSync.puml),
[홈 위젯 흐름](UML/sequence/HomeDoseWidget.puml),
[기록·위젯 클래스 구성](UML/class/06_DoseSyncAndWidget.puml).

Implementation references: [Android widget updates](https://developer.android.com/develop/ui/views/appwidgets/advanced),
[home_widget interactivity](https://docs.page/abausg/home_widget/features/interactive-widgets).

## Catalog Coverage Target

The primary coverage target is every solid oral medication that is searchable in
the Korean Pharmaceutical Information Center (KPIC) identification catalog. The
KPIC status dashboard reported 24,667 distinct products and 26,325 registration
records on 2026-09-02. The product count is represented by the dated
`PILL_IDENTIFICATION_KPIC_PRODUCT_FLOOR` deployment setting; it must be reviewed
against the dashboard before each release rather than treated as permanent.

- Continue ingesting the MFDS pill-identification OpenAPI as the machine-readable
  source because its public-data license permits reuse and the current sync is
  atomic, requires every upstream-advertised raw row to be fetched, and verifies
  the exact persisted `item_seq` set before publication.
- Do not scrape or redistribute KPIC images without explicit permission. Use the
  KPIC status dashboard to detect material coverage gaps until an authorized KPIC
  export or API is available.
- Record upstream row count, raw fetched rows, valid rows, unique `item_seq`
  count, rejected rows, duplicate rows, response bytes, and the exact persisted
  identifier-set result for every synchronization.
- A release may claim full catalog eligibility only when every valid unique MFDS
  row is stored and a reconciliation against the current KPIC product count has
  no unexplained gap. A lower count must fail readiness rather than silently
  publishing a partial catalog.
- Catalog eligibility means the product can participate in deterministic
  ranking. It does not promise a confident identity from a photo that hides the
  imprint, reverse side, color, shape, or scale.

## Stage 1: One-image Multi-pill Identification

Introduce a separate multi-object boundary instead of weakening the existing
single-pill contract.

Implementation status: the separate authenticated API, composition-preserving
image boundary, model-assisted normalized boxes, strict geometry validation,
independent deterministic ranking, numbered Flutter overlay, and confirmation
workflow are implemented on `beta/v0.2.0`. Release readiness still requires the
licensed physical-device corpus and measured acceptance evidence below.

1. Detect a bounded number of pill objects in one image and return a normalized
   bounding box, crop, visible attributes, quality score, and occlusion warning
   for each observation.
2. Rank catalog candidates independently for every observation. A failure for
   one crop must not discard successful observations.
3. Preserve object count and image order so identical-looking pills remain
   separate physical observations.
4. Reject or request another photo when objects overlap, image quality is below
   threshold, or the detector cannot establish a stable count.
5. Display the original image with numbered boxes and a compact candidate card
   for each object. The user corrects only uncertain objects.

Acceptance evidence must include mixed shapes and colors, identical duplicates,
partial occlusion, glare, front/back orientation, background clutter, false
objects, missing objects, and bounded latency/cost tests on physical devices.

## Image Corpus and Test Matrix

The repository test corpus must contain only images that MedBuddy is permitted to
redistribute: project-owned physical-device photos, explicitly licensed official
images, or generated composites made from permitted source assets. Unattributed
Google Image results can guide local exploratory testing but must not be committed.

Every committed test image needs a sidecar manifest containing source/license,
SHA-256, expected object count, normalized bounding boxes, visible shape/color/
imprint attributes, occlusion and glare labels, and whether identity is knowable
from the shown side. Unknown web-photo identities must never be guessed into the
expected result.

The first matrix must cover:

1. Mixed tablets inside a reflective printed medication bag.
2. White-on-white pills with weak edges and score lines.
3. Pills held through plastic with fingers and background text.
4. Pills on a palm with skin texture and strong scale differences.
5. Repeated shapes/colors, including two physically distinct identical tablets.
6. Touching and partially overlapping pills.
7. Front-only, back-only, and paired front/back views.
8. Synthetic composites with known catalog identities, randomized rotation,
   scale, lighting, blur, shadow, and background clutter.

Keep training/tuning assets separate from the final evaluation set. Object-count
recall, box precision, candidate top-k recall, abstention correctness, latency,
and false completion rate must be reported independently.

## Stage 2: Match Observations to the Current Dose

After Stage 1 meets its acceptance evidence, compare the confirmed observations
with the still-incomplete medications in the selected or inferred time slot.

1. Use server-owned active schedules and catalog identifiers; never match only
   by display name.
2. Match as a multiset so duplicate tablets and expected counts are preserved.
3. Classify every result as matched, missing, extra, ambiguous, or unknown.
4. Preselect the most likely current slot from time and schedule state, while
   allowing a one-tap correction.
5. Present one summary confirmation rather than a confirmation per pill.

No dose completion is written when the image has an unknown/ambiguous object, a
count mismatch, or a medication that is not part of the authenticated patient's
active schedule.

## Stage 3: Automated Completion

Use the existing atomic schedule-completion transaction as the only write
boundary. The first release should offer one summary confirmation. A later
opt-in zero-confirmation mode may be considered only after measured physical-
device accuracy demonstrates that the accepted false-completion risk is met.

- Full match: offer one action to complete the matched slot.
- Partial safe match: use a future atomic subset operation in the same schedule
  control to update only unambiguous matches and leave every other medication
  unchanged. Do not fan out several client-side writes.
- Any unsafe result: save no completion and explain the smallest corrective
  action, such as retaking one photo.
- Repeating the same image/request must be idempotent and must not duplicate
  caregiver completion events.

## Architecture Boundaries

- Flutter Boundary: camera guidance, numbered overlays, and one summary review.
- Flutter Control/ViewModel: request coordination and local presentation state;
  it does not decide medication identity or ownership.
- FastAPI Boundary/Control: authenticated ownership, bounded image processing,
  candidate orchestration, matching policy, and atomic completion request.
- Vision Boundary: object observations only; it never writes schedule state.
- Catalog Repository: deterministic candidate ranking and canonical identifiers.
- Schedule Control: the sole completion writer and caregiver-event producer.

Nearby-pharmacy and linked-chat work remains independent v0.2.0 scope and must
not be coupled to this pipeline.
