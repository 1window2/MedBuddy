# MedBuddy Class Diagram

## Document Contract

This is the canonical implementation-grounded class view for the
`v0.0.9-alpha` baseline and the Android beta hardening branch.

- `docs/temp/class diagram v5.png` remains the authoritative first-semester
  conceptual baseline.
- This document preserves that diagram's Boundary-Control-Entity spine while
  using the classes and module boundaries that exist in the repository.
- `docs/MedBuddy - v0.0.9 Pill Identification Extension.md` defines the UC-15
  extension that was not present in v5.
- `docs/MedBuddy - Beta Security Architecture.md` defines planned beta security
  types. Planned security types are intentionally not represented as already
  implemented below.

Private Flutter widgets, private Python helper classes, Pydantic transport DTOs,
SQLAlchemy row classes, exceptions, and framework-generated state classes are
implementation details. They remain valid code but are omitted from the primary
diagram so the use-case architecture remains readable.

## Naming and Layer Rules

1. Frontend and backend classes with the same name are separate tier-local
   implementations and are qualified by package in this document.
2. `api.router` is the FastAPI boundary. It is a module, not a fictional
   `MedicationRouter` class.
3. `api.dependencies` is the backend composition root. It constructs controls
   and shared boundaries; domain controls do not construct the API router.
4. Cross-tier calls use HTTP through `api.router`. No Flutter class directly
   invokes a backend Python class.
5. SQLite ORM rows prefixed with `_` are persistence mappings, not domain
   entities. Relationships shown to databases are logical because current ORM
   tables do not declare all relationships as SQL foreign keys.
6. Patient and caregiver are current domain roles. The alpha hashes select demo
   scopes but are not authentication credentials.

## Current Implementation Diagram

```plantuml
@startuml MedBuddy_Current_Implementation
left to right direction
skinparam packageStyle rectangle
skinparam classAttributeIconSize 0
hide empty members

package "Flutter / Boundary" as FE_Boundary {
  class MedBuddyApp <<composition root>>
  class HomeScreen <<boundary>>
  class InputPrescriptionUI <<boundary>>
  class PrescriptionAnalysisProgressUI <<boundary>>
  class PrescriptionAnalysisPreviewUI <<boundary>>
  class PrescriptionAnalysisSuccessUI <<boundary>>
  class PrescriptionAnalysisFailureUI <<boundary>>
  class CheckResultUI <<boundary>>
  class CheckMedicationDetailUI <<boundary>>
  class CheckSavedMedicationUI <<boundary>>
  class CheckTodayMedicationInfoUI <<boundary>>
  class CheckScheduleUI <<boundary>>
  class HealthRecommendationUI <<boundary>>
  class LinkPatientCaregiverUI <<boundary>>
  class CheckCaregiverMedicationUI <<boundary>>
  class SetCaregiverNotificationUI <<boundary>>
  class SetNotificationUI <<boundary>>
  class ManageUserSettingUI <<boundary>>
  class PillIdentificationUI <<boundary>>
}

package "Flutter / Control" as FE_Control {
  class MedBuddyViewModel <<control, facade>>
  class "InputPrescription" as FE_InputPrescription <<control>>
  class "CheckMedicationDetail" as FE_CheckMedicationDetail <<control>>
  class "CheckSavedMedication" as FE_CheckSavedMedication <<control>>
  class "CheckTodayMedicationInfo" as FE_CheckTodayMedicationInfo <<control>>
  class "CheckSchedule" as FE_CheckSchedule <<control>>
  class "CheckHealthRecommendation" as FE_CheckHealthRecommendation <<control>>
  class "RequestVoiceGuide" as FE_RequestVoiceGuide <<control>>
  class "LinkPatientCaregiver" as FE_LinkPatientCaregiver <<control>>
  class "CheckCaregiverMedication" as FE_CheckCaregiverMedication <<control>>
  class "SetCaregiverNotification" as FE_SetCaregiverNotification <<control>>
  class "SetNotification" as FE_SetNotification <<control>>
  class "ManageUserSetting" as FE_ManageUserSetting <<control>>
  class "IdentifyPill" as FE_IdentifyPill <<control>>
}

package "Flutter / Entity" as FE_Entity {
  class "AnalyzedMedication" as FE_AnalyzedMedication <<entity>>
  class "MedicationDetail" as FE_MedicationDetail <<entity>>
  class "MedicationSchedule" as FE_MedicationSchedule <<entity>>
  class "MedicationAlarm" as FE_MedicationAlarm <<entity>>
  class "CaregiverNotification" as FE_CaregiverNotification <<entity>>
  class "HealthRecommendation" as FE_HealthRecommendation <<entity>>
  class "PatientHash" as FE_PatientHash <<entity>>
  class "PatientLinkCode" as FE_PatientLinkCode <<entity>>
  class "PatientCaregiverLink" as FE_PatientCaregiverLink <<entity>>
  class "UserSetting" as FE_UserSetting <<entity>>
  class "PillVisualFeatures" as FE_PillVisualFeatures <<entity>>
  class "PillIdentificationCandidate" as FE_PillCandidate <<entity>>
  class "PillIdentificationResult" as FE_PillResult <<entity>>
}

package "Flutter / External and Shared Services" as FE_Service {
  class ApiConfig <<configuration>>
  class ApiResponseParser <<boundary helper>>
  class NotificationService <<external boundary>>
  class TTSService <<external boundary>>
}

package "FastAPI / API Boundary" as BE_API {
  component "api.router" as APIRouter <<boundary>>
  component "api.dependencies" as APIDependencies <<composition root>>
  class RequestBodyLimitMiddleware <<middleware>>
  class Settings <<configuration>>
}

package "FastAPI / Control" as BE_Control {
  class "InputPrescription" as BE_InputPrescription <<control>>
  class "CheckMedicationDetail" as BE_CheckMedicationDetail <<control>>
  class "CheckSavedMedication" as BE_CheckSavedMedication <<control>>
  class "CheckTodayMedicationInfo" as BE_CheckTodayMedicationInfo <<control>>
  class "CheckSchedule" as BE_CheckSchedule <<control>>
  class "CheckHealthRecommendation" as BE_CheckHealthRecommendation <<control>>
  class "RequestVoiceGuide" as BE_RequestVoiceGuide <<control>>
  class "LinkPatientCaregiver" as BE_LinkPatientCaregiver <<control>>
  class "CheckCaregiverMedication" as BE_CheckCaregiverMedication <<control>>
  class "SetCaregiverNotification" as BE_SetCaregiverNotification <<control>>
  class "SetNotification" as BE_SetNotification <<control>>
  class "ManageUserSetting" as BE_ManageUserSetting <<control>>
  class "IdentifyPill" as BE_IdentifyPill <<control>>
}

package "FastAPI / Entity" as BE_Entity {
  class PrescriptionText <<entity>>
  class MedicationCandidate <<entity>>
  class MedicationCandidateList <<entity>>
  class PrescriptionAnalysisResult <<entity>>
  class "MedicationDetail" as BE_MedicationDetail <<entity>>
  class "MedicationSchedule" as BE_MedicationSchedule <<entity>>
  class "MedicationAlarm" as BE_MedicationAlarm <<entity>>
  class MedicationCompletion <<entity>>
  class "CaregiverNotification" as BE_CaregiverNotification <<entity>>
  class "HealthRecommendation" as BE_HealthRecommendation <<entity>>
  class "PatientHash" as BE_PatientHash <<entity>>
  class "PatientLinkCode" as BE_PatientLinkCode <<entity>>
  class "PatientCaregiverLink" as BE_PatientCaregiverLink <<entity>>
  class "UserSetting" as BE_UserSetting <<entity>>
  class "PillVisualFeatures" as BE_PillVisualFeatures <<entity>>
  class PillCatalogEntry <<entity>>
  class "PillIdentificationCandidate" as BE_PillCandidate <<entity>>
  class "PillIdentificationResult" as BE_PillResult <<entity>>
  class PillIdentificationReference <<reference mapping>>
}

package "FastAPI / External Boundary" as BE_Boundary {
  class PrescriptionImageProcessor <<utility boundary>>
  class GeminiVisionClient <<external boundary>>
  class OCRServiceBoundary <<external boundary>>
  class LLMService <<external boundary>>
  class PublicDrugSmallAPI <<external boundary>>
  class PublicDrugLargeAPI <<external boundary>>
  class PillImageAPI <<external boundary>>
  class PillImageProcessingBoundary <<utility boundary>>
  class GeminiPillVisionAPI <<external boundary>>
  class PillVisionBoundary <<external boundary>>
  class MFDSPillAPI <<external boundary>>
  class MFDSPillCatalogBoundary <<external boundary>>
}

package "FastAPI / Policy and Repository" as BE_Support {
  class MedicationCoursePolicy <<policy>>
  class SavedMedicationRetentionPolicy <<policy>>
  class PillIdentificationCatalogRepository <<repository>>
}

package "Persistence" {
  database "medbuddy.db\n(local/demo SQLite)" as MedicationDB
  database "pill_identification_catalog.db\n(reference SQLite)" as PillCatalogDB
  database "Redis\n(optional cache)" as RedisCache
}

' Main Flutter navigation and use-case coordination
MedBuddyApp o-- MedBuddyViewModel
MedBuddyApp --> HomeScreen
HomeScreen --> MedBuddyViewModel
HomeScreen ..> InputPrescriptionUI
HomeScreen ..> CheckSavedMedicationUI
HomeScreen ..> CheckScheduleUI
HomeScreen ..> LinkPatientCaregiverUI
HomeScreen ..> PillIdentificationUI
InputPrescriptionUI --> MedBuddyViewModel
PrescriptionAnalysisPreviewUI --> MedBuddyViewModel
CheckResultUI --> MedBuddyViewModel
CheckSavedMedicationUI --> MedBuddyViewModel
CheckScheduleUI --> MedBuddyViewModel
HealthRecommendationUI --> MedBuddyViewModel
MedBuddyViewModel o-- FE_InputPrescription
MedBuddyViewModel o-- FE_CheckSavedMedication
MedBuddyViewModel o-- FE_CheckSchedule
MedBuddyViewModel o-- FE_CheckHealthRecommendation
MedBuddyViewModel o-- FE_ManageUserSetting
LinkPatientCaregiverUI --> FE_LinkPatientCaregiver
CheckCaregiverMedicationUI --> FE_CheckCaregiverMedication
CheckCaregiverMedicationUI --> FE_SetCaregiverNotification
SetNotificationUI --> FE_SetNotification
CheckMedicationDetailUI --> FE_CheckMedicationDetail
CheckMedicationDetailUI --> FE_RequestVoiceGuide
PillIdentificationUI --> FE_IdentifyPill

' Frontend entities and local external services
FE_InputPrescription --> FE_AnalyzedMedication
FE_CheckMedicationDetail --> FE_MedicationDetail
FE_CheckSavedMedication --> FE_MedicationDetail
FE_CheckSchedule --> FE_MedicationSchedule
FE_CheckSchedule --> FE_MedicationAlarm
FE_CheckHealthRecommendation --> FE_HealthRecommendation
FE_LinkPatientCaregiver --> FE_PatientLinkCode
FE_LinkPatientCaregiver --> FE_PatientCaregiverLink
FE_SetCaregiverNotification --> FE_CaregiverNotification
FE_ManageUserSetting --> FE_UserSetting
FE_IdentifyPill --> FE_PillResult
FE_PillResult *-- "0..*" FE_PillCandidate
FE_PillResult *-- FE_PillVisualFeatures
FE_SetNotification ..> NotificationService
FE_RequestVoiceGuide ..> TTSService

' Every Flutter control reaches the backend only through HTTP
FE_Control ..> APIRouter : HTTP JSON/multipart
FE_Control ..> ApiConfig
FE_Control ..> ApiResponseParser

' FastAPI composition and use-case controls
RequestBodyLimitMiddleware --> APIRouter
APIRouter --> APIDependencies
APIDependencies o-- BE_InputPrescription
APIDependencies o-- BE_CheckMedicationDetail
APIDependencies o-- BE_CheckSavedMedication
APIDependencies o-- BE_CheckTodayMedicationInfo
APIDependencies o-- BE_CheckSchedule
APIDependencies o-- BE_CheckHealthRecommendation
APIDependencies o-- BE_RequestVoiceGuide
APIDependencies o-- BE_LinkPatientCaregiver
APIDependencies o-- BE_CheckCaregiverMedication
APIDependencies o-- BE_SetCaregiverNotification
APIDependencies o-- BE_SetNotification
APIDependencies o-- BE_ManageUserSetting
APIDependencies o-- BE_IdentifyPill

' Prescription pipeline
BE_InputPrescription --> OCRServiceBoundary
OCRServiceBoundary --> PrescriptionImageProcessor
OCRServiceBoundary --> GeminiVisionClient
BE_InputPrescription --> PrescriptionText
BE_InputPrescription --> MedicationCandidateList
MedicationCandidateList *-- "0..*" MedicationCandidate
BE_InputPrescription --> PrescriptionAnalysisResult
PrescriptionAnalysisResult *-- "0..*" MedicationCandidate

' Medication, schedule, setting, and link pipelines
BE_CheckMedicationDetail --> PublicDrugSmallAPI
BE_CheckMedicationDetail --> PublicDrugLargeAPI
BE_CheckMedicationDetail --> LLMService
BE_CheckSavedMedication --> PillImageAPI
BE_CheckSavedMedication --> SavedMedicationRetentionPolicy
BE_CheckSchedule --> MedicationCoursePolicy
BE_CheckSchedule --> BE_MedicationSchedule
BE_SetNotification --> BE_MedicationAlarm
BE_CheckSchedule --> MedicationCompletion
BE_SetCaregiverNotification --> BE_CaregiverNotification
BE_LinkPatientCaregiver --> BE_PatientLinkCode
BE_LinkPatientCaregiver --> BE_PatientCaregiverLink
BE_CheckHealthRecommendation --> LLMService
BE_CheckHealthRecommendation --> BE_HealthRecommendation
BE_ManageUserSetting --> BE_UserSetting

' UC-15 loose-pill extension
BE_IdentifyPill --> PillVisionBoundary
PillVisionBoundary --> PillImageProcessingBoundary
PillVisionBoundary --> GeminiPillVisionAPI
BE_IdentifyPill --> MFDSPillCatalogBoundary
MFDSPillCatalogBoundary --> MFDSPillAPI
MFDSPillCatalogBoundary --> PillIdentificationCatalogRepository
PillIdentificationCatalogRepository --> PillCatalogDB
PillIdentificationCatalogRepository --> PillIdentificationReference
PillIdentificationReference --> PillCatalogDB
BE_IdentifyPill --> BE_PillResult
BE_PillResult *-- "0..*" BE_PillCandidate
BE_PillResult *-- BE_PillVisualFeatures
BE_PillCandidate --> PillCatalogEntry

' Persistence is logical; private ORM rows implement these mappings
BE_Control ..> MedicationDB
BE_CheckMedicationDetail ..> RedisCache
MedicationDB ..> BE_MedicationSchedule
MedicationDB ..> BE_MedicationAlarm
MedicationDB ..> MedicationCompletion
MedicationDB ..> BE_CaregiverNotification
MedicationDB ..> BE_PatientCaregiverLink
MedicationDB ..> BE_UserSetting
@enduml
```

## Public Architectural Type Inventory

The primary diagram includes every public production type that participates in
a use case or architectural boundary. The following categories are intentionally
not expanded into separate diagram nodes:

| Category | Examples | Reason |
| --- | --- | --- |
| Flutter private presentation types | `_MedicationResultCard`, `_ScheduleSlot`, `_PillImageSlot` | File-local rendering decomposition; no domain responsibility. |
| Flutter state classes | `_CheckScheduleUIState`, `_PillIdentificationUIState` | Framework lifecycle implementation owned by the public UI boundary. |
| View-model result/projection types | `TodayMedicationProgress`, `SavedMedicationBatchDeleteResult`, `MedicationSaveResult` | Typed return/state projections owned by their control or view model. |
| Theme tokens | `MedBuddyColors`, `MedBuddyRadii`, `MedBuddyShadows` | Shared presentation constants without use-case behavior. |
| Transport DTOs | `OCRParseRequest`, `MedicationRequest`, `MedicationResponse`, `PillIdentificationResponse` | API serialization contracts, not domain coordinators. |
| Private ORM rows | `_SavedMedication`, `_MedicationAlarm`, `_PatientCaregiverLink` | Persistence mapping for public entities and controls. |
| Private control helpers | `_MedicationTextNormalizer`, `_PrescriptionMedicationNameVerifier` | Cohesive algorithms owned by their public control module. |
| Exceptions | `PillImageQualityError`, `PrescriptionAnalysisTimeoutError` | Error contracts, not stateful architectural collaborators. |

## v5 Reconciliation

| v5/conceptual name | Current implementation | Resolution |
| --- | --- | --- |
| `MainUI` | `HomeScreen`, `InputPrescriptionUI` | Flutter separates the home view from the prescription input boundary. |
| `PrescriptionInputUI` | `InputPrescriptionUI`, progress/preview/status UIs | One use case is decomposed by visible UI state. |
| `PrescriptionResultUI` | `CheckResultUI` | Same result-review responsibility. |
| `SavedMedicationUI` | `CheckSavedMedicationUI` | Exact implementation name retained. |
| `TodayMedicationUI` | `CheckTodayMedicationInfoUI`, `CheckScheduleUI` | Summary and actionable schedule are separate boundaries. |
| `LinkUI` | `LinkPatientCaregiverUI` | Uses the final patient-caregiver terminology. |
| `UserSettingUI` | `ManageUserSettingUI` | Matches the implemented UC-14 control/UI pair. |
| `PrescriptionAnalysisControl` | frontend/backend `InputPrescription` | v5 responsibility preserved across the HTTP boundary. |
| `MedicationSaveControl` | `CheckMedicationDetail` plus `CheckSavedMedication` | Detail enrichment and persistence remain separate cohesive controls. |
| `SavedMedicationControl` | `CheckSavedMedication` | Direct implementation mapping. |
| `TodayMedicationControl` | `CheckTodayMedicationInfo`, `CheckSchedule`, `SetNotification`, `CheckHealthRecommendation`, `RequestVoiceGuide` | Split by the original UC-3/8/10/11/12 responsibilities. |
| `PatientGuardianLinkControl` | `LinkPatientCaregiver` | Terminology reconciled to the final code/document language. |
| `GuardianAlertSetting` | `CaregiverNotification` | Preference persistence is implemented; remote delivery remains a beta gap. |
| `MedicationAPIBoundary` | `api.router` module | The real FastAPI boundary is documented without inventing a class. |
| UC-15 types | `IdentifyPill`, `PillVisionBoundary`, pill entities/repository | Deliberate v0.0.9 extension documented separately. |

## Known Beta Architecture Gaps

- `PatientHash` and caregiver hashes are demo selectors, not authenticated
  identity. The planned replacement is defined in the beta security document.
- `CaregiverNotification` currently persists preference state; it does not by
  itself prove cross-device delivery.
- `medbuddy.db` is suitable for local/demo execution, not a horizontally scaled
  multi-user deployment.
- Android release builds still require production HTTPS policy and protected
  signing before beta distribution.
