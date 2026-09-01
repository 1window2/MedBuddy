# MedBuddy Medication Intake Automation Roadmap

## Objective

Reduce the number of actions required to record medication intake without
allowing uncertain image recognition to silently create a medically incorrect
record.

## Current Baseline

- The schedule can update one medication dose or atomically check/uncheck every
  active medication in one time slot.
- The loose-pill batch flow accepts up to ten **separately photographed** pills.
  It does not yet separate several physical pills from one image.
- Every pill candidate requires confirmation before it becomes a saved schedule.

## Catalog Coverage Target

The primary coverage target is every solid oral medication that is searchable in
the Korean Pharmaceutical Information Center (KPIC) identification catalog. The
KPIC status dashboard reported 24,660 distinct products and 26,317 registration
records on 2026-09-01. These values are a dated reconciliation baseline, not a
permanent hard-coded constant.

- Continue ingesting the MFDS pill-identification OpenAPI as the machine-readable
  source because its public-data license permits reuse and the current sync is
  atomic and validates 95% of the upstream-reported row count.
- Do not scrape or redistribute KPIC images without explicit permission. Use the
  KPIC status dashboard to detect material coverage gaps until an authorized KPIC
  export or API is available.
- Record upstream row count, raw fetched rows, unique `item_seq` count, rejected
  rows, and refresh time for every synchronization.
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
