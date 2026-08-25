"""환자·보호자 연결 조회 규칙을 한곳에 모으는 저장소."""

from sqlalchemy import or_
from sqlalchemy.orm import Session

from entities.patient_caregiver_link_entity import _PatientCaregiverLink


class PatientCaregiverLinkRepository:
    """활성 연결의 소유 범위와 반복 조회 조건을 관리한다."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def list_active_for_user(self, user_hash: str) -> list[_PatientCaregiverLink]:
        """사용자가 환자 또는 보호자로 참여한 활성 연결을 반환한다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.linked.is_(True),
                or_(
                    _PatientCaregiverLink.patient_hash == user_hash,
                    _PatientCaregiverLink.caregiver_hash == user_hash,
                ),
            )
            .order_by(_PatientCaregiverLink.id.asc())
            .all()
        )

    def list_for_user(self, user_hash: str) -> list[_PatientCaregiverLink]:
        """계정 내보내기에 필요한 활성·비활성 연결을 모두 반환한다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                or_(
                    _PatientCaregiverLink.patient_hash == user_hash,
                    _PatientCaregiverLink.caregiver_hash == user_hash,
                )
            )
            .order_by(_PatientCaregiverLink.id.asc())
            .all()
        )

    def list_active_for_patient(
        self,
        patient_hash: str,
    ) -> list[_PatientCaregiverLink]:
        """환자에게 연결된 모든 활성 보호자 관계를 반환한다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.patient_hash == patient_hash,
                _PatientCaregiverLink.linked.is_(True),
            )
            .order_by(_PatientCaregiverLink.id.asc())
            .all()
        )

    def list_active_for_caregiver(
        self,
        caregiver_hash: str,
    ) -> list[_PatientCaregiverLink]:
        """보호자가 관리하는 모든 활성 환자 연결을 반환한다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.caregiver_hash == caregiver_hash,
                _PatientCaregiverLink.linked.is_(True),
            )
            .order_by(_PatientCaregiverLink.id.asc())
            .all()
        )

    def find_active_for_user_by_id(
        self,
        link_id: int,
        user_hash: str,
    ) -> _PatientCaregiverLink | None:
        """사용자 소유 범위에서 활성 연결 하나를 찾는다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.id == link_id,
                _PatientCaregiverLink.linked.is_(True),
                or_(
                    _PatientCaregiverLink.patient_hash == user_hash,
                    _PatientCaregiverLink.caregiver_hash == user_hash,
                ),
            )
            .first()
        )

    def find_pair(
        self,
        patient_hash: str,
        caregiver_hash: str,
    ) -> _PatientCaregiverLink | None:
        """활성 여부와 관계없이 환자·보호자 쌍을 찾는다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.patient_hash == patient_hash,
                _PatientCaregiverLink.caregiver_hash == caregiver_hash,
            )
            .first()
        )

    def find_active_for_caregiver(
        self,
        caregiver_hash: str,
        patient_hash: str | None = None,
    ) -> _PatientCaregiverLink | None:
        """보호자의 활성 연결을 선택 환자 범위에서 조회한다."""
        query = self.db.query(_PatientCaregiverLink).filter(
            _PatientCaregiverLink.caregiver_hash == caregiver_hash,
            _PatientCaregiverLink.linked.is_(True),
        )
        if patient_hash:
            query = query.filter(_PatientCaregiverLink.patient_hash == patient_hash)
        return query.order_by(_PatientCaregiverLink.id.asc()).first()

    def find_active_for_caregiver_by_id(
        self,
        link_id: int,
        caregiver_hash: str,
    ) -> _PatientCaregiverLink | None:
        """보호자 소유 범위에서 별칭을 변경할 활성 연결 하나를 찾는다."""
        return (
            self.db.query(_PatientCaregiverLink)
            .filter(
                _PatientCaregiverLink.id == link_id,
                _PatientCaregiverLink.caregiver_hash == caregiver_hash,
                _PatientCaregiverLink.linked.is_(True),
            )
            .first()
        )

    def has_active_pair(self, caregiver_hash: str, patient_hash: str) -> bool:
        """보호자가 해당 환자에게 접근 가능한지 확인한다."""
        return (
            self.db.query(_PatientCaregiverLink.id)
            .filter(
                _PatientCaregiverLink.caregiver_hash == caregiver_hash,
                _PatientCaregiverLink.patient_hash == patient_hash,
                _PatientCaregiverLink.linked.is_(True),
            )
            .first()
            is not None
        )
