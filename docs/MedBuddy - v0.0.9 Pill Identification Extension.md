# MedBuddy v0.0.9 Loose-Pill Identification Extension

## Status and scope

This document defines the experimental extension developed on `temp` for the
v0.0.9-alpha candidate. Loose-pill identification was not part of the original
MedBuddy use cases, so the baseline class and sequence diagrams remain
unchanged. The extension follows the same Boundary-Control-Entity structure and
does not enter the prescription OCR or saved-medication workflows.

The feature returns **possible MFDS product candidates**, not a medical
diagnosis. It never saves a candidate as medication automatically, and the UI
requires the user to select and explicitly confirm a candidate. Users are told
to verify the package or consult a pharmacist before taking an unknown pill.

## Data and model boundaries

- The MFDS pill-identification API is the authoritative product catalog.
- Gemini Vision extracts only visible attributes: shape, color, imprint, score
  line, and image quality. Its prompt explicitly forbids product-name guessing.
- `IdentifyPill` ranks MFDS rows deterministically from those attributes.
- The optional reverse-side photo is checked against the front-side photo.
  Clearly mismatched pills are rejected; uncertain pairs remain non-confident
  and are surfaced to the user for retaking or manual verification.
- User photos are normalized in memory and sent for analysis, but are not
  persisted or logged. Path-specific body limits reject oversized multipart
  requests before Starlette parses them.
- Public MFDS metadata is cached for seven days in an isolated local SQLite
  reference database, so a catalog refresh cannot lock or enlarge the core
  medication/schedule database. A stale complete cache remains available
  during an MFDS outage.
- The published Korean pill-identification reference implementation expects
  trained shape-specific model weights and a large offline image corpus. Those
  assets are not publicly bundled, so v0.0.9 uses a replaceable vision boundary
  instead of claiming to ship that model.

Official sources:

- [MFDS pill-identification Open API](https://www.data.go.kr/data/15057639/openapi.do)
- [Public pill-identification algorithm source](https://www.data.go.kr/data/15112583/fileData.do?recommendDataYn=Y)
- [Public pill-identification sample images](https://www.data.go.kr/data/15112582/fileData.do?recommendDataYn=Y)

## Extension class diagram

```plantuml
@startuml MedBuddy_v009_Pill_Identification_Extension
skinparam classAttributeIconSize 0

package "Frontend" {
  class HomeScreen <<boundary>>
  class InputPrescriptionUI <<boundary>>
  class PillIdentificationUI <<boundary>>
  class "IdentifyPill" as IdentifyPillFlutter <<control>> {
    +requestPillImage(source)
    +requestPillIdentification(frontImage, backImage)
  }
  class "PillVisualFeatures" as PillVisualFeaturesFlutter <<entity>>
  class "PillIdentificationResult" as PillIdentificationResultFlutter <<entity>>
  class "PillIdentificationCandidate" as PillIdentificationCandidateFlutter <<entity>>
}

package "Backend" {
  class RequestBodyLimitMiddleware <<infrastructure>>
  rectangle "api.router\n<<HTTP boundary module>>" as ApiRouter
  rectangle "api.dependencies\n<<composition module>>" as ApiDependencies
  class IdentifyPill <<control>> {
    +requestPillIdentification(frontImage, backImage)
    -_rank_candidates(features, catalog)
  }
  class PillVisionBoundary <<boundary>> {
    +extractVisualFeatures(frontImage, backImage)
  }
  class PillImageProcessingBoundary <<boundary>> {
    +preprocessPillImage(image)
  }
  class MFDSPillCatalogBoundary <<boundary>> {
    +getCatalog()
  }
  class GeminiPillVisionAPI <<external>>
  class MFDSPillAPI <<external>> {
    +requestCatalog()
  }
  class PillIdentificationCatalogRepository <<repository>>
  class PillVisualFeatures <<entity>>
  class PillCatalogEntry <<entity>>
  class PillIdentificationResult <<entity>>
  class PillIdentificationCandidate <<entity>>
  class PillIdentificationReference <<entity>>
}

HomeScreen --> InputPrescriptionUI : renders
InputPrescriptionUI --> HomeScreen : requests UC-15 navigation
HomeScreen --> PillIdentificationUI : Navigator.push
PillIdentificationUI --> IdentifyPillFlutter
IdentifyPillFlutter --> RequestBodyLimitMiddleware : multipart HTTP
RequestBodyLimitMiddleware --> ApiRouter : bounded request
IdentifyPillFlutter --> PillIdentificationResultFlutter
PillIdentificationResultFlutter *-- PillVisualFeaturesFlutter
PillIdentificationResultFlutter *-- PillIdentificationCandidateFlutter

ApiRouter --> IdentifyPill
ApiRouter ..> ApiDependencies : Depends(get_identify_pill)
ApiDependencies ..> IdentifyPill : constructs per request
ApiDependencies ..> PillVisionBoundary : owns reusable boundary
ApiDependencies ..> MFDSPillCatalogBoundary : owns reusable boundary
IdentifyPill --> PillVisionBoundary
IdentifyPill --> MFDSPillCatalogBoundary
IdentifyPill --> PillIdentificationResult
PillIdentificationResult *-- PillIdentificationCandidate
PillVisionBoundary --> PillImageProcessingBoundary
PillVisionBoundary --> GeminiPillVisionAPI
PillVisionBoundary --> PillVisualFeatures
MFDSPillCatalogBoundary --> MFDSPillAPI
MFDSPillCatalogBoundary --> PillIdentificationCatalogRepository
PillIdentificationCatalogRepository --> PillIdentificationReference
MFDSPillCatalogBoundary --> PillCatalogEntry
@enduml
```

`PillIdentificationCatalogRepository` is an infrastructure adapter, not a new
domain use case. `MFDSPillCatalogBoundary` owns its short-lived session factory
and runs synchronous SQLite access outside the event loop. Its isolated
reference database keeps catalog replacement independent from core MedBuddy
transactions and keeps SQLAlchemy concerns out of the `IdentifyPill` control.
The repository initializes this optional database lazily on first catalog
access, so the extension adds no catalog I/O to the baseline app startup.
`api.dependencies` is the runtime composition module: it owns the reusable
vision/catalog boundary instances, constructs a request-scoped `IdentifyPill`
control from those boundaries, injects that control into `api.router`, and
closes owned clients during the FastAPI lifespan. It is an implementation node,
not a replacement for any conceptual BCE class.

## Extension sequence diagram

```plantuml
@startuml MedBuddy_v009_Pill_Identification_Sequence
actor User
boundary HomeScreen
boundary InputPrescriptionUI
boundary PillIdentificationUI
control IdentifyPillFlutter
participant RequestBodyLimitMiddleware
participant "api.router" as ApiRouter
participant "api.dependencies" as ApiDependencies
control IdentifyPill
boundary PillVisionBoundary
boundary MFDSPillCatalogBoundary
external GeminiPillVisionAPI
external MFDSPillAPI
database PillCatalogSQLite

User -> InputPrescriptionUI : click camera analysis
InputPrescriptionUI -> User : choose prescription or loose pill
User -> InputPrescriptionUI : choose loose pill
InputPrescriptionUI -> HomeScreen : onPillIdentificationRequested()
HomeScreen -> PillIdentificationUI : Navigator.push
User -> PillIdentificationUI : select front image\n[optional back image]
User -> PillIdentificationUI : request identification
PillIdentificationUI -> IdentifyPillFlutter : requestPillIdentification()
IdentifyPillFlutter -> RequestBodyLimitMiddleware : POST front + optional back
RequestBodyLimitMiddleware -> ApiRouter : bounded multipart request
ApiRouter -> ApiDependencies : get_identify_pill()
ApiDependencies --> ApiRouter : configured IdentifyPill
ApiRouter -> IdentifyPill : requestPillIdentification()

par Visual attributes
  IdentifyPill -> PillVisionBoundary : extractVisualFeatures()
  PillVisionBoundary -> PillVisionBoundary : normalize front then optional back
  PillVisionBoundary -> GeminiPillVisionAPI : bounded images + same-pill check
  GeminiPillVisionAPI --> PillVisionBoundary : visible attributes only
  PillVisionBoundary --> IdentifyPill : PillVisualFeatures
and Public catalog
  IdentifyPill -> MFDSPillCatalogBoundary : getCatalog()
  MFDSPillCatalogBoundary -> PillCatalogSQLite : read fresh cache
  alt cache missing or expired
    MFDSPillCatalogBoundary -> MFDSPillAPI : fetch bounded pages concurrently
    MFDSPillAPI --> MFDSPillCatalogBoundary : public product rows
    MFDSPillCatalogBoundary -> PillCatalogSQLite : replace complete cache atomically
  end
  MFDSPillCatalogBoundary --> IdentifyPill : PillCatalogEntry[]
end

IdentifyPill -> IdentifyPill : deterministic weighted ranking
IdentifyPill --> ApiRouter : candidate result
ApiRouter --> IdentifyPillFlutter : response DTO
IdentifyPillFlutter --> PillIdentificationUI : candidate entities
PillIdentificationUI --> User : show candidates + safety warning
User -> PillIdentificationUI : select and confirm candidate
note right of PillIdentificationUI
  Confirmation does not save medication
  and does not assert a diagnosis.
end note
@enduml
```

## Release-candidate validation

The v0.0.9-alpha candidate was validated against three distinct front/back
image pairs obtained from the official MFDS catalog. The production FastAPI
endpoint, local image preprocessing, Gemini visual-feature boundary, MFDS
catalog boundary, deterministic ranking, response DTO, and confirmation policy
were exercised together. The expected MFDS products ranked first for item
sequences `200808877`, `200809076`, and `200809402`; every response kept
`requires_confirmation=true`.
After the front/back consistency contract was added, item `200808877` was
revalidated through the production boundaries using the two sides of its
official MFDS reference image. The expected product ranked first, the pair was
accepted as consistent, and the result remained explicitly confirmable by the
user.

A complete live catalog refresh advertised 25,315 upstream rows and accepted
25,298 normalized image-bearing entries after validation and deduplication,
well above the 95% completeness threshold. With the bounded 12-request
concurrency used by the external catalog adapter, the local validation refresh
completed in approximately 14.7 seconds; an in-memory cache lookup was
effectively immediate. These timings describe one development-machine run and
are not a service-level guarantee.

Live external-service validation is intentionally separate from CI because it
requires private credentials and network availability. Deterministic unit and
widget tests cover malformed upstream data, candidate ambiguity, mandatory
confirmation, request cancellation, replacement-image locking, front-only
evidence isolation, front/back consistency, bounded multipart and MFDS response
bodies, and compact large-text layouts without committing pill photos or
generated catalog files.

## Failure and performance policy

- Oversized requests are rejected before multipart parsing. Empty, invalid,
  oversized, tiny, or excessively large images are rejected before external
  analysis. High-resolution JPEGs use bounded draft decoding before Pillow and
  OpenCV normalize the analysis frame to at most 1,600 pixels per side.
- Blocking visual defects such as unreadable blur, glare, occlusion, multiple
  pills, or no detectable pill are reported as `422`. A small pill in frame or
  a textured background is treated as a non-blocking warning when shape and
  color remain usable. Unavailable catalog is reported as `503`; invalid
  visual-service data as `502`; visual timeout as `504`. Internal details are
  not returned to the client.
- When both sides are supplied, photos that clearly show different pills are
  reported as `422`. A low side-consistency score forces `is_confident=false`
  and produces a visible warning instead of silently combining two pills.
- When no reverse-side photo is supplied, any model-generated reverse imprint
  or score-line value is discarded before ranking, so nonexistent evidence
  cannot increase candidate confidence.
- Front and optional back preprocessing run sequentially inside one worker to
  cap per-request decode memory. A timed-out worker retains a preprocessing
  capacity slot until the underlying thread actually exits. The complete vision
  task and catalog loading run concurrently. MFDS pages use bounded concurrency,
  a fixed decompressed response-body limit, and cancellation of unfinished
  siblings when one page fails. Catalog lock waiting, refresh, and fallback share
  one fixed deadline; failed cold-cache refreshes use a short retry backoff so
  queued callers do not repeat the same outage.
- A catalog refresh is accepted only when at least 95% of the advertised rows
  are present, preventing a partial response from replacing a valid cache.
- A stale persisted catalog remains available during upstream failure, but its
  in-memory fallback is retried after five minutes rather than suppressing
  refresh attempts for the full seven-day fresh-cache lifetime.
- If no readable imprint exists, the score is capped and `is_confident` remains
  false. Shape and color must both match before an imprint-free candidate can
  be returned, and a one-character imprint cannot produce a confident result.
  `requires_confirmation` remains true for every result.

## Future replacement path

A licensed or locally trained pill classifier can replace
`PillVisionBoundary` later. It must emit the same `PillVisualFeatures` contract,
which keeps the control, MFDS matching, API response, and Flutter UI unchanged.
