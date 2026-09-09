# 파일명: patient_caregiver_link_repository.py
# 역할: 환자·보호자 연동을 소유 범위와 활성 상태에 따라 조회한다.
"""환자·보호자 연결 조회 규칙을 한곳에 모으는 저장소."""

from sqlalchemy import or_
from sqlalchemy.orm import Session

from entities.patient_caregiver_link_entity import _PatientCaregiverLink


# 클래스명: PatientCaregiverLinkRepository
# 역할:
# - 환자·보호자 관계의 반복 조회 조건을 저장소에 모은다.
# 주요 책임:
# - 참여자별 소유 범위를 유지하고 활성 관계 조회와 계정 내보내기용 전체 관계 조회를 구분한다.
# 속성:
# - db (Session): 호출자가 관리하는 관계 조회 세션.
class PatientCaregiverLinkRepository:
    """활성 연결의 소유 범위와 반복 조회 조건을 관리한다."""

    # 함수이름: __init__
    # 함수역할:
    # - 연동 관계 조회에 사용할 SQLAlchemy 세션을 보관한다.
    # 매개변수:
    # - db (Session): 영속 기록에 접근할 호출자의 SQLAlchemy 세션.
    # 반환값:
    # - 없음; 쿼리는 아직 실행하지 않는다.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: list_active_for_user
    # 함수역할:
    # - 사용자가 환자 또는 보호자로 참여한 활성 관계를 ID 오름차순으로 조회한다.
    # 매개변수:
    # - user_hash (str): 접근 범위를 제한할 참여자 소유권 해시.
    # 반환값:
    # - 사용자와 연관된 활성 연동 목록.
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

    # 함수이름: list_for_user
    # 함수역할:
    # - 계정 내보내기에 필요한 사용자의 활성·비활성 관계를 ID 순서로 모두 조회한다.
    # 매개변수:
    # - user_hash (str): 접근 범위를 제한할 참여자 소유권 해시.
    # 반환값:
    # - 환자 또는 보호자로 참여한 모든 연동 목록.
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

    # 함수이름: list_active_for_patient
    # 함수역할:
    # - 지정 환자에게 연결된 활성 보호자 관계를 ID 순서로 조회한다.
    # 매개변수:
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # 반환값:
    # - 환자가 소유한 활성 연동 목록.
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

    # 함수이름: list_active_for_caregiver
    # 함수역할:
    # - 지정 보호자가 관리하는 활성 환자 관계를 ID 순서로 조회한다.
    # 매개변수:
    # - caregiver_hash (str): 연결된 환자를 조회할 보호자 해시.
    # 반환값:
    # - 보호자의 활성 환자 연동 목록.
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

    # 함수이름: find_active_for_user_by_id
    # 함수역할:
    # - 연동 ID와 참여자 해시를 함께 확인하여 사용자 범위의 활성 관계를 조회한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - user_hash (str): 접근 범위를 제한할 참여자 소유권 해시.
    # 반환값:
    # - 소유 범위에 속한 활성 연동 또는 None.
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

    # 함수이름: find_pair
    # 함수역할:
    # - 활성 여부를 제한하지 않고 환자와 보호자 해시 쌍이 일치하는 관계를 찾는다.
    # 매개변수:
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # - caregiver_hash (str): 연결된 환자를 조회할 보호자 해시.
    # 반환값:
    # - 일치하는 연동 또는 None.
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

    # 함수이름: find_active_for_caregiver
    # 함수역할:
    # - 보호자의 활성 관계 중 선택 환자 조건을 적용하고 가장 작은 ID의 관계를 고른다.
    # 매개변수:
    # - caregiver_hash (str): 연결된 환자를 조회할 보호자 해시.
    # - patient_hash (str | None): 조회할 환자 해시; 없거나 비어 있으면 보호자의 전체 환자 범위.
    # 반환값:
    # - 조건에 맞는 첫 활성 연동 또는 None.
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

    # 함수이름: find_active_for_caregiver_by_id
    # 함수역할:
    # - 보호자 소유권, 연동 ID와 활성 상태를 함께 확인하여 별칭 변경 대상을 조회한다.
    # 매개변수:
    # - link_id (int): 환자와 보호자 간 연동 ID.
    # - caregiver_hash (str): 연결된 환자를 조회할 보호자 해시.
    # 반환값:
    # - 해당 보호자의 활성 연동 또는 None.
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

    # 함수이름: has_active_pair
    # 함수역할:
    # - 환자·보호자 해시 쌍에 활성 연동이 존재하는지 ID 조회만으로 확인한다.
    # 매개변수:
    # - caregiver_hash (str): 연결된 환자를 조회할 보호자 해시.
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # 반환값:
    # - 해당 환자에 접근할 수 있는 활성 관계가 있으면 True.
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
