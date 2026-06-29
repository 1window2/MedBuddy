# 파일명: saved_medication_retention.py
# 역할: 오래된 저장 복약 정보를 자동 정리하는 보존 정책을 정의한다.

from datetime import date, timedelta
import re

from sqlalchemy.orm import Session

from entities.medication_completion_entity import _MedicationCompletion
from entities.saved_medication_entity import _SavedMedication

_TOTAL_DAYS_PATTERN = re.compile(r"\d+")
_RETENTION_DAYS_AFTER_END = 30


# 클래스명: SavedMedicationRetentionPolicy
# 역할: 복용 종료 후 일정 기간이 지난 저장 복약 정보를 삭제한다.
# 주요 책임:
#   - 조제일자와 총 투약일을 기준으로 복용 종료일을 계산한다.
#   - 복용 종료 후 30일 이상 지난 저장 복약 정보를 로컬 DB에서 삭제한다.
#   - 복용 기간을 확인할 수 없는 데이터는 안전하게 보존한다.
class SavedMedicationRetentionPolicy:
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
        total_days = self._read_total_days(medication.total_days)
        if total_days <= 0:
            return False

        start_date = self._read_start_date(medication, today)
        end_date = start_date + timedelta(days=total_days - 1)
        delete_after_date = end_date + timedelta(days=_RETENTION_DAYS_AFTER_END)
        return today >= delete_after_date

    # 함수명: _read_start_date
    # 함수역할:
    # - 조제일자를 우선 사용하고 없으면 등록일자를 복용 시작일로 읽는다.
    # 매개변수:
    # - medication: 저장 복약 정보 row
    # - fallback_date: 날짜를 읽을 수 없을 때 사용할 기준일
    # 반환값:
    # - 복용 시작일
    def _read_start_date(self, medication: _SavedMedication, fallback_date: date) -> date:
        raw_date = medication.prescription_date or medication.created_date
        if isinstance(raw_date, date):
            return raw_date
        if isinstance(raw_date, str) and raw_date.strip():
            try:
                return date.fromisoformat(raw_date.strip())
            except ValueError:
                return fallback_date
        return fallback_date

    # 함수명: _read_total_days
    # 함수역할:
    # - 총 투약일 문자열에서 숫자를 추출한다.
    # 매개변수:
    # - raw_total_days: "7일" 같은 총 투약일 원본 문자열
    # 반환값:
    # - 추출한 투약일 수, 없으면 0
    def _read_total_days(self, raw_total_days: str | None) -> int:
        if not raw_total_days:
            return 0
        match = _TOTAL_DAYS_PATTERN.search(raw_total_days)
        if match is None:
            return 0
        return int(match.group(0))
