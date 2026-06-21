# 파일명: check_saved_medication_control.py
# 역할: 저장 복약 정보 생성, 조회, 삭제 흐름을 조정한다.

from datetime import date
from fastapi import HTTPException
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from schemas.medication import SavedMedicationCreate

_GUARDIAN_ROLES = {"guardian", "caregiver"}


# 클래스명: CheckSavedMedication
# 역할: 저장 복약 정보 CRUD 유스케이스 흐름을 조정한다.
# 주요 책임:
#   - 선택한 약의 저장 snapshot을 생성한다.
#   - 요청 환자 또는 연동 보호자 권한 범위의 저장 복약 정보를 나열한다.
#   - 같은 날짜에 같은 약이 중복 저장되지 않도록 방지한다.
#   - 저장된 약 삭제 시 존재 여부를 확인한다.
# 속성:
#   - db: 저장 작업에 사용하는 SQLAlchemy 세션
class CheckSavedMedication:
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: save_medication_detail
    # 함수역할:
    # - 선택한 약을 저장 복약 정보 snapshot으로 저장한다.
    # - 같은 환자와 같은 날짜에 동일한 약 이름이 이미 있으면 새 row를 만들지 않는다.
    # 매개변수:
    # - medication: 검증된 저장 복약 정보 DTO
    # 반환값:
    # - API 호환 저장 결과 dictionary
    def save_medication_detail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        try:
            patient_hash = normalize_patient_hash(medication.patient_hash)
            duplicate_medication = self._find_today_duplicate(
                patient_hash,
                medication.item_name,
            )
            if duplicate_medication is not None:
                return {
                    "success": False,
                    "duplicate": True,
                    "message": "이미 추가된 약입니다.",
                    "id": duplicate_medication.id,
                }

            db_medication = _SavedMedication(
                patient_hash=patient_hash,
                item_name=medication.item_name.strip(),
                efficacy=medication.efficacy,
                use_method=medication.use_method,
                warning_message=medication.warning_message,
                dosage_per_time=medication.dosage_per_time,
                daily_frequency=medication.daily_frequency,
                total_days=medication.total_days,
                image_url=medication.image_url,
                ai_guide=medication.ai_guide,
            )
            self.db.add(db_medication)
            self.db.commit()
            self.db.refresh(db_medication)
            return {
                "success": True,
                "duplicate": False,
                "message": f"'{db_medication.item_name}' saved to pillbox.",
                "id": db_medication.id,
            }
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=f"Save failed: {exc}") from exc

    # 함수명: saveMedicationDetail
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 save_medication_detail wrapper이다.
    # 매개변수:
    # - medication: 검증된 저장 복약 정보 DTO
    # 반환값:
    # - API 호환 저장 결과 dictionary
    def saveMedicationDetail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        return self.save_medication_detail(medication)

    # 함수명: request_saved_medication_info
    # 함수역할:
    # - 환자 해시 또는 연동 보호자 권한 범위의 저장 복약 정보를 읽는다.
    # 매개변수:
    # - patient_hash: 저장 복약 정보 조회 범위를 구분하는 환자 해시
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # 반환값:
    # - API-compatible list response dictionary.
    def request_saved_medication_info(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        saved_medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_patient_hash)
            .all()
        )
        return {
            "success": True,
            "message": "Saved medication lookup succeeded.",
            "data": [
                self._to_response_dict(medication)
                for medication in saved_medications
            ],
        }

    # 함수명: requestSavedMedicationInfo
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 request_saved_medication_info wrapper이다.
    # 매개변수:
    # - patient_hash: 저장 복약 정보 조회 범위를 구분하는 환자 해시
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # 반환값:
    # - API-compatible list response dictionary.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_saved_medication_info(patient_hash, user_hash, role)

    # 함수명: request_delete
    # 함수역할:
    # - 저장된 복약 정보 하나를 id 기준으로 삭제한다.
    # 매개변수:
    # - medication_id: 저장 복약 정보 기본키
    # - patient_hash: 삭제 범위를 구분하는 환자 해시
    # 반환값:
    # - API-compatible success response dictionary.
    def request_delete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        try:
            medication = self._get_existing_medication(medication_id, patient_hash)
            self.db.delete(medication)
            self.db.commit()
            return {"success": True, "message": "Medication was deleted from pillbox."}
        except HTTPException:
            raise
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(status_code=500, detail=f"Delete failed: {exc}") from exc

    # 함수명: requestDelete
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 request_delete wrapper이다.
    # 매개변수:
    # - medication_id: 저장 복약 정보 기본키
    # - patient_hash: 삭제 범위를 구분하는 환자 해시
    # 반환값:
    # - API-compatible delete success dictionary.
    def requestDelete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_delete(medication_id, patient_hash)

    # 함수명: _to_response_dict
    # 함수역할:
    # - SavedMedication ORM 엔티티를 JSON 직렬화 가능한 API DTO로 변환한다.
    # 매개변수:
    # - medication: 저장 계층에서 읽은 SavedMedication 엔티티
    # 반환값:
    # - JSON-compatible saved medication dictionary.
    def _to_response_dict(self, medication: _SavedMedication) -> dict[str, object]:
        return {
            "id": medication.id,
            "patient_hash": medication.patient_hash,
            "created_date": (
                medication.created_date.isoformat()
                if medication.created_date
                else ""
            ),
            "item_name": medication.item_name,
            "efficacy": medication.efficacy,
            "use_method": medication.use_method,
            "warning_message": medication.warning_message,
            "dosage_per_time": medication.dosage_per_time,
            "daily_frequency": medication.daily_frequency,
            "total_days": medication.total_days,
            "image_url": medication.image_url,
            "ai_guide": medication.ai_guide,
        }

    # 함수명: resolvePatientHash
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 환자/보호자 권한 범위 확인 wrapper이다.
    # 매개변수:
    # - patient_hash: 환자 요청에서 직접 전달된 환자 해시
    # - user_hash: 보호자 요청에서 전달된 사용자 해시
    # - role: 요청 사용자 역할
    # 반환값:
    # - 이 요청에 대해 권한이 확인된 환자 해시
    def resolvePatientHash(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        return self._resolve_patient_hash(patient_hash, user_hash, role)

    def _resolve_patient_hash(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        normalized_role = (role or "patient").strip().lower()
        if normalized_role in _GUARDIAN_ROLES:
            return LinkPatientCaregiver(self.db).get_linked_patient_hash(
                user_hash or patient_hash
            )
        return normalize_patient_hash(user_hash or patient_hash)

    # 함수명: _get_existing_medication
    # 함수역할:
    # - 기존 저장 복약 정보를 찾고 없으면 404 오류를 발생시킨다.
    # 매개변수:
    # - medication_id: 저장 복약 정보 기본키
    # - patient_hash: 조회 범위를 구분하는 환자 해시
    # 반환값:
    # - 기존 _SavedMedication row
    def _get_existing_medication(
        self,
        medication_id: int,
        patient_hash: str,
    ) -> _SavedMedication:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        medication = (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.id == medication_id,
                _SavedMedication.patient_hash == normalized_patient_hash,
            )
            .first()
        )
        if medication is None:
            raise HTTPException(status_code=404, detail="Medication was not found.")
        return medication

    # 함수명: _find_today_duplicate
    # 함수역할:
    # - 같은 환자와 오늘 날짜에 이미 저장된 동일 약 이름이 있는지 확인한다.
    # - 공백 차이로 중복 방지가 실패하지 않도록 정규화된 이름끼리 비교한다.
    # 매개변수:
    # - patient_hash: 저장 범위를 구분하는 환자 해시
    # - item_name: 저장하려는 약품명
    # 반환값:
    # - 중복 row가 있으면 _SavedMedication
    # - 중복이 없으면 None
    def _find_today_duplicate(
        self,
        patient_hash: str,
        item_name: str,
    ) -> _SavedMedication | None:
        normalized_item_name = self._normalize_item_name(item_name)
        if not normalized_item_name:
            return None

        today_medications = (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.patient_hash == patient_hash,
                _SavedMedication.created_date == date.today(),
            )
            .all()
        )
        for medication in today_medications:
            if self._normalize_item_name(medication.item_name or "") == normalized_item_name:
                return medication
        return None

    # 함수명: _normalize_item_name
    # 함수역할:
    # - 중복 비교에 사용할 약품명을 공백 제거와 소문자 기준으로 정규화한다.
    # 매개변수:
    # - item_name: 원본 약품명
    # 반환값:
    # - 정규화된 약품명
    def _normalize_item_name(self, item_name: str) -> str:
        return " ".join(item_name.strip().lower().split())
