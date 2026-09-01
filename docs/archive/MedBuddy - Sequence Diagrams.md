# MedBuddy Sequence Diagrams

이 문서는 MedBuddy의 주요 상호작용을 Boundary-Control-Entity 관점으로 정리한 PlantUML 시퀀스 다이어그램 제안본이다.

> **Implementation status (2026-07-20):** The six UC-1 through UC-14 groups
> below preserve the first-semester behavioral baseline. Current implementation
> names are defined by `MedBuddy - Class Diagram.md`: use `Caregiver`,
> `LinkPatientCaregiver`, and `CaregiverNotification` where older diagrams say
> `Guardian`, `PatientGuardianLinkControl`, or `GuardianAlertSetting`. UC-15
> loose-pill identification is documented in `MedBuddy - v0.0.9 Pill
> Identification Extension.md`. Caregiver preference persistence is implemented,
> but cross-device caregiver alert delivery is a beta requirement and must not
> be inferred from the external notification messages in this historical flow.
> Authentication and HTTPS are cross-cutting beta additions defined in
> `MedBuddy - Beta Security Architecture.md`.

## 수정 기준과 논거

- `boundary`는 사용자 화면, 외부 API, 로컬 저장소처럼 시스템 경계에서 입출력을 담당하는 객체로 둔다.
- `control`은 시나리오의 순서, 분기 조건, 트랜잭션 흐름을 조정하는 객체로 둔다.
- `entity`는 처방 분석 결과, 저장 복약 정보, 사용자 설정, 연동 정보처럼 도메인 상태를 가지는 객체로 둔다.
- `database`는 entity의 영속화 저장소로만 표현한다. DB가 직접 업무 규칙을 판단하지 않는다.
- `alt`는 상호 배타적인 조건 분기에만 사용한다. 예: 환자/보호자 권한, 캐시 hit/miss, API 조회 성공/실패.
- `opt`는 기본 시나리오 이후 사용자가 선택할 때만 발생하는 확장 흐름에 사용한다. 예: 상세 보기, 삭제, 알림 설정, 음성 안내.
- `loop`는 동일한 메시지 패턴이 반복되는 경우에만 사용한다. 예: 약물 후보 반복, 복약 카드 렌더링, 설정 항목 반복 변경.
- `break`는 이후 흐름을 진행할 수 없는 중단 조건에 사용한다. 예: 촬영 취소, 연동 환자 없음, 약 정보 미검색.
- `critical`은 DB 상태 변경과 외부 알림 등록처럼 원자성이 필요한 변경 구간에 사용한다.
- `par`는 하나의 커밋 이후 서로 독립적으로 갱신 가능한 UI/알림 흐름에만 제한적으로 사용한다.

최종 시퀀스 다이어그램은 다음 6개로 구성한다.

| No. | 시나리오 | 관련 유스케이스 |
| --- | --- | --- |
| 1 | 처방전/약봉투 이미지 입력, 분석, 결과 확인 | UC-1, UC-2 |
| 2 | 분석된 약물 상세 조회 및 저장 | UC-4, UC-9 |
| 3 | 저장된 복약 정보 조회, 상세 확인, 삭제, 보호자 알림 설정 | UC-4, UC-5, UC-9, UC-13 |
| 4 | 오늘의 복약 일정 확인, 건강 추천, 음성 안내, 알림, 복약 완료 | UC-3, UC-8, UC-10, UC-11, UC-12 |
| 5 | 환자/보호자 연동 및 연동 해제 | UC-6, UC-7 |
| 6 | 사용자 설정 | UC-14 |

## 1. 처방전/약봉투 이미지 입력, 분석, 결과 확인

### 수정 논거

- 처방전 OCR은 기기 내 Google ML Kit에서 수행하고 개인정보 필터를 통과한 비식별 텍스트만 서버에 전송한다.
- 가이드 카메라 촬영은 화면에 표시한 영역과 같은 원본 좌표를 사용해 이미지를 자른 뒤 OCR로 전달한다.
- OCR 누락 행은 사용자가 표에서 직접 추가할 수 있으며, 수정한 행 식별자와 순서는 상세 조회까지 유지한다.
- 일부 상세 조회만 실패하면 확인된 행은 잠그고 미확인 행만 수정·재시도한다. 미확인 행을 제외하고 계속 진행하려면 별도 확인을 거친다.
- 모든 조회가 연결·시간초과 같은 기술 오류로 실패한 경우에만 전체 실패 화면으로 분기한다.

```plantuml
@startuml SD01_Prescription_Analysis
autonumber
actor "환자" as Patient
boundary "GuidedPrescriptionCameraUI" as CameraUI
boundary "PrescriptionAnalysisPreviewUI" as UI
control "MedBuddyViewModel" as VM
boundary "PrescriptionImageCropService" as Crop
boundary "PrescriptionLocalOcrService" as OCR
boundary "PrescriptionPrivacyFilter" as Privacy
boundary "FastAPI prescription-text endpoint" as API
control "InputPrescription" as Parse
boundary "MedicationDetail endpoint" as Detail
entity "MedicationSchedule review rows" as Rows
entity "PrescriptionAnalysisResult" as Result

Patient -> CameraUI : openPrescriptionCapture()
CameraUI --> Patient : displayGuideAndCameraPreview()

break [pickedFile == null]
  Patient -> CameraUI : cancelCapture()
  CameraUI --> Patient : keepPreviousScreen()
end

alt [guided camera capture]
  Patient -> CameraUI : captureInsideGuide()
  CameraUI -> Crop : cropToGuide(image, normalizedGuideRect)
  Crop --> CameraUI : croppedImage
  CameraUI -> UI : submitPrescriptionImage(croppedImage)
else [gallery selection]
  Patient -> UI : submitPrescriptionImage(galleryImage)
end
UI -> OCR : recognize(selectedImage)
activate OCR
OCR -> Privacy : removeSensitiveText(recognizedBlocks)
Privacy --> OCR : deidentifiedText, displayRegions
OCR --> UI : localOcrResult
deactivate OCR

UI -> API : parsePrescriptionText(deidentifiedText)
API -> Parse : parseAndNormalize(deidentifiedText)
Parse --> API : medication schedules
API --> UI : parsed rows
UI -> Rows : <<create>> preserve source row indexes
UI --> Patient : displayEditableReviewTable()

opt [OCR missed a medication]
  Patient -> UI : addMedicationRow(values)
  UI -> Rows : append row with stable index
end

Patient -> UI : confirmAndAnalyze()
UI -> VM : identifyMedicationDetails(rows)
loop [for each unresolved review row]
  VM -> Detail : lookupMedication(row.name)
  Detail --> VM : verified detail or unresolved/error
end

alt [all requests failed technically]
  VM --> UI : technicalFailure
  UI --> Patient : displayActionableFailure()
else [one or more rows unresolved]
  VM --> UI : verified details + unresolved row indexes
  UI -> Rows : lock verified rows and keep unresolved editable
  UI --> Patient : displayPartialRecoveryTable()
  alt [patient corrects and retries]
    Patient -> UI : editUnresolvedRowsAndRetry()
    UI -> VM : identifyMedicationDetails(unresolved rows only)
  else [patient continues with verified rows]
    UI --> Patient : requestExplicitConfirmation()
    Patient -> UI : confirmVerifiedOnly()
  end
else [all rows verified]
  VM -> Result : <<create>> preserve row-aligned details
  VM --> UI : completedAnalysisResult
  UI --> Patient : displayAnalysisResult()
end
@enduml
```

## 2. 분석된 약물 상세 조회 및 저장

### 수정 논거

- Redis 캐시 조회는 `cache hit`과 `cache miss`가 동시에 성립할 수 없으므로 `alt`로 분리했다.
- 공공 API 조회는 실제 코드 흐름처럼 Basic API 우선, 결과가 없으면 Advanced API fallback으로 표현했다.
- Basic API는 여러 건을 반환할 수 있으므로 `loop [for each basic API item]`와 `loop [for each DrugInfo without aiGuide]`를 사용했다.
- 조회 결과가 없는 경우 저장으로 넘어가면 안 되므로 `alt [drugInfoList is empty]`에서 사용자에게 실패를 표시하고 저장 경로와 분리했다.
- 저장은 DB insert, commit, 목록 최신화가 하나의 변경 흐름이므로 `critical persist selected medication`으로 묶었다.

```plantuml
@startuml SD02_Drug_Detail_Save
autonumber
actor "환자" as Patient
boundary "PrescriptionAnalysisResultUI_boundary" as UI
control "MedicationSave_control" as C
entity "MedicationCandidateList_entity" as Candidates
database "RedisCache_database" as Cache
boundary "PublicDrugDataPortal_boundary" as DrugAPI
boundary "LLMService_boundary" as LLM
entity "MedicationInfo_entity" as Info
entity "SavedMedicationInfo_entity" as Saved
database "MedicationDB_database" as DB

Patient -> UI : clickAnalyzeAndSave(rawDrug)
activate UI
UI -> C : requestMedicationDetailAndSave(rawDrug)
activate C
C --> UI : showAnalyzingAndSaving()

C -> Candidates : normalizeCandidateName(rawDrug)
activate Candidates
Candidates --> C : medicineName
deactivate Candidates

C -> Cache : findDrugInfo(medicineName)
activate Cache
Cache --> C : cacheLookupResult
deactivate Cache

alt [cache hit]
  C -> Info : loadMedicationInfoList(cacheLookupResult)
  activate Info
  Info --> C : drugInfoList
  deactivate Info
else [cache miss]
  C -> DrugAPI : searchBasicDrugInfo(medicineName)
  activate DrugAPI
  DrugAPI --> C : basicSearchResult
  deactivate DrugAPI

  alt [basicSearchResult has items]
    create Info
    C -> Info : <<create>> MedicationInfoList()
    activate Info
    loop [for each basic API item]
      C -> Info : addBasicDrugInfo(item)
    end
    Info --> C : drugInfoList
    deactivate Info

    loop [for each DrugInfo without aiGuide]
      C -> LLM : generateFriendlyGuide(drugInfo)
      activate LLM
      LLM --> C : aiGuide
      deactivate LLM
      C -> Info : attachAiGuide(drugInfo, aiGuide)
    end
  else [basicSearchResult is empty]
    C -> DrugAPI : searchAdvancedDrugInfo(medicineName)
    activate DrugAPI
    DrugAPI --> C : advancedSearchResult
    deactivate DrugAPI

    alt [advancedSearchResult has item]
      C -> LLM : summarizeAdvancedDrugDocument(advancedSearchResult)
      activate LLM
      LLM --> C : summarizedDrugInfo
      deactivate LLM
      create Info
      C -> Info : <<create>> MedicationInfo(summarizedDrugInfo)
      activate Info
      Info --> C : drugInfoList
      deactivate Info
    else [advancedSearchResult is empty]
      C -> Info : buildEmptyMedicationInfoList()
      activate Info
      Info --> C : emptyDrugInfoList
      deactivate Info
    end
  end

  opt [drugInfoList is not empty]
    C -> Cache : saveDrugInfo(medicineName, drugInfoList, ttl=7days)
    activate Cache
    Cache --> C : cacheSaved
    deactivate Cache
  end
end

alt [drugInfoList is empty]
  C --> UI : showMedicationNotFound(medicineName)
  UI --> Patient : displayMedicationNotFound()
else [drugInfoList is not empty]
  C -> Info : selectBestMatchedDrugInfo(drugInfoList)
  activate Info
  Info --> C : selectedDrugInfo
  deactivate Info

  critical persist selected medication
    create Saved
    C -> Saved : <<create>> SavedMedicationInfo(selectedDrugInfo)
    activate Saved
    Saved -> DB : insertSavedMedication(savedMedication)
    activate DB
    DB --> Saved : savedMedicationId
    deactivate DB
    Saved -> DB : findSavedMedicationList()
    activate DB
    DB --> Saved : updatedSavedMedicationList
    deactivate DB
    Saved --> C : updatedSavedMedicationList
    deactivate Saved
  end

  C --> UI : showSaveSuccess(updatedSavedMedicationList)
  UI --> Patient : displaySaveSuccessMessage()
end

deactivate C
deactivate UI
@enduml
```

## 3. 저장된 복약 정보 조회, 상세 확인, 삭제, 보호자 알림 설정

### 수정 논거

- 환자는 자신의 `patientHash`로 바로 조회하지만, 보호자는 연동된 환자를 먼저 찾아야 하므로 `alt [role == PATIENT] / [role == GUARDIAN]`로 접근 경로를 분리했다.
- 보호자에게 연동 환자가 없으면 저장 복약 정보 조회가 불가능하므로 `break [linked patient is not found]`로 중단 조건을 둔다.
- 조회된 복약 정보 목록 렌더링은 항목 수만큼 반복되므로 `loop [for each saved medication]`로 표시했다.
- 상세 확인, 삭제, 보호자 알림 설정은 기본 조회 이후 선택적으로 발생하므로 각각 `opt`로 분리했다.
- 삭제와 보호자 알림 변경은 DB 상태와 알림 서비스 상태가 함께 바뀌므로 `critical` 구간으로 묶었다.

```plantuml
@startuml SD03_Saved_Medication_Management
autonumber
actor "환자" as Patient
actor "보호자" as Guardian
boundary "SavedMedicationUI_boundary" as UI
control "SavedMedication_control" as C
entity "PatientGuardianLink_entity" as CareLink
entity "SavedMedicationInfo_entity" as Saved
database "MedicationDB_database" as DB
boundary "PublicDrugDataPortal_boundary" as DrugAPI
entity "GuardianAlertSetting_entity" as Alert
boundary "NotificationService_boundary" as Notify

alt [role == PATIENT]
  Patient -> UI : clickSavedMedicationInfo()
else [role == GUARDIAN]
  Guardian -> UI : clickSharedMedicationInfo()
end
activate UI
UI -> C : requestSavedMedicationInfo(userHash, role)
activate C

alt [role == PATIENT]
  C -> C : resolvePatientHash(userHash)
else [role == GUARDIAN]
  C -> CareLink : getLinkedPatientHash(guardianHash)
  activate CareLink
  CareLink -> DB : findLinkedPatientHash(guardianHash)
  activate DB
  DB --> CareLink : linkedPatientLookupResult
  deactivate DB
  CareLink --> C : linkedPatientLookupResult
  deactivate CareLink

  break [linked patient is not found]
    C --> UI : showNoLinkedPatient()
    UI --> Guardian : displayNoLinkedPatient()
  end
end

C -> Saved : getSavedMedicationList(patientHash)
activate Saved
Saved -> DB : findSavedMedicationList(patientHash)
activate DB
DB --> Saved : savedMedicationList
deactivate DB
Saved --> C : savedMedicationList
deactivate Saved

alt [savedMedicationList is empty]
  C --> UI : showEmptySavedMedicationInfo()
else [savedMedicationList is not empty]
  C --> UI : showSavedMedicationInfo(savedMedicationList)
  loop [for each saved medication]
    UI -> UI : renderSavedMedicationCard(savedMedication)
  end
end

alt [role == PATIENT]
  UI --> Patient : displaySavedMedicationInfo()
else [role == GUARDIAN]
  UI --> Guardian : displaySharedMedicationInfo()
end
deactivate C
deactivate UI

opt [user selects a medicine detail]
  alt [selected by patient]
    Patient -> UI : clickMedicineName(medicineName)
  else [selected by guardian]
    Guardian -> UI : clickMedicineName(medicineName)
  end
  activate UI
  UI -> C : requestDrugInfo(medicineName)
  activate C
  C -> DrugAPI : searchDrugInfo(medicineName)
  activate DrugAPI
  DrugAPI --> C : drugInfo
  deactivate DrugAPI
  C --> UI : showDrugDetail(drugInfo)
  alt [selected by patient]
    UI --> Patient : displayDrugDetail()
  else [selected by guardian]
    UI --> Guardian : displayDrugDetail()
  end
  deactivate C
  deactivate UI
end

opt [patient requests deletion]
  Patient -> UI : clickDeleteSavedMedication(savedMedicationId)
  activate UI
  UI -> C : requestDeleteSavedMedication(savedMedicationId)
  activate C
  C --> UI : showDeleteConfirmPopup()

  alt [confirm delete]
    Patient -> UI : confirmDelete()
    UI -> C : deleteSavedMedication(patientHash, savedMedicationId)
    critical delete saved medication transaction
      C -> Saved : deleteSavedMedicationInfo(patientHash, savedMedicationId)
      activate Saved
      Saved -> DB : deleteSavedMedication(patientHash, savedMedicationId)
      activate DB
      DB --> Saved : deleteStatus
      deactivate DB
      Saved -> DB : findSavedMedicationList(patientHash)
      activate DB
      DB --> Saved : updatedSavedMedicationList
      deactivate DB
      Saved --> C : updatedSavedMedicationList
      deactivate Saved
    end
    C --> UI : showUpdatedSavedMedicationInfo(updatedSavedMedicationList)
    UI --> Patient : displayUpdatedSavedMedicationInfo()
  else [cancel delete]
    Patient -> UI : cancelDelete()
    UI -> C : cancelDeleteSavedMedication()
    C --> UI : closeDeleteConfirmPopup()
    UI --> Patient : displaySavedMedicationInfo()
  end

  deactivate C
  deactivate UI
end

opt [guardian changes alert setting]
  Guardian -> UI : clickGuardianAlertBell(patientHash)
  activate UI
  UI -> C : requestGuardianAlertSetting(guardianHash, patientHash)
  activate C
  C -> Alert : getGuardianAlertSetting(guardianHash, patientHash)
  activate Alert
  Alert -> DB : findGuardianAlertSetting(guardianHash, patientHash)
  activate DB
  DB --> Alert : guardianAlertSettingLookupResult
  deactivate DB
  Alert --> C : guardianAlertSettingLookupResult
  deactivate Alert

  alt [setting exists]
    C --> UI : showGuardianAlertSettingPopup(guardianAlertSetting)
  else [setting does not exist]
    C -> Alert : initializeDefaultGuardianAlertSetting(guardianHash, patientHash)
    activate Alert
    Alert -> DB : insertGuardianAlertSetting(defaultDisabled)
    activate DB
    DB --> Alert : createdAlertSetting
    deactivate DB
    Alert --> C : guardianAlertSetting
    deactivate Alert
    C --> UI : showGuardianAlertSettingPopup(guardianAlertSetting)
  end

  Guardian -> UI : selectGuardianAlertOption(alertOption)
  UI -> C : updateGuardianAlertSetting(guardianHash, patientHash, alertOption)

  critical update guardian alert state
    alt [alertOption == ENABLE]
      C -> Alert : enableGuardianAlert(guardianHash, patientHash)
      activate Alert
      Alert -> DB : updateGuardianAlertEnabled(true)
      activate DB
      DB --> Alert : enabledAlertSetting
      deactivate DB
      Alert --> C : enabledAlertSetting
      deactivate Alert
      C -> Notify : registerGuardianAlert(enabledAlertSetting)
      activate Notify
      Notify --> C : guardianAlertRegistered
      deactivate Notify
    else [alertOption == DISABLE]
      C -> Alert : disableGuardianAlert(guardianHash, patientHash)
      activate Alert
      Alert -> DB : updateGuardianAlertEnabled(false)
      activate DB
      DB --> Alert : disabledAlertSetting
      deactivate DB
      Alert --> C : disabledAlertSetting
      deactivate Alert
      C -> Notify : cancelGuardianAlert(disabledAlertSetting)
      activate Notify
      Notify --> C : guardianAlertCancelled
      deactivate Notify
    end
  end

  C --> UI : updateGuardianAlertBell(alertOption)
  UI --> Guardian : displayGuardianAlertState()
  deactivate C
  deactivate UI
end
@enduml
```

## 4. 오늘의 복약 일정 확인, 건강 추천, 음성 안내, 알림, 복약 완료

### 수정 논거

- 환자와 보호자는 같은 화면을 볼 수 있지만 권한 해석 방식이 다르므로 일정 조회 전 `alt`로 환자 식별 과정을 분리했다.
- 보호자가 연동된 환자를 찾지 못하면 이후 일정 조회가 불가능하므로 `break [linked patient is not found]`를 둔다.
- 복약 일정은 여러 약과 여러 시간대의 조합으로 구성되므로 `loop [for each medication and time slot]`로 일정 계산을 표현했다.
- 건강 추천, 약 상세 정보, 음성 안내, 알림 설정, 복약 완료는 오늘 일정 조회 이후 선택적으로 발생하는 확장 흐름이므로 `opt`로 분리했다.
- 알림 설정과 복약 완료 기록은 상태 변경이므로 `critical`로 묶었다.

```plantuml
@startuml SD04_Today_Medication
autonumber
actor "환자" as Patient
actor "보호자" as Guardian
boundary "TodayMedicationUI_boundary" as UI
control "TodayMedication_control" as C
entity "PatientGuardianLink_entity" as CareLink
entity "MedicationSchedule_entity" as Schedule
database "MedicationDB_database" as DB
entity "HealthRecommendation_entity" as Recommend
boundary "LLMService_boundary" as LLM
boundary "PublicDrugDataPortal_boundary" as DrugAPI
entity "MedicationAlarm_entity" as Alarm
boundary "NotificationService_boundary" as Notify
boundary "TTSService_boundary" as TTS
entity "MedicationCompletion_entity" as Complete

alt [role == PATIENT]
  Patient -> UI : openMainScreen()
else [role == GUARDIAN]
  Guardian -> UI : openSharedMainScreen()
end
activate UI
UI -> C : requestTodayMedicationSummary(userHash, role)
activate C

alt [role == PATIENT]
  C -> C : resolvePatientHash(userHash)
else [role == GUARDIAN]
  C -> CareLink : getLinkedPatientHash(guardianHash)
  activate CareLink
  CareLink -> DB : findLinkedPatientHash(guardianHash)
  activate DB
  DB --> CareLink : linkedPatientLookupResult
  deactivate DB
  CareLink --> C : linkedPatientLookupResult
  deactivate CareLink

  break [linked patient is not found]
    C --> UI : showNoLinkedPatient()
    UI --> Guardian : displayNoLinkedPatient()
  end
end

C -> Schedule : getTodayMedicationSummary(patientHash)
activate Schedule
Schedule -> DB : findTodayMedicationSummary(patientHash)
activate DB
DB --> Schedule : todayMedicationSummaryData
deactivate DB
loop [for each medication and time slot]
  Schedule -> Schedule : calculateDoseSummary(medication, timeSlot)
end
Schedule --> C : todayMedicationSummary
deactivate Schedule
C --> UI : showMainTodaySchedule(todayMedicationSummary)
alt [role == PATIENT]
  UI --> Patient : displayMainTodaySchedule()
else [role == GUARDIAN]
  UI --> Guardian : displaySharedTodaySchedule()
end
deactivate C
deactivate UI

opt [user opens today's medication schedule]
  alt [opened by patient]
    Patient -> UI : clickTodayMedicationSchedule()
  else [opened by guardian]
    Guardian -> UI : clickTodayMedicationSchedule()
  end
  activate UI
  UI -> C : requestTodayMedicationSchedule(patientHash)
  activate C
  C -> Schedule : getTodayMedicationSchedule(patientHash)
  activate Schedule
  Schedule -> DB : findTodayMedicationSchedule(patientHash)
  activate DB
  DB --> Schedule : todayMedicationScheduleData
  deactivate DB
  loop [for each schedule item]
    Schedule -> Schedule : buildScheduleItemViewModel(scheduleItem)
  end
  Schedule --> C : todayMedicationSchedule
  deactivate Schedule
  C --> UI : showTodaySchedule(todayMedicationSchedule)
  alt [opened by patient]
    UI --> Patient : displayTodayMedicationSchedule()
  else [opened by guardian]
    UI --> Guardian : displaySharedTodayMedicationSchedule()
  end
  deactivate C
  deactivate UI
end

opt [user requests health recommendation]
  alt [requested by patient]
    Patient -> UI : clickHealthRecommendation()
  else [requested by guardian]
    Guardian -> UI : clickHealthRecommendation()
  end
  activate UI
  UI -> C : requestHealthRecommendation(patientHash)
  activate C
  C -> Schedule : getMedicationContext(patientHash)
  activate Schedule
  Schedule -> DB : findMedicationContext(patientHash)
  activate DB
  DB --> Schedule : medicationContextData
  deactivate DB
  Schedule --> C : medicationContext
  deactivate Schedule
  C -> LLM : generateHealthRecommendation(medicationContext)
  activate LLM
  LLM --> C : recommendationMessage
  deactivate LLM
  create Recommend
  C -> Recommend : <<create>> HealthRecommendation(recommendationMessage)
  activate Recommend
  Recommend --> C : healthRecommendation
  deactivate Recommend
  C --> UI : showHealthRecommendation(healthRecommendation)
  alt [requested by patient]
    UI --> Patient : displayHealthRecommendation()
  else [requested by guardian]
    UI --> Guardian : displayHealthRecommendation()
  end
  deactivate C
  deactivate UI
end

opt [user selects medicine detail]
  alt [selected by patient]
    Patient -> UI : clickMedicineName(medicineName)
  else [selected by guardian]
    Guardian -> UI : clickMedicineName(medicineName)
  end
  activate UI
  UI -> C : requestDrugInfo(medicineName)
  activate C
  C -> DrugAPI : searchDrugInfo(medicineName)
  activate DrugAPI
  DrugAPI --> C : drugInfo
  deactivate DrugAPI
  C --> UI : showDrugDetail(drugInfo)
  alt [selected by patient]
    UI --> Patient : displayDrugDetail()
  else [selected by guardian]
    UI --> Guardian : displayDrugDetail()
  end
  deactivate C
  deactivate UI
end

opt [patient requests read aloud]
  Patient -> UI : clickReadAloud(text)
  activate UI
  UI -> C : requestTTS(text)
  activate C
  C -> TTS : readDoseInstruction(text)
  activate TTS
  TTS --> C : ttsAudio
  deactivate TTS
  C --> UI : playTTSAudio(ttsAudio)
  UI --> Patient : hearDoseInstruction()
  deactivate C
  deactivate UI
end

opt [patient changes medication alarm]
  Patient -> UI : clickAlarmBell(timeSlot)
  activate UI
  UI -> C : requestAlarmToggle(patientHash, timeSlot)
  activate C
  C -> Alarm : getAlarmStatus(patientHash, timeSlot)
  activate Alarm
  Alarm -> DB : findAlarmSetting(patientHash, timeSlot)
  activate DB
  DB --> Alarm : alarmStatus
  deactivate DB
  Alarm --> C : alarmStatus
  deactivate Alarm

  critical update medication alarm state
    alt [alarm disabled or not found]
      C --> UI : showAlarmSettingPopup()
      Patient -> UI : submitAlarmTime(alarmTime)
      UI -> C : setMedicationAlarm(patientHash, timeSlot, alarmTime)
      C -> Alarm : upsertMedicationAlarm(patientHash, timeSlot, alarmTime)
      activate Alarm
      Alarm -> DB : saveAlarmSetting(patientHash, timeSlot, alarmTime)
      activate DB
      DB --> Alarm : savedAlarmSetting
      deactivate DB
      Alarm --> C : savedAlarmSetting
      deactivate Alarm
      C -> Notify : registerMedicationAlarm(savedAlarmSetting)
      activate Notify
      Notify --> C : alarmRegistered
      deactivate Notify
      C --> UI : displayEnabledAlarmBell()
    else [alarm enabled]
      C -> Alarm : disableAlarmSetting(patientHash, timeSlot)
      activate Alarm
      Alarm -> DB : updateAlarmEnabled(patientHash, timeSlot, false)
      activate DB
      DB --> Alarm : disabledAlarmSetting
      deactivate DB
      Alarm --> C : disabledAlarmSetting
      deactivate Alarm
      C -> Notify : cancelMedicationAlarm(disabledAlarmSetting)
      activate Notify
      Notify --> C : alarmCancelled
      deactivate Notify
      C --> UI : displayDisabledAlarmBell()
    end
  end

  deactivate C
  deactivate UI
end

opt [patient checks medication as taken]
  Patient -> UI : clickMedicationCheck(medicineName, timeSlot)
  activate UI
  UI -> C : completeMedication(patientHash, medicineName, timeSlot)
  activate C
  critical record completion and refresh progress
    create Complete
    C -> Complete : <<create>> MedicationCompletion(patientHash, medicineName, timeSlot)
    activate Complete
    Complete -> DB : insertMedicationCompletion(patientHash, medicineName, timeSlot)
    activate DB
    DB --> Complete : savedCompletion
    deactivate DB
    Complete --> C : completionStatus
    deactivate Complete
    C -> Schedule : updateMedicationProgress(patientHash)
    activate Schedule
    Schedule -> DB : findTodayMedicationProgress(patientHash)
    activate DB
    DB --> Schedule : todayMedicationProgressData
    deactivate DB
    Schedule --> C : updatedProgress
    deactivate Schedule
  end
  C --> UI : showUpdatedMedicationSchedule(updatedProgress)
  UI --> Patient : displayCheckedMedicineAndProgress()
  deactivate C
  deactivate UI
end
@enduml
```

## 5. 환자/보호자 연동 및 연동 해제

### 수정 논거

- 환자 코드 생성과 보호자 코드 등록은 시간 순서가 있는 하나의 연동 시나리오이므로 같은 다이어그램에 둔다.
- 코드 검증 성공/실패는 상호 배타적이므로 `alt [patientCode is valid] / [patientCode is invalid or expired]`로 표현했다.
- 연동 관계 생성과 삭제는 DB 상태 변경이므로 `critical`로 묶었다.
- 연동 생성 후 환자 화면과 보호자 화면의 갱신은 동일 커밋 이후 독립적으로 가능하므로 `par`로 표현했다.
- 연동 해제는 사용자가 선택할 때만 발생하므로 `opt`, 해제 확인/취소는 `alt`로 표현했다.

```plantuml
@startuml SD05_Patient_Guardian_Link
autonumber
actor "환자" as Patient
actor "보호자" as Guardian
boundary "PatientLinkUI_boundary" as PatientUI
boundary "GuardianLinkUI_boundary" as GuardianUI
control "PatientGuardianLink_control" as C
entity "PatientLinkCode_entity" as Code
entity "PatientGuardianLink_entity" as CareLink
database "LinkDB_database" as DB

Patient -> PatientUI : clickPatientGuardianLink()
activate PatientUI
PatientUI -> C : requestLinkPage(patientHash)
activate C
C -> CareLink : getLinkList(patientHash)
activate CareLink
CareLink -> DB : findLinkListByUserHash(patientHash)
activate DB
DB --> CareLink : linkList
deactivate DB
CareLink --> C : linkList
deactivate CareLink
C --> PatientUI : showLinkPage(linkList)
deactivate C
PatientUI --> Patient : displayLinkPage()
deactivate PatientUI

Patient -> PatientUI : clickCreatePatientCode()
activate PatientUI
PatientUI -> C : requestPatientCode(patientHash)
activate C
critical create temporary patient link code
  create Code
  C -> Code : <<create>> PatientLinkCode(patientHash)
  activate Code
  Code -> DB : savePatientCode(patientHash, patientCode, expiresAt)
  activate DB
  DB --> Code : savedPatientCode
  deactivate DB
  Code --> C : patientCode
  deactivate Code
end
C --> PatientUI : showPatientCode(patientCode, expiresAt)
deactivate C
PatientUI --> Patient : displayPatientCode()
deactivate PatientUI

Guardian -> GuardianUI : clickPatientGuardianLink()
activate GuardianUI
GuardianUI -> C : requestLinkPage(guardianHash)
activate C
C -> CareLink : getLinkList(guardianHash)
activate CareLink
CareLink -> DB : findLinkListByUserHash(guardianHash)
activate DB
DB --> CareLink : linkList
deactivate DB
CareLink --> C : linkList
deactivate CareLink
C --> GuardianUI : showLinkPage(linkList)
deactivate C
GuardianUI --> Guardian : displayLinkPage()
deactivate GuardianUI

Guardian -> GuardianUI : clickRegisterPatient()
activate GuardianUI
GuardianUI -> C : requestPatientRegistration()
activate C
C --> GuardianUI : showPatientCodeInputPopup()
GuardianUI --> Guardian : displayPatientCodeInputPopup()
Guardian -> GuardianUI : submitPatientCode(patientCode)
GuardianUI -> C : registerPatientCode(guardianHash, patientCode)
C -> Code : validatePatientCode(patientCode)
activate Code
Code -> DB : findValidPatientCode(patientCode)
activate DB
DB --> Code : patientCodeLookupResult
deactivate DB
Code --> C : patientCodeLookupResult
deactivate Code

alt [patientCode is valid]
  critical create patient guardian link
    C -> CareLink : createPatientGuardianLink(patientHash, guardianHash)
    activate CareLink
    CareLink -> DB : insertPatientGuardianLink(patientHash, guardianHash)
    activate DB
    DB --> CareLink : savedLinkInfo
    deactivate DB
    CareLink --> C : linkedInfo
    deactivate CareLink
  end

  par [update guardian link page]
    C --> GuardianUI : showLinkedInfo(linkedInfo)
    GuardianUI --> Guardian : displayLinkedInfo()
  else [update patient link page]
    activate PatientUI
    C --> PatientUI : showLinkedInfo(linkedInfo)
    PatientUI --> Patient : displayLinkedInfo()
    deactivate PatientUI
  end
else [patientCode is invalid or expired]
  C --> GuardianUI : showInvalidCodeMessage()
  GuardianUI --> Guardian : displayInvalidCodeMessage()
end
deactivate C
deactivate GuardianUI

opt [guardian requests unlink]
  Guardian -> GuardianUI : clickDeleteLink(selectedLinkId)
  activate GuardianUI
  GuardianUI -> C : requestDeleteLink(selectedLinkId)
  activate C
  C --> GuardianUI : showDeleteConfirmPopup()

  alt [confirm delete]
    Guardian -> GuardianUI : confirmDelete()
    GuardianUI -> C : deletePatientGuardianLink(selectedLinkId)
    critical delete patient guardian link
      C -> CareLink : deleteLink(selectedLinkId)
      activate CareLink
      CareLink -> DB : deletePatientGuardianLink(selectedLinkId)
      activate DB
      DB --> CareLink : deletedLinkInfo
      deactivate DB
      CareLink -> DB : findUpdatedLinkList(deletedLinkInfo)
      activate DB
      DB --> CareLink : updatedLinkList
      deactivate DB
      CareLink --> C : updatedLinkList
      deactivate CareLink
    end
    C --> GuardianUI : showUpdatedLinkInfo(updatedLinkList)
    GuardianUI --> Guardian : displayUpdatedLinkInfo()
  else [cancel delete]
    Guardian -> GuardianUI : cancelDelete()
    GuardianUI -> C : cancelDeleteLink()
    C --> GuardianUI : closeDeleteConfirmPopup()
    GuardianUI --> Guardian : displayLinkPage()
  end

  deactivate C
  deactivate GuardianUI
end
@enduml
```

## 6. 사용자 설정

### 수정 논거

- 사용자 설정이 없으면 기본 설정을 생성해야 하므로 `alt [setting exists] / [setting not found]`로 초기 조회 결과를 분리했다.
- 사용자는 설정 화면을 닫기 전까지 여러 항목을 반복 변경할 수 있으므로 `loop [while setting page is open]`를 사용했다.
- 한 번의 변경 이벤트에서 글씨 크기, 읽기 속도, 언어 변경은 동시에 발생하는 것이 아니라 상호 배타적 선택이므로 `alt`로 표현했다.
- 설정 저장은 사용자 경험에 즉시 반영되어야 하는 상태 변경이므로 각 변경을 `critical persist user setting`으로 묶었다.

```plantuml
@startuml SD06_User_Setting
autonumber
actor "환자 또는 보호자" as User
boundary "MainUI_boundary" as MainUI
boundary "UserSettingUI_boundary" as SettingUI
control "UserSetting_control" as C
entity "UserSetting_entity" as Setting
boundary "LocalSettingStorage_boundary" as Storage

User -> MainUI : clickSettingButton()
activate MainUI
MainUI -> C : requestUserSetting(userHash)
activate C
C -> Storage : findUserSetting(userHash)
activate Storage
Storage --> C : userSettingLookupResult
deactivate Storage

alt [setting exists]
  C -> Setting : loadUserSetting(userSettingLookupResult)
  activate Setting
  Setting --> C : userSetting
  deactivate Setting
else [setting not found]
  C -> Setting : initializeDefaultUserSetting(userHash)
  activate Setting
  Setting -> Storage : saveUserSetting(defaultValues)
  activate Storage
  Storage --> Setting : savedUserSetting
  deactivate Storage
  Setting --> C : userSetting
  deactivate Setting
end

C --> SettingUI : showUserSettingPage(userSetting)
activate SettingUI
deactivate C
deactivate MainUI
SettingUI --> User : displayUserSettingPage()

loop [while setting page is open and user changes settings]
  alt [font size selected]
    User -> SettingUI : selectFontSize(fontSize)
    SettingUI -> C : updateFontSize(fontSize)
    activate C
    critical persist user setting
      C -> Setting : changeFontSize(fontSize)
      activate Setting
      Setting -> Storage : saveFontSize(fontSize)
      activate Storage
      Storage --> Setting : savedFontSize
      deactivate Storage
      Setting --> C : updatedUserSetting
      deactivate Setting
    end
    C --> SettingUI : applyFontSize(updatedUserSetting)
    deactivate C
    SettingUI --> User : displayUpdatedFontSize()
  else [reading speed selected]
    User -> SettingUI : selectReadingSpeed(readingSpeed)
    SettingUI -> C : updateReadingSpeed(readingSpeed)
    activate C
    critical persist user setting
      C -> Setting : changeReadingSpeed(readingSpeed)
      activate Setting
      Setting -> Storage : saveReadingSpeed(readingSpeed)
      activate Storage
      Storage --> Setting : savedReadingSpeed
      deactivate Storage
      Setting --> C : updatedUserSetting
      deactivate Setting
    end
    C --> SettingUI : applyReadingSpeed(updatedUserSetting)
    deactivate C
    SettingUI --> User : displayUpdatedReadingSpeed()
  else [language selected]
    User -> SettingUI : selectLanguage(language)
    SettingUI -> C : updateLanguage(language)
    activate C
    critical persist user setting
      C -> Setting : changeLanguage(language)
      activate Setting
      Setting -> Storage : saveLanguage(language)
      activate Storage
      Storage --> Setting : savedLanguage
      deactivate Storage
      Setting --> C : updatedUserSetting
      deactivate Setting
    end
    C --> SettingUI : applyLanguage(updatedUserSetting)
    deactivate C
    SettingUI --> User : displayUpdatedLanguage()
  end
end

User -> SettingUI : closeSettingPage()
SettingUI -> C : finishUserSetting()
activate C
C --> MainUI : returnToMainScreen()
activate MainUI
deactivate C
MainUI --> User : displayMainScreen()
deactivate MainUI
deactivate SettingUI
@enduml
```
