# 파일명: medication_schedule_entity.py
# 역할: ClassDiagram2의 MedicationSchedule 박스에 대응하는 엔티티 클래스이다.

from datetime import date

from pydantic import AliasChoices, BaseModel, ConfigDict, Field


# 클래스명: MedicationSchedule
# 역할: one medication schedule or one extracted medication candidate을 표현한다.
# 주요 책임:
#   - Carry medication schedule fields defined in the class diagram.
#   - Provide operation names that preserve UML-to-code traceability.
# 속성:
#   - masked_prescription_text: Masked prescription text.
#   - created_date: Date when the medication schedule was created.
#   - medication_id: 약 식별자
#   - medication_name: 약품명
#   - dosage: Dose per administration.
#   - intake_time: Intake frequency or time label.
#   - medcation_status: 복약 완료 상태. 오탈자는 기존 다이어그램 명칭을 따른다.
#   - patient_id: 환자 식별자
#   - medication_time: Total medication duration or time count.
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
    # - 분석 결과 저장을 위한 placeholder이다. 현재 구현은
    #   selected medication details through CheckSavedMedication instead.
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
    # - Applies a completion status to this schedule DTO.
    # 매개변수:
    # - medication_status: New completion status.
    # 반환값:
    # - 복약 상태가 변경된 MedicationSchedule 인스턴스
    def saveMedicationStatus(
        self,
        medication_status: bool | None = None,
    ) -> "MedicationSchedule":
        if medication_status is not None:
            self.medcation_status = medication_status
        return self
