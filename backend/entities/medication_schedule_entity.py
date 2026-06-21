# 파일명: medication_schedule_entity.py
# 역할: ClassDiagram2의 MedicationSchedule 박스에 대응하는 엔티티 클래스이다.

from datetime import date

from pydantic import AliasChoices, BaseModel, ConfigDict, Field


# 클래스명: MedicationSchedule
# 역할: 저장된 복약 일정 또는 OCR에서 추출한 약 후보 하나를 표현한다.
# 주요 책임:
#   - 클래스 다이어그램에서 정의한 복약 일정 필드를 보관한다.
#   - UML과 코드의 추적성을 유지하는 메서드 이름을 제공한다.
# 속성:
#   - masked_prescription_text: 마스킹된 처방전 텍스트
#   - created_date: 복약 일정이 생성된 날짜
#   - medication_id: 약 식별자
#   - medication_name: 약품명
#   - dosage: 1회 복용량
#   - intake_time: 1일 복용 횟수 또는 복용 시간 라벨
#   - medcation_status: 복약 완료 상태. 오탈자는 기존 다이어그램 명칭을 따른다.
#   - patient_id: 환자 식별자
#   - medication_time: 총 복용 일수 또는 복용 시간 수
class MedicationSchedule(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    masked_prescription_text: str = Field(
        default="",
        validation_alias=AliasChoices("maskedPrescriptionText", "masked_prescription_text"),
        serialization_alias="maskedPrescriptionText",
    )
    created_date: date | None = Field(
        default=None,
        validation_alias=AliasChoices("createdDate", "created_date"),
        serialization_alias="createdDate",
    )
    medication_id: str = Field(
        default="",
        validation_alias=AliasChoices("medicationID", "medication_id"),
        serialization_alias="medicationID",
    )
    medication_name: str = Field(
        default="",
        validation_alias=AliasChoices("medicationName", "medication_name", "drug_name"),
        serialization_alias="drug_name",
    )
    dosage: str = Field(
        default="",
        validation_alias=AliasChoices("dosage", "dosage_per_time"),
        serialization_alias="dosage_per_time",
    )
    intake_time: str = Field(
        default="",
        validation_alias=AliasChoices("intakeTime", "intake_time", "daily_frequency"),
        serialization_alias="daily_frequency",
    )
    medcation_status: bool = Field(
        default=False,
        validation_alias=AliasChoices(
            "medcationStatus",
            "medcation_status",
            "medicationStatus",
            "medication_status",
        ),
        serialization_alias="medication_status",
    )
    patient_id: str = Field(
        default="",
        validation_alias=AliasChoices("patientID", "patient_id"),
        serialization_alias="patientID",
    )
    medication_time: str = Field(
        default="",
        validation_alias=AliasChoices("medicationTime", "medication_time", "total_days"),
        serialization_alias="total_days",
    )

    # 함수명: saveAnalysisResult
    # 함수역할:
    # - 분석 결과 저장을 위한 placeholder이다. 현재 저장 흐름은
    #   CheckSavedMedication을 통해 선택된 약 상세 정보를 저장한다.
    # 반환값:
    # - None.
    def saveAnalysisResult(self) -> None:
        raise NotImplementedError("Analysis result persistence is not implemented yet.")

    # 함수명: getTodayMedicationInfo
    # 함수역할:
    # - 오늘의 복약 요약 조회를 위한 placeholder이다.
    # 반환값:
    # - None.
    def getTodayMedicationInfo(self) -> None:
        raise NotImplementedError("Today's medication info is not implemented yet.")

    # 함수명: getAnalysisResult
    # 함수역할:
    # - 현재 구현된 분석 흐름에서 추출된 일정을 그대로 반환한다.
    # 반환값:
    # - 현재 MedicationSchedule 인스턴스
    def getAnalysisResult(self) -> "MedicationSchedule":
        return self

    # 함수명: getSavedMedicationInfo
    # 함수역할:
    # - 이 엔티티를 통한 저장 복약 조회를 위한 placeholder이다.
    # 반환값:
    # - None.
    def getSavedMedicationInfo(self) -> None:
        raise NotImplementedError("Saved medication info is handled by CheckSavedMedication.")

    # 함수명: updateMedicationInfo
    # 함수역할:
    # - 복약 일정 수정을 위한 placeholder이다.
    # 반환값:
    # - None.
    def updateMedicationInfo(self) -> None:
        raise NotImplementedError("Medication schedule editing is not implemented yet.")

    # 함수명: getTodayMedicationSchedule
    # 함수역할:
    # - 현재 인스턴스를 오늘 복약 일정 DTO로 반환한다.
    # 반환값:
    # - 현재 MedicationSchedule 인스턴스
    def getTodayMedicationSchedule(self) -> "MedicationSchedule":
        return self

    # 함수명: saveMedicationStatus
    # 함수역할:
    # - 이 복약 일정 DTO에 완료 상태를 적용한다.
    # 매개변수:
    # - medication_status: 새 복약 완료 상태
    # 반환값:
    # - 복약 상태가 변경된 MedicationSchedule 인스턴스
    def saveMedicationStatus(
        self,
        medication_status: bool | None = None,
    ) -> "MedicationSchedule":
        if medication_status is not None:
            self.medcation_status = medication_status
        return self
