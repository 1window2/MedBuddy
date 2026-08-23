# MedBuddy Class Diagram

## Document Contract

This is the canonical implementation-grounded class view for the
`v0.2.0-beta` development branch and its released `v0.1.0` functional baseline.

- `docs/temp/class diagram v5.png` remains the authoritative first-semester
  conceptual baseline.
- This document preserves that diagram's Boundary-Control-Entity spine while
  using the classes and module boundaries that exist in the repository.
- `docs/MedBuddy - v0.0.9 Pill Identification Extension.md` defines the UC-15
  extension that was not present in v5.
- `docs/MedBuddy - Beta Security Architecture.md` defines the implemented beta
  identity, authorization, deployment, and signing boundaries shown below.

Private Flutter widgets, private Python helper classes, Pydantic transport DTOs,
most SQLAlchemy row mappings, exceptions, and framework-generated state classes
are implementation details. They remain valid code but are omitted from the
primary diagram so the use-case architecture remains readable. Public adapters,
controls, and protocol boundaries that participate in a use case are retained.

## Naming and Layer Rules

1. Frontend and backend classes with the same name are separate tier-local
   implementations and are qualified by package in this document.
2. `api.router`, `api.pharmacy_router`, and `api.chat_router` are FastAPI
   boundary modules. They are not fictional router classes.
3. `api.dependencies` is the backend composition root. It constructs controls
   and shared boundaries; domain controls do not construct the API router.
4. Cross-tier calls use HTTP through `api.router`. No Flutter class directly
   invokes a backend Python class.
5. ORM rows prefixed with `_` are persistence mappings, not domain entities.
   Ownership and lifecycle-critical references use database foreign keys, while
   the ORM intentionally does not expose SQLAlchemy `relationship()` navigation
   for every association. Database links below therefore summarize both enforced
   foreign keys and logical repository access.
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
  class AuthenticationUI <<boundary>>
  class HomeScreen <<boundary>>
  class InputPrescriptionUI <<boundary>>
  class PrescriptionAnalysisProgressUI <<boundary>>
  class PrescriptionAnalysisPreviewUI <<boundary>>
  class PrescriptionAnalysisSuccessUI <<boundary>>
  class PrescriptionAnalysisFailureUI <<boundary>>
  class CheckResultUI <<boundary>>
  class PrescriptionChangeRadarUI <<boundary>>
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
  class ManualMedicationEntryUI <<boundary>>
  class MedicationScheduleReviewBoundary <<function boundary>>
  class CheckNearbyPharmacyUI <<boundary>>
  class LinkedChatUI <<boundary>>
}

package "Flutter / Control" as FE_Control {
  class MedBuddyViewModel <<control, facade>>
  class AuthenticationControl <<control>>
  class "ManageAccount" as FE_ManageAccount <<control>>
  class "InputPrescription" as FE_InputPrescription <<control>>
  class "CheckPrescriptionChange" as FE_CheckPrescriptionChange <<control>>
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
  class "IdentifyPillBatch" as FE_IdentifyPillBatch <<control>>
  class "CheckNearbyPharmacy" as FE_CheckNearbyPharmacy <<control>>
  class "ManageLinkedChat" as FE_ManageLinkedChat <<control>>
}

package "Flutter / Entity" as FE_Entity {
  class AuthSession <<entity>>
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
  class "ManualMedicationEntry" as FE_ManualMedicationEntry <<entity>>
  class "NearbyPharmacy" as FE_NearbyPharmacy <<entity>>
  class "ChatMedicationContext" as FE_ChatMedicationContext <<entity>>
  class "ChatMessage" as FE_ChatMessage <<entity>>
}

package "Flutter / External and Shared Services" as FE_Service {
  class ApiConfig <<configuration>> {
    + validateUrl(value) {static}
  }
  class AuthConfig <<configuration>>
  class "medication_image_url_entity\nsafeMedicationImageUrl()" as MedicationImageUrlPolicy <<egress policy>>
  class AuthenticatedApiClient <<external boundary>>
  class FirebaseRuntimeService <<runtime service>>
  class FirebaseAuth <<external identity provider>>
  class FirebaseAppCheck <<external attestation provider>>
  class ApiResponseParser <<boundary helper>>
  class NotificationService <<external boundary>>
  class TTSService <<external boundary>>
  class PrescriptionLocalOcrService <<privacy boundary>>
  class PushNotificationService <<external boundary>>
  class CaregiverNotificationMonitorService <<application service>>
  class CaregiverNotificationBackgroundScheduler <<runtime scheduler>>
  interface DeviceLocationBoundary <<device boundary>>
  class GeolocatorDeviceLocationService <<device boundary>>
  class PrescriptionGuideLayout <<layout service>>
  class PrescriptionImageCropService <<image service>>
  class ManualMedicationImageStore <<local storage boundary>>
  interface LinkedChatEventSource <<stream boundary>>
  class LinkedChatRealtimeService <<WebSocket service>>
}

package "FastAPI / API Boundary" as BE_API {
  component "api.router" as APIRouter <<boundary>>
  component "api.pharmacy_router" as PharmacyRouter <<boundary>>
  component "api.chat_router" as ChatRouter <<boundary>>
  component "api.dependencies" as APIDependencies <<composition root>>
  class RequestBodyLimitMiddleware <<middleware>>
  class RequestRateLimitMiddleware <<middleware>>
  class Settings <<configuration>>
}

package "FastAPI / Control" as BE_Control {
  class AuthorizationControl <<control>>
  class "ManageAccount" as BE_ManageAccount <<control>>
  class ManagePushToken <<control>>
  class DispatchCaregiverAlert <<control>>
  class "InputPrescription" as BE_InputPrescription <<control>>
  class "CheckPrescriptionChange" as BE_CheckPrescriptionChange <<control>>
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
  class "CheckNearbyPharmacy" as BE_CheckNearbyPharmacy <<control>>
  class "ManageLinkedChat" as BE_ManageLinkedChat <<control>>
  class DispatchChatMessageAlert <<control>>
}

package "FastAPI / Entity" as BE_Entity {
  class AuthenticatedPrincipal <<entity>>
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
  class PharmacyLocationRecord <<entity>>
  class "NearbyPharmacy" as BE_NearbyPharmacy <<entity>>
  class "ChatMessage" as BE_ChatMessage <<entity>>
}

package "FastAPI / External Boundary" as BE_Boundary {
  class OIDCTokenVerifier <<external boundary>>
  class AppCheckTokenVerifier <<external boundary>>
  component "boundaries.firebase_admin_boundary\nget_firebase_admin_app()" as FirebaseAdminModule <<module boundary>>
  interface MedicationCompletionEventBoundary <<protocol boundary>>
  interface PushNotificationBoundary <<protocol boundary>>
  class FirebasePushNotificationBoundary <<external boundary>>
  class PrescriptionImageProcessor <<utility boundary>> {
    + maxPixels: 24000000 {static}
    + processPrescriptionImage(imageBytes)
  }
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
  interface PharmacyLookupBoundary <<protocol boundary>>
  class NationalEmergencyMedicalCenterPharmacyAPI <<external boundary>>
}

package "FastAPI / Policy and Repository" as BE_Support {
  class MedicationCoursePolicy <<policy>>
  class SavedMedicationRetentionPolicy <<policy>>
  class PillIdentificationCatalogRepository <<repository>>
  class ChatMessageRepository <<repository>>
  class ChatConnectionManager <<runtime service>>
}

package "Persistence" {
  database "medbuddy.db\n(local/demo SQLite)" as MedicationDB
  database "Self-hosted PostgreSQL\n(beta production)" as ProductionDB
  database "Redis\n(cache + distributed quota)" as RedisCache
  database "chat_messages\n(link-scoped message history)" as ChatMessageStore
}

' Main Flutter navigation, authentication, and use-case coordination
MedBuddyApp o-- AuthenticationControl
MedBuddyApp o-- PushNotificationService
MedBuddyApp o-- CaregiverNotificationMonitorService
MedBuddyApp ..> CaregiverNotificationBackgroundScheduler
MedBuddyApp --> AuthenticationUI
AuthenticationUI --> AuthenticationControl
AuthenticationControl --> AuthConfig
AuthenticationControl --> FirebaseAuth
AuthenticationControl --> FirebaseRuntimeService
FirebaseRuntimeService --> FirebaseAppCheck
AuthenticationControl --> AuthSession
AuthenticationControl o-- AuthenticatedApiClient
MedBuddyApp o-- MedBuddyViewModel : authenticated session
MedBuddyApp --> HomeScreen
HomeScreen --> MedBuddyViewModel
HomeScreen ..> InputPrescriptionUI
HomeScreen ..> CheckSavedMedicationUI
HomeScreen ..> CheckScheduleUI
HomeScreen ..> LinkPatientCaregiverUI
HomeScreen ..> PillIdentificationUI
HomeScreen ..> ManualMedicationEntryUI
HomeScreen ..> CheckNearbyPharmacyUI
ManageUserSettingUI ..> AuthenticationControl : signOut()
InputPrescriptionUI --> MedBuddyViewModel
PrescriptionAnalysisPreviewUI --> MedBuddyViewModel
CheckResultUI --> MedBuddyViewModel
PrescriptionChangeRadarUI --> MedBuddyViewModel
CheckSavedMedicationUI --> MedBuddyViewModel
CheckScheduleUI --> MedBuddyViewModel
HealthRecommendationUI --> MedBuddyViewModel
MedBuddyViewModel o-- FE_InputPrescription
MedBuddyViewModel o-- FE_ManageAccount
MedBuddyViewModel o-- FE_CheckPrescriptionChange
MedBuddyViewModel o-- FE_CheckSavedMedication
MedBuddyViewModel o-- FE_CheckSchedule
MedBuddyViewModel o-- FE_CheckHealthRecommendation
MedBuddyViewModel o-- FE_ManageUserSetting
LinkPatientCaregiverUI --> FE_LinkPatientCaregiver
CheckCaregiverMedicationUI --> FE_CheckCaregiverMedication
CheckCaregiverMedicationUI --> FE_SetCaregiverNotification
CheckCaregiverMedicationUI ..> SetCaregiverNotificationUI : opens dialog
SetCaregiverNotificationUI ..> SetNotificationUI : selects deadline
SetNotificationUI --> FE_SetNotification
CheckMedicationDetailUI --> FE_CheckMedicationDetail
CheckMedicationDetailUI --> FE_RequestVoiceGuide
PillIdentificationUI --> FE_IdentifyPill
PillIdentificationUI --> FE_IdentifyPillBatch
PillIdentificationUI ..> MedicationScheduleReviewBoundary
PrescriptionAnalysisPreviewUI ..> MedicationScheduleReviewBoundary
ManualMedicationEntryUI --> FE_ManualMedicationEntry
ManualMedicationEntryUI --> FE_CheckSavedMedication
ManualMedicationEntryUI --> ManualMedicationImageStore
CheckNearbyPharmacyUI --> FE_CheckNearbyPharmacy
CheckCaregiverMedicationUI ..> LinkedChatUI
LinkedChatUI --> FE_ManageLinkedChat
LinkedChatUI --> LinkedChatRealtimeService

' Frontend entities and local external services
FE_InputPrescription --> FE_AnalyzedMedication
FE_InputPrescription --> PrescriptionLocalOcrService
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
FE_IdentifyPillBatch --> FE_IdentifyPill
FE_CheckNearbyPharmacy --> DeviceLocationBoundary
GeolocatorDeviceLocationService ..|> DeviceLocationBoundary
FE_CheckNearbyPharmacy --> FE_NearbyPharmacy
FE_ManageLinkedChat --> FE_ChatMessage
FE_ManageLinkedChat --> FE_ChatMedicationContext
FE_ChatMessage o-- "0..1" FE_ChatMedicationContext
LinkedChatRealtimeService ..|> LinkedChatEventSource
FE_PillResult *-- "0..*" FE_PillCandidate
FE_PillResult *-- FE_PillVisualFeatures
FE_MedicationDetail ..> MedicationImageUrlPolicy : sanitize API and stored value
FE_MedicationSchedule ..> MedicationImageUrlPolicy : sanitize API and stored value
FE_PillCandidate ..> MedicationImageUrlPolicy : sanitize API value
CheckMedicationDetailUI ..> MedicationImageUrlPolicy : revalidate before fetch
CheckSavedMedicationUI ..> MedicationImageUrlPolicy : revalidate before fetch
CheckScheduleUI ..> MedicationImageUrlPolicy : revalidate before fetch
CheckCaregiverMedicationUI ..> MedicationImageUrlPolicy : revalidate before fetch
PillIdentificationUI ..> MedicationImageUrlPolicy : revalidate before fetch
FE_SetNotification ..> NotificationService
FE_RequestVoiceGuide ..> TTSService
PushNotificationService --> AuthenticatedApiClient : token lifecycle
CaregiverNotificationMonitorService --> AuthenticatedApiClient : adherence polling
CaregiverNotificationBackgroundScheduler ..> CaregiverNotificationMonitorService

' Every Flutter control reaches the backend only through authenticated HTTP
FE_Control ..> AuthenticatedApiClient
AuthenticatedApiClient --> APIRouter : HTTPS + Bearer + App Check
FE_Control ..> ApiConfig
FE_Control ..> ApiResponseParser

' FastAPI composition and use-case controls
RequestBodyLimitMiddleware --> APIRouter
RequestRateLimitMiddleware --> APIRouter
RequestRateLimitMiddleware --> RedisCache : distributed quota
APIRouter --> APIDependencies
PharmacyRouter --> APIDependencies
ChatRouter --> APIDependencies
APIDependencies o-- OIDCTokenVerifier
APIDependencies o-- AppCheckTokenVerifier
OIDCTokenVerifier --> FirebaseAdminModule : get_firebase_admin_app()
AppCheckTokenVerifier --> FirebaseAdminModule : get_firebase_admin_app()
FirebasePushNotificationBoundary --> FirebaseAdminModule : get_firebase_admin_app()
FirebasePushNotificationBoundary ..|> PushNotificationBoundary
APIDependencies o-- AuthorizationControl
APIDependencies o-- BE_ManageAccount
APIDependencies o-- ManagePushToken
APIDependencies o-- DispatchCaregiverAlert
APIDependencies o-- PushNotificationBoundary
OIDCTokenVerifier --> AuthenticatedPrincipal
APIRouter --> AuthenticatedPrincipal
APIRouter --> AuthorizationControl : resolve trusted scope
AuthorizationControl --> BE_PatientCaregiverLink
APIDependencies o-- BE_InputPrescription
APIDependencies o-- BE_CheckPrescriptionChange
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
APIDependencies o-- BE_CheckNearbyPharmacy
APIDependencies o-- BE_ManageLinkedChat
APIDependencies o-- DispatchChatMessageAlert
APIDependencies o-- ChatConnectionManager

' Prescription pipeline
BE_InputPrescription --> OCRServiceBoundary
OCRServiceBoundary --> PrescriptionImageProcessor
OCRServiceBoundary --> GeminiVisionClient
BE_InputPrescription --> PrescriptionText
BE_InputPrescription --> MedicationCandidateList
MedicationCandidateList *-- "0..*" MedicationCandidate
BE_InputPrescription --> PrescriptionAnalysisResult
PrescriptionAnalysisResult *-- "0..*" MedicationCandidate
BE_CheckPrescriptionChange --> BE_MedicationSchedule

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
BE_CheckSchedule --> MedicationCompletionEventBoundary
DispatchCaregiverAlert ..|> MedicationCompletionEventBoundary
DispatchCaregiverAlert --> PushNotificationBoundary
DispatchCaregiverAlert --> BE_CaregiverNotification
BE_SetCaregiverNotification --> BE_CaregiverNotification
BE_LinkPatientCaregiver --> BE_PatientLinkCode
BE_LinkPatientCaregiver --> BE_PatientCaregiverLink
BE_CheckHealthRecommendation --> LLMService
BE_CheckHealthRecommendation --> BE_HealthRecommendation
BE_ManageUserSetting --> BE_UserSetting
BE_ManageAccount ..> MedicationDB : local account lifecycle
BE_ManageAccount ..> ProductionDB : beta account lifecycle
ManagePushToken ..> MedicationDB : local device-token lifecycle
ManagePushToken ..> ProductionDB : beta device-token lifecycle

' UC-15 loose-pill extension
BE_IdentifyPill --> PillVisionBoundary
PillVisionBoundary --> PillImageProcessingBoundary
PillVisionBoundary --> GeminiPillVisionAPI
BE_IdentifyPill --> MFDSPillCatalogBoundary
MFDSPillCatalogBoundary --> MFDSPillAPI
MFDSPillCatalogBoundary --> PillIdentificationCatalogRepository
PillIdentificationCatalogRepository --> PillIdentificationReference
PillIdentificationReference --> MedicationDB : local table
PillIdentificationReference --> ProductionDB : beta table
BE_IdentifyPill --> BE_PillResult
BE_PillResult *-- "0..*" BE_PillCandidate
BE_PillResult *-- BE_PillVisualFeatures
BE_PillCandidate --> PillCatalogEntry

' v0.2.0 direct-entry, nearby-pharmacy, and medication-context chat extensions
FE_ManualMedicationEntry --> FE_MedicationSchedule
BE_CheckNearbyPharmacy --> PharmacyLookupBoundary
NationalEmergencyMedicalCenterPharmacyAPI ..|> PharmacyLookupBoundary
BE_CheckNearbyPharmacy --> PharmacyLocationRecord
BE_CheckNearbyPharmacy --> BE_NearbyPharmacy
BE_ManageLinkedChat --> ChatMessageRepository
BE_ManageLinkedChat --> BE_PatientCaregiverLink
BE_ManageLinkedChat --> BE_MedicationSchedule
BE_ManageLinkedChat --> BE_ChatMessage
DispatchChatMessageAlert --> PushNotificationBoundary
DispatchChatMessageAlert --> ChatConnectionManager
ChatMessageRepository --> ChatMessageStore

' Persistence is logical; private ORM rows implement these mappings
BE_Control ..> MedicationDB
BE_Control ..> ProductionDB : production mapping
AuthorizationControl ..> ProductionDB
BE_CheckMedicationDetail ..> RedisCache
MedicationDB ..> BE_MedicationSchedule
MedicationDB ..> BE_MedicationAlarm
MedicationDB ..> MedicationCompletion
MedicationDB ..> BE_CaregiverNotification
MedicationDB ..> BE_PatientCaregiverLink
MedicationDB ..> BE_UserSetting
MedicationDB ..> ChatMessageStore
@enduml
```

## Deployment Runtime Role View

Runtime roles are deployment entry points configured through `Settings`; they
are not additional domain classes. All four roles execute the same immutable
backend image while exposing different processes and dependencies.

```plantuml
@startuml MedBuddy_Runtime_Roles
left to right direction
skinparam packageStyle rectangle

artifact "MedBuddy backend image" as BackendImage

package "Self-hosted API container" {
  component "API process\nRUNTIME_ROLE=api" as ApiRuntime
  component "api.router" as RuntimeRouter <<boundary>>
  component RequestRateLimitMiddleware as RuntimeRateLimit <<middleware>>
}

package "Controlled maintenance commands" {
  component "Migration process\nRUNTIME_ROLE=migration" as MigrationRuntime
  component "Maintenance process\nRUNTIME_ROLE=maintenance" as MaintenanceRuntime
  component "Catalog sync process\nRUNTIME_ROLE=catalog_sync" as CatalogRuntime
  component "Alembic CLI" as AlembicRuntime <<migration tool>>
  class DataMaintenanceService <<service>>
  class DrugCatalogSyncJob <<job>>
}

database "Self-hosted PostgreSQL" as RuntimeDatabase
database "Private-network Redis" as RuntimeRedis
cloud "Firebase Auth / App Check / FCM" as RuntimeFirebase
cloud "Public medication APIs" as RuntimePublicAPIs

BackendImage ..> ApiRuntime
BackendImage ..> MigrationRuntime
BackendImage ..> MaintenanceRuntime
BackendImage ..> CatalogRuntime

ApiRuntime --> RuntimeRouter
ApiRuntime --> RuntimeRateLimit
ApiRuntime --> RuntimeDatabase
RuntimeRateLimit --> RuntimeRedis
ApiRuntime --> RuntimeFirebase

MigrationRuntime --> AlembicRuntime
AlembicRuntime --> RuntimeDatabase : upgrade head
MaintenanceRuntime --> DataMaintenanceService
DataMaintenanceService --> RuntimeDatabase
CatalogRuntime --> DrugCatalogSyncJob
DrugCatalogSyncJob --> RuntimePublicAPIs
DrugCatalogSyncJob --> RuntimeDatabase : shared catalog writer
@enduml
```

## Public Architectural Type Inventory

The primary and runtime diagrams include architecturally significant public
production types that own a use case, external integration, or process
lifecycle. They are not intended to duplicate every public source declaration.
The following categories are intentionally not expanded into separate diagram
nodes:

| Category | Examples | Reason |
| --- | --- | --- |
| Flutter private presentation types | `_MedicationResultCard`, `_ScheduleSlot`, `_PillImageSlot` | File-local rendering decomposition; no domain responsibility. |
| Flutter state classes | `_CheckScheduleUIState`, `_PillIdentificationUIState` | Framework lifecycle implementation owned by the public UI boundary. |
| View-model result/projection types | `TodayMedicationProgress`, `SavedMedicationBatchDeleteResult`, `MedicationSaveResult` | Typed return/state projections owned by their control or view model. |
| Theme tokens | `MedBuddyColors`, `MedBuddyRadii`, `MedBuddyShadows` | Shared presentation constants without use-case behavior. |
| Transport DTOs | `OCRParseRequest`, `MedicationRequest`, `MedicationResponse`, `PillIdentificationResponse` | API serialization contracts, not domain coordinators. |
| Private ORM rows | `_SavedMedication`, `_MedicationAlarm`, `_PatientCaregiverLink` | Persistence mappings; lifecycle-critical references are enforced with database foreign keys even though ORM navigation relationships are generally omitted. |
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
| Prescription comparison extension | frontend/backend `CheckPrescriptionChange`, `PrescriptionChangeRadarUI` | Compares a confirmed prescription with related saved history without expanding `InputPrescription` beyond analysis. |
| `MedicationSaveControl` | `CheckMedicationDetail` plus `CheckSavedMedication` | Detail enrichment and persistence remain separate cohesive controls. |
| `SavedMedicationControl` | `CheckSavedMedication` | Direct implementation mapping. |
| `TodayMedicationControl` | `CheckTodayMedicationInfo`, `CheckSchedule`, `SetNotification`, `CheckHealthRecommendation`, `RequestVoiceGuide` | Split by the original UC-3/8/10/11/12 responsibilities. |
| `PatientGuardianLinkControl` | `LinkPatientCaregiver` | Terminology reconciled to the final code/document language. |
| `GuardianAlertSetting` | `CaregiverNotification` | Preference persistence is implemented; remote delivery remains a beta gap. |
| Account and device lifecycle | frontend/backend `ManageAccount`, backend `ManagePushToken` | Beta authentication adds explicit account-data and FCM-token lifecycle controls outside the original v5 scope. |
| Caregiver alert delivery | `MedicationCompletionEventBoundary`, `DispatchCaregiverAlert`, `PushNotificationBoundary` | Completion persistence remains in `CheckSchedule`; downstream delivery is isolated behind protocol boundaries. |
| `MedicationAPIBoundary` | `api.router` module | The real FastAPI boundary is documented without inventing a class. |
| Firebase Admin SDK ownership | `boundaries.firebase_admin_boundary` module | A locked module-level `get_firebase_admin_app()` factory owns the shared SDK application; no helper class is invented. |
| UC-15 types | `IdentifyPill`, `PillVisionBoundary`, pill entities/repository | Deliberate v0.0.9 extension documented separately. |
| Guided capture and schedule confirmation | `PrescriptionGuideLayout`, `PrescriptionImageCropService`, `MedicationScheduleReviewBoundary` | Captured content is cropped to the visible guide and recognized schedules remain user-correctable before analysis or save. |
| Direct medication entry | `ManualMedicationEntryUI`, `ManualMedicationImageStore`, shared saved-medication control | Manual input reuses the established medication persistence and schedule model instead of creating a parallel domain. |
| Multi-pill batch identification | `IdentifyPillBatch` over `IdentifyPill` | Bounded concurrency and per-item outcomes extend the single-pill control without duplicating the identification pipeline. |
| Nearby pharmacy laboratory feature | frontend/backend `CheckNearbyPharmacy`, `DeviceLocationBoundary`, `PharmacyLookupBoundary` | Device location, server API-key ownership, normalization, and presentation remain separate cohesive boundaries. |
| Medication-context chat laboratory feature | frontend/backend `ManageLinkedChat`, `LinkedChatRealtimeService`, `ChatMessageRepository` | Active-link authorization, REST persistence, WebSocket delivery, medication snapshots, and generic push alerts are separated by responsibility. |

## Known Beta Architecture Gaps

- Firebase authentication and server-side authorization are implemented, but
  self-hosted public HTTPS, protected host secrets, backup/restore, and the
  signed two-device smoke test remain deployment gates.
- `CaregiverNotification` persists preference state and the FCM boundaries
  implement delivery, but source structure alone does not prove signed
  cross-device delivery against provisioned Firebase resources.
- `medbuddy.db` remains local/demo storage; production uses the same ORM mapping
  through Alembic-managed PostgreSQL.
- App Check, Redis-backed distributed rate limiting, shared catalog
  persistence, and self-hosted runtime roles are implemented in source.
  Public ingress, provisioned Firebase configuration, and signed two-device
  tests remain operational beta gates.
- The nearby-pharmacy and medication-context chat features are disabled by
  default laboratory toggles. Enabling a toggle changes presentation only;
  backend authorization, active-link checks, and medication ownership checks
  remain mandatory.
- WebSocket chat delivery still requires production `WSS` routing, reconnect
  verification, and two-device notification tests before a v0.2.0 release.
