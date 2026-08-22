"""저장 복약정보 조회 규칙을 한곳에 모으는 저장소."""

from datetime import date

from sqlalchemy.orm import Session

from entities.saved_medication_entity import _SavedMedication


class SavedMedicationRepository:
    """저장 복약정보의 반복 조회 조건과 정렬 규칙을 관리한다."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def list_by_patient(self, patient_hash: str) -> list[_SavedMedication]:
        """환자 소유 복약정보를 저장 순서대로 반환한다."""
        return (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )

    def list_all(self) -> list[_SavedMedication]:
        """전체 환자의 복약정보를 저장 순서대로 반환한다."""
        return self.db.query(_SavedMedication).order_by(_SavedMedication.id.asc()).all()

    def list_recent_by_patient(self, patient_hash: str) -> list[_SavedMedication]:
        """처방 변화 비교에 사용할 복약정보를 최신 처방 순으로 반환한다."""
        return (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(
                _SavedMedication.prescription_date.desc(),
                _SavedMedication.created_date.desc(),
                _SavedMedication.id.desc(),
            )
            .all()
        )

    def find_owned_by_id(
        self,
        medication_id: int,
        patient_hash: str,
    ) -> _SavedMedication | None:
        """환자 범위 안에서 식별자가 일치하는 복약정보를 반환한다."""
        return (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.id == medication_id,
                _SavedMedication.patient_hash == patient_hash,
            )
            .first()
        )

    def find_daily_duplicate(
        self,
        *,
        patient_hash: str,
        registration_date: date,
        deduplication_key: str,
    ) -> _SavedMedication | None:
        """같은 환자와 등록일에 동일 처방 서명이 저장됐는지 확인한다."""
        return (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.patient_hash == patient_hash,
                _SavedMedication.created_date == registration_date,
                _SavedMedication.deduplication_key == deduplication_key,
            )
            .first()
        )
