# 파일명: saved_medication_retention.py
# 역할: 오래된 저장 복약 정보를 자동 정리하는 보존 정책을 정의한다.

from datetime import date

from sqlalchemy.orm import Session

from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication
from services.medication_course_policy import MedicationCoursePolicy

_RETENTION_DAYS_AFTER_END = 30


# 클래스명: SavedMedicationRetentionPolicy
# 역할: 복용 종료 후 일정 기간이 지난 저장 복약 정보를 삭제한다.
# 주요 책임:
#   - 조제일자와 총 투약일을 기준으로 복용 종료일을 계산한다.
#   - 복용 종료 후 30일 이상 지난 저장 복약 정보를 로컬 DB에서 삭제한다.
#   - 복용 기간을 확인할 수 없는 데이터는 안전하게 보존한다.
class SavedMedicationRetentionPolicy:
    def __init__(
        self,
        course_policy: MedicationCoursePolicy | None = None,
    ) -> None:
        self.course_policy = course_policy or MedicationCoursePolicy()

    # 함수명: cleanup_expired_medications
    # 함수역할:
    # - 특정 환자의 만료된 저장 복약 정보를 삭제한다.
    # 매개변수:
    # - db: 저장 복약 정보 조회와 삭제에 사용할 세션
    # - patient_hash: 삭제 범위를 제한할 환자 해시
    # - today: 테스트 또는 실행 시점 기준일
    # 반환값:
    # - 삭제된 row 개수
    def cleanup_expired_medications(
        self,
        db: Session,
        patient_hash: str,
        today: date | None = None,
    ) -> int:
        reference_date = today or date.today()
        medications = (
            db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .all()
        )
        expired_medications = [
            medication
            for medication in medications
            if self.is_expired(medication, reference_date)
        ]

        for medication in expired_medications:
            db.query(_MedicationCompletion).filter(
                _MedicationCompletion.saved_medication_id == medication.id,
                _MedicationCompletion.patient_hash == patient_hash,
            ).delete(synchronize_session=False)
            db.delete(medication)

        if expired_medications:
            db.commit()
        return len(expired_medications)

    # 함수명: is_expired
    # 함수역할:
    # - 저장 복약 정보가 자동 삭제 기준을 넘었는지 확인한다.
    # 매개변수:
    # - medication: 저장 복약 정보 row
    # - today: 판정 기준일
    # 반환값:
    # - 복용 종료 후 30일 이상 지났으면 True
    def is_expired(self, medication: _SavedMedication, today: date) -> bool:
        return self.course_policy.is_expired_after(
            medication,
            today,
            _RETENTION_DAYS_AFTER_END,
        )
