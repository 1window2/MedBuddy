# MedBuddy Communication Diagrams

---

## UC-1 처방전 이미지 입력 및 개인정보 보호 처리

```mermaid
sequenceDiagram
    actor 환자
    participant UI as PrescriptionInputUI_boundary
    participant Control as PrescriptionAnalysis_control
    participant OCR as OCRService_boundary
    participant PText as PrescriptionText_entity
    participant MedInfo as MedicationInfo_entity
    participant DrugPortal as PublicDrugDataPortal_boundary
    participant AnalysisResult as PrescriptionAnalysisResult_entity

    환자->>UI: 1: clickPrescriptionScan()
    UI->>Control: 2: startPrescriptionInput()
    Control-->>UI: 3: showCaptureScreen()
    UI-->>환자: 4: displayCaptureScreen()
    환자->>UI: 5: clickCapture()
    UI->>Control: 6: submitPrescriptionImage(image)
    Control-->>UI: 7: showAnalyzing()
    UI-->>환자: 8: displayAnalyzingScreen()
    Control->>OCR: 9: extractText(image)
    OCR-->>Control: 10: rawText
    Control->>PText: 11: removeSensitiveInfoByRegex(rawText)
    PText-->>Control: 12: medicationOnlyText
    Control->>MedInfo: 13: parseMedicationInfo(medicationOnlyText)
    MedInfo-->>Control: 14: medicationList
    Control->>AnalysisResult: 15: createAnalysisResult(medicationList)
    AnalysisResult->>DrugPortal: 16.1: searchDrugInfo(medicineName)
    DrugPortal-->>AnalysisResult: 16.2: drugInfo
    AnalysisResult->>AnalysisResult: 16.3: addDrugInfo(medicineName, drugInfo)
    AnalysisResult-->>Control: 17: completedAnalysisResult
    Control->>UI: 18: showAnalysisResult(completedAnalysisResult)
    UI-->>환자: 19: displayMedicationCards()

    Note over UI,Control: [Alternative Flow]<br/>A1: clickLoadImage()<br/>A2: submitPrescriptionImage(image)<br/>이후 9번부터 동일하게 진행
```

---

## UC-2 OCR 결과 분석 및 약 정보 조회

```mermaid
sequenceDiagram
    participant OCR as OCRService_boundary
    participant Control as PrescriptionAnalysis_control
    participant PText as PrescriptionText_entity
    participant MedInfo as MedicationInfo_entity
    participant DrugPortal as PublicDrugDataPortal_boundary
    participant AnalysisResult as PrescriptionAnalysisResult_entity

    OCR-->>Control: 1: rawText
    Control->>PText: 2: removeSensitiveInfoByRegex(rawText)
    PText-->>Control: 3: medicationOnlyText
    Control->>MedInfo: 4: parseMedicationInfo(medicationOnlyText)
    MedInfo-->>Control: 5: medicationList
    Control->>AnalysisResult: 6: createAnalysisResult(medicationList)
    AnalysisResult->>DrugPortal: 7.1: searchDrugInfo(medicineName)
    DrugPortal-->>AnalysisResult: 7.2: drugInfo
    AnalysisResult->>AnalysisResult: 7.3: addDrugInfo(medicineName, drugInfo)
    AnalysisResult-->>Control: 8: completedAnalysisResult
```

---

## UC-3 오늘의 복약 일정 확인

```mermaid
sequenceDiagram
    actor 환자
    actor 보호자
    participant UI as TodayMedicationUI_boundary
    participant Control as TodayMedication_control
    participant LinkEntity as PatientCaregiverLink_entity
    participant Schedule as MedicationSchedule_entity
    participant DB as MedicationDB_database

    환자->>UI: 1: loadMainScreen()
    UI->>Control: 2: requestTodayMedicationSchedule(patientHash, role)

    Note over Control,DB: [환자인 경우] 3a ~ 6a 경로
    Control->>Schedule: 3a: getTodayMedicationSummary(patientHash)
    Schedule->>DB: 4a: findTodayMedicationSummary(patientHash)
    DB-->>Schedule: 5a: todayMedicationData
    Schedule-->>Control: 6a: todayMedicationSummary(data)

    Note over Control,DB: [보호자인 경우] 3b ~ 10b 경로
    Control->>LinkEntity: 3b: getLinkedPatientHash(caregiverHash)
    LinkEntity->>DB: 4b: findLinkedPatientHash(caregiverHash)
    DB-->>LinkEntity: 5b: patientHash
    LinkEntity-->>Control: 6b: patientHash
    Control->>Schedule: 7b: getTodayMedicationSummary(patientHash)
    Schedule->>DB: 8b: findTodayMedicationSummary(patientHash)
    DB-->>Schedule: 9b: todayMedicationData
    Schedule-->>Control: 10b: todayMedicationSummary(data)

    Control->>UI: 11: displayTodayMedicationSchedule(schedule)
    UI-->>환자: 12: displayTodayMedicationSchedule()

    Note over UI,환자: [복약 정보 없음]<br/>A1: displayEmptyMedicationInfo()
```

---

## UC-4 저장된 복약 정보 조회

```mermaid
sequenceDiagram
    actor 환자
    actor 보호자
    participant UI as SavedMedicationUI_boundary
    participant Control as SavedMedication_control
    participant LinkEntity as PatientCaregiverLink_entity
    participant SavedMedInfo as SavedMedicationInfo_entity
    participant DB as MedicationDB_database

    환자->>UI: 1: clickSavedMedicationInfo()
    UI->>Control: 2: requestSavedMedicationInfoList(userHash, role)

    Note over Control,DB: [환자인 경우] 3a ~ 6a 경로
    Control->>SavedMedInfo: 3a: getSavedMedicationList(patientHash)
    SavedMedInfo->>DB: 4a: findSavedMedicationList(patientHash)
    DB-->>SavedMedInfo: 5a: savedMedicationList
    SavedMedInfo-->>Control: 6a: savedMedicationList

    Note over Control,DB: [보호자인 경우] 3b ~ 10b 경로
    Control->>LinkEntity: 3b: getLinkedPatientHash(caregiverHash)
    LinkEntity->>DB: 4b: findLinkedPatientHash(caregiverHash)
    DB-->>LinkEntity: 5b: patientHash
    LinkEntity-->>Control: 6b: patientHash
    Control->>SavedMedInfo: 7b: getSavedMedicationList(patientHash)
    SavedMedInfo->>DB: 8b: findSavedMedicationList(patientHash)
    DB-->>SavedMedInfo: 9b: savedMedicationList
    SavedMedInfo-->>Control: 10b: savedMedicationList

    Control->>UI: 11: showSavedMedicationInfo(savedMedicationList, isPatient)
    UI-->>환자: 12: displaySavedMedicationInfo()

    Note over UI,환자: [저장된 복약 정보 없음]<br/>A1: showEmptySavedMedicationInfo()<br/>A2: displayEmptySavedMedicationInfo()
```

---

## UC-5 복약 정보 수정/삭제

```mermaid
sequenceDiagram
    actor 환자
    participant UI as SavedMedicationUI_boundary
    participant Control as SavedMedication_control
    participant SavedMedInfo as SavedMedicationInfo_entity
    participant DB as MedicationDB_database

    환자->>UI: 1: clickDeleteSavedMedication()
    UI->>Control: 2: requestDeleteSavedMedication(savedMedicationId)
    Control-->>UI: 3: showDeleteConfirmPopup()
    UI-->>환자: 4: displayDeleteConfirmPopup()

    Note over 환자,DB: [예 선택] 5a ~ 12a 경로
    환자->>UI: 5a: confirmDelete()
    UI->>Control: 6a: deleteSavedMedication(patientHash, savedMedicationId)
    Control->>SavedMedInfo: 7a: deleteMedicationInfo(patientHash, savedMedicationId)
    SavedMedInfo->>DB: 8a: deleteSavedMedicationInfo(patientHash, savedMedicationId)
    DB-->>SavedMedInfo: 9a: deleteStatus
    SavedMedInfo-->>Control: 10a: updatedSavedMedicationList
    Control->>UI: 11a: showUpdatedSavedMedicationInfo(updatedSavedMedicationList)
    UI-->>환자: 12a: displayUpdatedSavedMedicationInfo()

    Note over 환자,UI: [아니오 선택] 5b ~ 8b 경로
    환자->>UI: 5b: cancelDelete()
    UI->>Control: 6b: cancelDeleteSavedMedication()
    Control-->>UI: 7b: closeDeleteConfirmPopup()
    UI-->>환자: 8b: displaySavedMedicationInfo()
```

---

## UC-6 환자/보호자 연동

```mermaid
sequenceDiagram
    actor 환자
    actor 보호자
    participant PatientUI as PatientLinkUI_boundary
    participant CaregiverUI as CaregiverLinkUI_boundary
    participant Control as PatientCaregiverLink_control
    participant LinkCode as PatientLinkCode_entity
    participant LinkEntity as PatientCaregiverLink_entity
    participant DB as LinkDB_database

    Note over 환자,DB: [환자 흐름]
    환자->>PatientUI: 1: clickPatientCaregiverLink()
    PatientUI->>Control: 2: requestLinkPage(patientHash)
    Control->>LinkEntity: 3: getLinkList(patientHash)
    LinkEntity->>DB: 4: findLinkListByUserHash(patientHash)
    DB-->>LinkEntity: 5: linkList
    LinkEntity-->>Control: 6: linkList
    Control->>PatientUI: 7: showLinkPage(linkList)
    PatientUI-->>환자: 8: displayLinkPage()
    환자->>PatientUI: 9: clickCreatePatientCode()
    PatientUI->>Control: 10: requestPatientCode(patientHash)
    Control->>LinkCode: 11: generatePatientCode(patientHash)
    LinkCode->>DB: 12: savePatientCode(patientHash, patientCode, expiresAt)
    DB-->>LinkCode: 13: savedPatientCode
    LinkCode-->>Control: 14: patientCode
    Control->>PatientUI: 15: showPatientCode(patientCode, expiresAt)
    PatientUI-->>환자: 16: displayPatientCode()
    환자->>환자: 17: sharePatientCode(patientCode)

    Note over 보호자,DB: [보호자 흐름]
    보호자->>CaregiverUI: 18: clickPatientCaregiverLink()
    CaregiverUI->>Control: 19: requestLinkPage(caregiverHash)
    Control->>LinkEntity: 20: getLinkList(caregiverHash)
    LinkEntity->>DB: 21: findLinkListByUserHash(caregiverHash)
    DB-->>LinkEntity: 22: linkList
    LinkEntity-->>Control: 23: linkList
    Control->>CaregiverUI: 24: showLinkPage(linkList)
    CaregiverUI-->>보호자: 25: displayLinkPage()
    보호자->>CaregiverUI: 26: clickRegisterPatient()
    CaregiverUI->>Control: 27: requestPatientRegistration()
    Control->>CaregiverUI: 28: showPatientCodeInputPopup()
    CaregiverUI-->>보호자: 29: displayPatientCodeInputPopup()
    보호자->>CaregiverUI: 30: submitPatientCode(patientCode)
    CaregiverUI->>Control: 31: registerPatientCode(caregiverHash, patientCode)
    Control->>LinkCode: 32: validatePatientCode(patientCode)
    LinkCode->>DB: 33: findValidPatientCode(patientCode)
    DB-->>LinkCode: 34: patientCodeInfo
    LinkCode-->>Control: 35: patientHash
    Control->>LinkEntity: 36: createPatientCaregiverLink(patientHash, caregiverHash)
    LinkEntity->>DB: 37: insertPatientCaregiverLink(patientHash, caregiverHash)
    DB-->>LinkEntity: 38: savedLinkInfo
    LinkEntity-->>Control: 39: linkedInfo
    Control->>PatientUI: 40: showLinkedInfo(linkedInfo)
    PatientUI-->>환자: 41: displayLinkedInfo()
    Control->>CaregiverUI: 42: showLinkedInfo(linkedInfo)
    CaregiverUI-->>보호자: 43: displayLinkedInfo()

    Note over CaregiverUI,Control: [코드 유효하지 않은 경우]<br/>A1: invalidPatientCode<br/>A2: showErrorMessage()<br/>A3: displayPatientCodeInputPopup()
```

---

## UC-7 환자/보호자 연동 해제

```mermaid
sequenceDiagram
    actor 환자
    actor 보호자
    participant PatientUI as PatientLinkUI_boundary
    participant CaregiverUI as CaregiverLinkUI_boundary
    participant Control as PatientCaregiverLink_control
    participant LinkEntity as PatientCaregiverLink_entity
    participant DB as LinkDB_database

    환자->>PatientUI: 1: clickDeleteLink(selectedLinkId)
    PatientUI->>Control: 2: requestDeleteLink(selectedLinkId)
    Control-->>PatientUI: 3: showDeleteConfirmPopup()
    PatientUI-->>환자: 4: displayDeleteConfirmPopup()

    Note over 환자,DB: [예 선택] 5a ~ 16a 경로
    환자->>PatientUI: 5a: confirmDelete()
    PatientUI->>Control: 6a: deletePatientCaregiverLink(selectedLinkId)
    Control->>LinkEntity: 7a: deleteLink(selectedLinkId)
    LinkEntity->>DB: 8a: deletePatientCaregiverLink(selectedLinkId)
    DB-->>LinkEntity: 9a: deletedLinkInfo
    LinkEntity->>DB: 10a: findUpdatedLinkList(deletedLinkInfo)
    DB-->>LinkEntity: 11a: updatedLinkList
    LinkEntity-->>Control: 12a: updatedLinkList
    Control->>PatientUI: 13a: showUpdatedLinkInfo(updatedLinkList)
    PatientUI-->>환자: 14a: displayUpdatedLinkInfo()
    Control->>CaregiverUI: 15a: showUpdatedLinkInfo(updatedLinkList)
    CaregiverUI-->>보호자: 16a: displayUpdatedLinkInfo()

    Note over 환자,PatientUI: [아니오 선택] 5b ~ 8b 경로
    환자->>PatientUI: 5b: cancelDelete()
    PatientUI->>Control: 6b: cancelDeleteLink()
    Control-->>PatientUI: 7b: closeDeleteConfirmPopup()
    PatientUI-->>환자: 8b: displayLinkPage()
```

---

## UC-8 복약 완료 체크

```mermaid
sequenceDiagram
    actor 환자
    participant UI as TodayMedicationUI_boundary
    participant Control as TodayMedication_control
    participant NotifCompletion as NotificationCompletion_entity
    participant Schedule as MedicationSchedule_entity
    participant LinkEntity as PatientCaregiverLink_entity
    participant NotifService as NotificationService_boundary
    participant DB as MedicationDB_database

    환자->>UI: 1: clickMedicationCheck(id)
    UI->>Control: 2: requestCompleteMedication(alarmId, medicineId)
    Control->>NotifCompletion: 3: saveNotificationCompletion(alarmId, medicineId, patientHash, completedTime)
    NotifCompletion->>DB: 4: insertNotificationCompletion(alarmId, medicineId, patientHash, completedTime)
    DB-->>NotifCompletion: 5: savedCompletion
    NotifCompletion-->>Control: 6: savedCompletion
    Control->>Schedule: 7: updateMedicationSchedule(alarmId, patientHash, true)
    Schedule->>DB: 8: updateMedicationScheduleData(alarmId, patientHash, true)
    DB-->>Schedule: 9: savedSchedule
    Schedule-->>Control: 10: savedSchedule
    Control->>UI: 11: displayTodayMedicationSchedule(schedule)
    UI-->>환자: 12: displayTodayMedicationSchedule()

    Note over Control,NotifService: [보호자 연동된 경우] 13 ~ 18 경로
    Control->>LinkEntity: 13: getCaregiverHash(patientHash)
    LinkEntity->>DB: 14: findCaregiverHash(patientHash)
    DB-->>LinkEntity: 15: caregiverHash
    LinkEntity-->>Control: 16: caregiverHash
    Control->>NotifService: 17: sendMedicationCompleteNotification(caregiverHash, medicineId, completedTime)
    NotifService-->>Control: 18: notified

    Note over 환자,UI: [체크 취소] A1 ~ A8 경로
    환자->>UI: A1: clickMedicationCheck(id)
    UI->>Control: A2: requestCancelMedication(alarmId, medicineId)
    Control->>Schedule: A3: updateMedicationSchedule(alarmId, patientHash, false)
    Schedule->>DB: A4: updateMedicationScheduleData(alarmId, patientHash, false)
    DB-->>Schedule: A5: savedSchedule
    Schedule-->>Control: A6: savedSchedule
    Control->>UI: A7: displayTodayMedicationSchedule(schedule)
    UI-->>환자: A8: displayTodayMedicationSchedule()
```

---

## UC-9 약 상세 정보 확인

```mermaid
sequenceDiagram
    actor 환자
    participant UI as TodayMedicationUI_boundary
    participant Control as TodayMedication_control
    participant MedInfo as MedicationInfo_entity
    participant DrugPortal as PublicDrugDataPortal_boundary
    participant DB as MedicationDB_database

    환자->>UI: 1: clickMedicineName(medicineName)
    UI->>Control: 2: requestDrugInfo(medicineName)
    Control->>MedInfo: 3: getDrugInfo(medicineName)
    MedInfo->>DrugPortal: 4: searchDrugInfo(medicineName)
    DrugPortal-->>MedInfo: 5: drugInfo
    MedInfo-->>Control: 6: drugInfo
    Control->>UI: 7: showDrugDetail(drugInfo)
    UI-->>환자: 8: displayDrugDetail()
```

---

## UC-10 건강 관리 추천 확인

```mermaid
sequenceDiagram
    actor 환자
    participant UI as TodayMedicationUI_boundary
    participant Control as TodayMedication_control
    participant Schedule as MedicationSchedule_entity
    participant HealthRec as HealthRecommendation_entity
    participant DB as MedicationDB_database

    환자->>UI: 1: clickHealthRecommendation()
    UI->>Control: 2: requestHealthRecommendation(patientHash, medicines)
    Control->>Schedule: 3: getTodayMedicationSummary(patientHash)
    Schedule->>DB: 4: findTodayMedicationSummary(patientHash)
    DB-->>Schedule: 5: todayMedicationData
    Schedule-->>Control: 6: todayMedicationData
    Control->>HealthRec: 7: generateHealthRecommendation(medicines, patientInfo)
    HealthRec-->>Control: 8: healthRecommendation
    Control->>UI: 9: showHealthRecommendation(healthRecommendation)
    UI-->>환자: 10: displayHealthRecommendation()

    Note over HealthRec,UI: [추천 정보 생성 실패 시]
    HealthRec-->>Control: A1: failGenerateRecommendation()
    Control->>UI: A2: showHealthRecommendationError()
    UI-->>환자: A3: displayHealthRecommendationError()
```

---

## UC-11 음성 안내 제공

```mermaid
sequenceDiagram
    actor 환자
    participant UI as TodayMedicationUI_boundary
    participant Control as TodayMedication_control
    participant MedInfo as MedicationInfo_entity
    participant TTS as TTSService_boundary

    환자->>UI: 1: clickTTS(id)
    UI->>Control: 2: requestTTSPlayback(summaryText, ttsOption)
    Control->>MedInfo: 3: getMedicationSummaryText(medicineId)
    MedInfo-->>Control: 4: summaryText
    Control->>TTS: 5: generateTTS(text, ttsOption)
    TTS-->>Control: 6: audioStream
    Control->>UI: 7: playTTS(audioStream)
    UI-->>환자: 8: playVoiceGuide()

    Note over TTS,UI: [음성 변환 실패 시]
    TTS-->>Control: A1: detectTTSFailure()
    Control->>UI: A2: showTTSError()
    UI-->>환자: A3: displayVoiceGuideError()
```

---

## UC-12 복약 알림 설정

```mermaid
sequenceDiagram
    actor 환자
    participant UI as TodayMedicationUI_boundary
    participant Control as TodayMedication_control
    participant AlarmInfo as AlarmInfo_entity
    participant Schedule as MedicationSchedule_entity
    participant DB as MedicationDB_database

    환자->>UI: 1: clickAlarmBell(alarmId)
    UI->>Control: 2: requestAlarmSetting(alarmId, patientHash)
    Control->>AlarmInfo: 3: getAlarmInfo(alarmId)
    AlarmInfo->>DB: 4: findAlarmInfo(alarmId)
    DB-->>AlarmInfo: 5: alarmInfo
    AlarmInfo-->>Control: 6: alarmInfo
    Control->>UI: 7: showAlarmSettingPopup(alarmInfo)
    UI-->>환자: 8: displayAlarmSettingPopup()
    환자->>UI: 9: selectAlarmTime(time)
    환자->>UI: 10: confirmAlarmSetting()
    UI->>Control: 11: saveAlarmInfo(alarmId, patientHash, time)
    Control->>AlarmInfo: 12: updateAlarmInfo(alarmId, patientHash, time)
    AlarmInfo->>DB: 13: saveAlarmData(alarmId, patientHash, time)
    DB-->>AlarmInfo: 14: savedAlarm
    AlarmInfo-->>Control: 15: savedAlarm
    Control->>Schedule: 16: updateMedicationSchedule(alarmId, patientHash, time)
    Schedule->>DB: 17: updateScheduleData(alarmId, patientHash, time)
    DB-->>Schedule: 18: savedSchedule
    Schedule-->>Control: 19: savedSchedule
    Control->>UI: 20: updateAlarmBell(isEnabled)
    UI-->>환자: 21: displayUpdatedAlarmBell()

    Note over 환자,UI: [설정 취소 시]
    환자->>UI: A1: cancelAlarmSetting()
    UI-->>환자: A2: closeAlarmSettingPopup()
```

---

## UC-13 보호자 알림 수신

```mermaid
sequenceDiagram
    actor 보호자
    participant UI as SavedMedicationUI_boundary
    participant Control as SavedMedication_control
    participant AlertSetting as CaregiverAlertSetting_entity
    participant DB as MedicationDB_database
    participant NotifService as NotificationService_boundary

    보호자->>UI: 1: clickCaregiverAlarmBell(patientHash)
    UI->>Control: 2: requestCaregiverAlertSetting(caregiverHash, patientHash)
    Control->>AlertSetting: 3: getCaregiverAlertSetting(caregiverHash, patientHash)
    AlertSetting->>DB: 4: findCaregiverAlertSetting(caregiverHash, patientHash)
    DB-->>AlertSetting: 5: caregiverAlertSetting
    AlertSetting-->>Control: 6: caregiverAlertSetting
    Control->>UI: 7: showCaregiverAlertSettingPopup(caregiverAlertSetting)
    UI-->>보호자: 8: displayCaregiverAlertSettingPopup()
    보호자->>UI: 9: selectCaregiverAlertOption(alertOption)
    UI->>Control: 10: updateCaregiverAlertSetting(caregiverHash, patientHash, alertOption)

    Note over Control,NotifService: [알림 켜기] 11a ~ 19a 경로
    Control->>AlertSetting: 11a: enableCaregiverAlert(caregiverHash, patientHash)
    AlertSetting->>DB: 12a: updateCaregiverAlertEnabled(caregiverHash, patientHash, true)
    DB-->>AlertSetting: 13a: enabledAlertSetting
    AlertSetting->>NotifService: 14a: enableAlertSetting
    NotifService->>DB: 15a: registerCaregiverAlert(enabledAlertSetting)
    DB-->>NotifService: 16a: caregiverAlertRegistered
    NotifService-->>Control: 17a: updateCaregiverAlarmBell(isEnabled)
    Control->>UI: 18a: updateCaregiverAlarmBell(isEnabled)
    UI-->>보호자: 19a: displayEnabledCaregiverAlarmBell()

    Note over Control,NotifService: [알림 끄기] 11b ~ 19b 경로
    Control->>AlertSetting: 11b: disableCaregiverAlert(caregiverHash, patientHash)
    AlertSetting->>DB: 12b: updateCaregiverAlertDisabled(caregiverHash, patientHash, false)
    DB-->>AlertSetting: 13b: disabledAlertSetting
    AlertSetting->>NotifService: 14b: disableAlertSetting
    NotifService->>DB: 15b: unregisterCaregiverAlert(disabledAlertSetting)
    DB-->>NotifService: 16b: caregiverAlertCancelled
    NotifService-->>Control: 17b: updateCaregiverAlarmBell(isDisabled)
    Control->>UI: 18b: updateCaregiverAlarmBell(isDisabled)
    UI-->>보호자: 19b: displayDisabledCaregiverAlarmBell()
```

---

## UC-14 사용자 설정

```mermaid
sequenceDiagram
    actor User as 환자 또는 보호자
    participant MainUI as MainUI_boundary
    participant SettingUI as UserSettingUI_boundary
    participant Control as UserSetting_control
    participant SettingEntity as UserSetting_entity
    participant Storage as LocalSettingStorage

    User->>MainUI: 1: clickSettingButton()
    MainUI->>Control: 2: requestUserSetting()
    Control->>SettingEntity: 3: getUserSetting()
    SettingEntity->>Storage: 4: findUserSetting()
    Storage-->>SettingEntity: 5: userSetting
    SettingEntity-->>Control: 6: userSetting
    Control->>SettingUI: 7: showUserSettingPage(userSetting)
    SettingUI-->>User: 8: displayUserSettingPage()

    Note over User,Storage: [글씨 크기 변경] 9.x 경로
    User->>SettingUI: 9.1: selectFontSize(fontSize)
    SettingUI->>Control: 9.2: updateFontSize(fontSize)
    Control->>SettingEntity: 9.3: changeFontSize(fontSize)
    SettingEntity->>Storage: 9.4: saveFontSize(fontSize)
    Storage-->>SettingEntity: 9.5: savedFontSize
    SettingEntity-->>Control: 9.6: updatedUserSetting
    Control->>SettingUI: 9.7: applyFontSize(updatedUserSetting)
    SettingUI-->>User: 9.8: displayUpdatedFontSize()

    Note over User,Storage: [읽기 속도 변경] 10.x 경로
    User->>SettingUI: 10.1: selectReadingSpeed(readingSpeed)
    SettingUI->>Control: 10.2: updateReadingSpeed(readingSpeed)
    Control->>SettingEntity: 10.3: changeReadingSpeed(readingSpeed)
    SettingEntity->>Storage: 10.4: saveReadingSpeed(readingSpeed)
    Storage-->>SettingEntity: 10.5: savedReadingSpeed
    SettingEntity-->>Control: 10.6: updatedUserSetting
    Control->>SettingUI: 10.7: applyReadingSpeed(updatedUserSetting)
    SettingUI-->>User: 10.8: displayUpdatedReadingSpeed()

    Note over User,Storage: [언어 변경] 11.x 경로
    User->>SettingUI: 11.1: selectLanguage(language)
    SettingUI->>Control: 11.2: updateLanguage(language)
    Control->>SettingEntity: 11.3: changeLanguage(language)
    SettingEntity->>Storage: 11.4: saveLanguage(language)
    Storage-->>SettingEntity: 11.5: savedLanguage
    SettingEntity-->>Control: 11.6: updatedUserSetting
    Control->>SettingUI: 11.7: applyLanguage(updatedUserSetting)
    SettingUI-->>User: 11.8: displayUpdatedLanguage()

    User->>SettingUI: 12: closeSettingPage()
    SettingUI->>Control: 13: finishUserSetting()
    Control->>MainUI: 14: returnToMainScreen()
    MainUI-->>User: 15: displayMainScreen()
```
