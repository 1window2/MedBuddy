# 파일명: saved_medication_repository.py
# 역할: 저장 복약정보의 환자별 소유 범위, 정렬과 당일 중복 조회를 제공한다.
"""저장 복약정보 조회 규칙을 한곳에 모으는 저장소."""

from datetime import date

from sqlalchemy.orm import Session

from entities.saved_medication_entity import _SavedMedication


# 클래스명: SavedMedicationRepository
# 역할:
# - 저장 약의 반복 조회 조건과 정렬 규칙을 캡슐화한다.
# 주요 책임:
# - 환자 범위를 제한하고 전체 정리, 처방 비교와 당일 중복 검사에 필요한 조회를 구분한다.
# 속성:
# - db (Session): 호출자가 관리하는 저장 약 조회 세션.
class SavedMedicationRepository:
    """저장 복약정보의 반복 조회 조건과 정렬 규칙을 관리한다."""

    # 함수이름: __init__
    # 함수역할:
    # - 저장 약 조회에 재사용할 호출자의 SQLAlchemy 세션을 보관한다.
    # 매개변수:
    # - db (Session): 영속 기록에 접근할 호출자의 SQLAlchemy 세션.
    # 반환값:
    # - 없음; 새 세션을 열거나 커밋하지 않는다.
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수이름: list_by_patient
    # 함수역할:
    # - 환자가 소유한 저장 약을 ID 오름차순으로 조회한다.
    # 매개변수:
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # 반환값:
    # - 해당 환자의 저장 약 목록.
    def list_by_patient(self, patient_hash: str) -> list[_SavedMedication]:
        """환자 소유 복약정보를 저장 순서대로 반환한다."""
        return (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )

    # 함수이름: list_all
    # 함수역할:
    # - 전체 환자의 저장 약을 ID 순서로 조회하여 전역 보존 정책 처리를 지원한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 환자 제한 없이 조회한 저장 약 목록.
    def list_all(self) -> list[_SavedMedication]:
        """전체 환자의 복약정보를 저장 순서대로 반환한다."""
        return self.db.query(_SavedMedication).order_by(_SavedMedication.id.asc()).all()

    # 함수이름: list_recent_by_patient
    # 함수역할:
    # - 처방 변화 비교를 위해 환자의 약을 처방일, 등록일, ID 내림차순으로 조회한다.
    # 매개변수:
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # 반환값:
    # - 최신 처방부터 정렬된 저장 약 목록.
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

    # 함수이름: find_owned_by_id
    # 함수역할:
    # - 약 ID와 환자 소유권을 함께 확인하여 저장 약 한 건을 조회한다.
    # 매개변수:
    # - medication_id (int): 저장된 약 기록 ID.
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # 반환값:
    # - 환자 범위에 속한 저장 약 또는 None.
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

    # 함수이름: find_daily_duplicate
    # 함수역할:
    # - 같은 환자의 같은 등록일에 동일 처방 중복 방지 키가 저장됐는지 조회한다.
    # 매개변수:
    # - patient_hash (str): 저장 기록의 소유 범위를 제한할 환자 해시.
    # - registration_date (date): 중복 여부를 비교할 서비스 기준 등록 날짜.
    # - deduplication_key (str): 정규화한 처방 내용에서 계산한 중복 방지 서명.
    # 반환값:
    # - 기존 중복 저장 약 또는 None.
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
