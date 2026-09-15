# 파일명: saved_medication_retention.py
# 역할: 오래된 저장 복약 정보를 자동 정리하는 보존 정책을 정의한다.

from datetime import date

from sqlalchemy.orm import Session

from core.application_clock import application_today
from core.config import settings
from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication
from repositories.saved_medication_repository import SavedMedicationRepository
from services.medication_course_policy import MedicationCoursePolicy


# 클래스명: SavedMedicationRetentionPolicy
# 역할:
# - 복용 종료 후 일정 기간이 지난 저장 복약 정보를 삭제한다.
# 주요 책임:
# - 조제일자와 총 투약일로 복용 종료일을 계산한다.
# - 설정된 종료 후 보관 기간을 넘긴 약과 해당 완료 기록을 삭제하되, 기간이 0이면 자동 삭제하지 않는다.
# - 복용 기간을 확인할 수 없는 데이터는 보존한다.
# 속성:
# - course_policy (MedicationCoursePolicy): 복용 기간 계산 정책.
# - retention_days_after_end (int): 종료 후 보관 일수; 0이면 자동 삭제 비활성화.
class SavedMedicationRetentionPolicy:
    # Function Name: __init__
    # Description:
    # - Bind the medication-course policy and resolve post-course retention days, clamping negative values to zero.
    # Parameters:
    # - course_policy (MedicationCoursePolicy | None): Optional shared medication date/duration policy.
    # - retention_days_after_end (int | None): Days to keep ended courses; None reads settings, and zero preserves history.
    # Returns:
    # - None; zero retention disables automatic deletion.
    def __init__(
        self,
        course_policy: MedicationCoursePolicy | None = None,
        retention_days_after_end: int | None = None,
    ) -> None:
        self.course_policy = course_policy or MedicationCoursePolicy()
        configured_days = (
            settings.SAVED_MEDICATION_RETENTION_DAYS_AFTER_END
            if retention_days_after_end is None
            else retention_days_after_end
        )
        self.retention_days_after_end = max(0, configured_days)

    # 함수이름: cleanup_expired_medications
    # 함수역할:
    # - 환자 범위 또는 전체 저장 약에서 보존 기한이 지난 약과 해당 완료 기록을 함께 삭제한다.
    # 매개변수:
    # - db (Session): 저장 복약 정보 조회와 삭제에 사용할 세션
    # - patient_hash (str | None): 삭제 범위를 제한할 환자 해시; None이면 모든 환자를 대상으로 한다.
    # - today (date | None): 테스트 또는 실행 시점 기준일
    # - commit (bool): 호출자 트랜잭션에 맡기지 않고 여기서 삭제를 커밋할지 여부.
    # 반환값:
    # - 삭제된 row 개수
    def cleanup_expired_medications(
        self,
        db: Session,
        patient_hash: str | None = None,
        today: date | None = None,
        *,
        commit: bool = True,
    ) -> int:
        reference_date = today or application_today()
        repository = SavedMedicationRepository(db)
        medications = (
            repository.list_by_patient(patient_hash)
            if patient_hash is not None
            else repository.list_all()
        )
        expired_medications = [
            medication
            for medication in medications
            if self.is_expired(medication, reference_date)
        ]

        for medication in expired_medications:
            db.query(_MedicationCompletion).filter(
                _MedicationCompletion.saved_medication_id == medication.id,
            ).delete(synchronize_session=False)
            db.delete(medication)

        if expired_medications and commit:
            db.commit()
        return len(expired_medications)

    # Function Name: is_expired
    # Description:
    # - Preserve history when automatic cleanup is disabled; otherwise evaluate the configured post-course retention cutoff.
    # Parameters:
    # - medication (_SavedMedication): Saved medication row containing start-date and total-day fields.
    # - today (date): Application-local reference date for the retention decision.
    # Returns:
    # - True on or after the configured deletion date; False for disabled cleanup or unknown course duration.
    def is_expired(self, medication: _SavedMedication, today: date) -> bool:
        if self.retention_days_after_end == 0:
            return False
        return self.course_policy.is_expired_after(
            medication,
            today,
            self.retention_days_after_end,
        )
