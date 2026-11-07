# File Name: check_saved_medication_control.py
# Role: Persists and retrieves patient-owned medication snapshots with deduplication and retention rules.

import logging

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from core.application_clock import application_today
from core.config import settings
from entities.medication_completion_entity import _MedicationCompletion
from entities.medication_image_url_entity import safe_medication_image_url
from entities.medication_schedule_entity import (
    decode_medication_schedule_slot_keys,
    encode_medication_schedule_slot_keys,
    medication_schedule_slot_keys_for_frequency,
)
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import (
    _SavedMedication,
    build_saved_medication_deduplication_key,
)
from schemas.medication import SavedMedicationCreate
from repositories.saved_medication_repository import SavedMedicationRepository
from services.medication_course_policy import MedicationCoursePolicy
from services.medication_dosing_mode import medication_dosing_mode, resolve_dosing_mode
from services.medication_care_receipts import redact_medication_care_receipts
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)

SAVED_MEDICATION_LIMIT_DETAIL = (
    "저장할 수 있는 약의 수를 넘었습니다. 복약함에서 쓰지 않는 약을 지운 뒤 다시 시도해주세요."
)


# Class Name: CheckSavedMedication
# Role:
# - Coordinates saved medication CRUD use cases.
# Responsibilities:
# - Save medication snapshots.
# - List saved medications for one patient-owned scope.
# - Delete saved medications with not-found handling.
# Attributes:
# - db (Session): SQLAlchemy session used for persistence operations.
class CheckSavedMedication:
    # 함수이름: __init__
    # 함수역할:
    # - 저장 약 저장소와 복용 기간·보관 만료 정책을 같은 세션에 연결한다.
    # 매개변수:
    # - db (Session): 현재 작업에 사용할 SQLAlchemy 세션.
    # - course_policy (MedicationCoursePolicy | None): 약 복용 시작·종료·활성 날짜의 공통 판정 정책.
    # - medication_repository (SavedMedicationRepository | None): 환자 소유 저장 약품 스냅샷 저장소.
    # 반환값:
    # - 없음.
    def __init__(
        self,
        db: Session,
        course_policy: MedicationCoursePolicy | None = None,
        medication_repository: SavedMedicationRepository | None = None,
    ) -> None:
        self.db = db
        self.medication_repository = (
            medication_repository or SavedMedicationRepository(db)
        )
        self.course_policy = course_policy or MedicationCoursePolicy()
        self.retention_policy = SavedMedicationRetentionPolicy(self.course_policy)

    # 함수이름: saveMedicationDetail
    # 함수역할: 만료 정리와 약품 저장을 같은 트랜잭션에서 처리하고 당일 중복·계정별 수 제한을 검사한다. 실패하면 롤백하며 일반 저장 오류는 HTTP 500으로 바꾼다.
    # 매개변수: medication (SavedMedicationCreate)은 소유 환자와 약품·일정 정보이다.
    # 반환값: dict[str, object]. 신규 저장 성공 또는 기존 중복 약품 ID를 반환하고 계정 한도 초과는 HTTP 409로 알린다.
    def saveMedicationDetail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        try:
            patient_hash = normalize_patient_hash(medication.patient_hash)
            # 계정 잠금은 최종 저장까지 유지하고 정리 실패도 저장과 함께 롤백한다.
            self.retention_policy.cleanup_expired_medications(self.db, patient_hash, commit=False)
            self.db.flush()
            registration_date = application_today()
            deduplication_key = self._build_deduplication_key(medication)
            duplicate_medication = self.medication_repository.find_daily_duplicate(
                patient_hash=patient_hash,
                registration_date=registration_date,
                deduplication_key=deduplication_key,
            )
            # 이전 앱이 필요시 지시를 정기 모드로 저장한 경우에도 기존 중복 서명을 확인한다.
            if duplicate_medication is None and resolve_dosing_mode(
                None, medication.daily_frequency, medication.dosage_per_time,
                has_slots=bool(medication.schedule_slot_keys),
            ) == "as_needed":
                duplicate_medication = self.medication_repository.find_daily_duplicate(
                    patient_hash=patient_hash, registration_date=registration_date,
                    deduplication_key=self._build_deduplication_key(medication, include_dosing_mode=False),
                )
            if duplicate_medication is not None:
                self.db.commit()
                return {
                    "success": False,
                    "duplicate": True,
                    "message": "이미 추가된 약입니다.",
                    "id": duplicate_medication.id,
                }
            # 한 계정의 저장 약 수를 제한해 목록·일정 응답과 추천 프롬프트가 끝없이 커지지 않게 한다.
            if (
                self.medication_repository.count_by_patient(patient_hash)
                >= settings.SAVED_MEDICATION_MAX_PER_ACCOUNT
            ):
                raise HTTPException(
                    status_code=409,
                    detail=SAVED_MEDICATION_LIMIT_DETAIL,
                )

            db_medication = _SavedMedication(
                patient_hash=patient_hash,
                created_date=registration_date,
                prescription_date=medication.prescription_date,
                prescription_batch_id=medication.prescription_batch_id,
                item_seq=(medication.item_seq or "").strip() or None,
                item_name=medication.item_name.strip(),
                efficacy=medication.efficacy,
                use_method=medication.use_method,
                warning_message=medication.warning_message,
                interaction=medication.interaction,
                side_effect=medication.side_effect,
                storage_method=medication.storage_method,
                dosage_per_time=medication.dosage_per_time,
                daily_frequency=medication.daily_frequency,
                total_days=medication.total_days,
                dosing_mode=medication_dosing_mode(medication),
                schedule_slot_keys=encode_medication_schedule_slot_keys(
                    medication.schedule_slot_keys
                ),
                deduplication_key=deduplication_key,
                image_url=medication.image_url,
                ai_guide=medication.ai_guide,
            )
            self.db.add(db_medication)
            try:
                self.db.commit()
            except IntegrityError:
                self.db.rollback()
                duplicate_medication = self.medication_repository.find_daily_duplicate(
                    patient_hash=patient_hash,
                    registration_date=registration_date,
                    deduplication_key=deduplication_key,
                )
                if duplicate_medication is None:
                    raise
                return {
                    "success": False,
                    "duplicate": True,
                    "message": "이미 추가된 약입니다.",
                    "id": duplicate_medication.id,
                }
            self.db.refresh(db_medication)
            return {
                "success": True,
                "duplicate": False,
                "message": f"'{db_medication.item_name}' saved to pillbox.",
                "id": db_medication.id,
            }
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Saved medication persistence failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication could not be saved.",
            ) from exc

    # Function Name: requestSavedMedicationInfo
    # Description:
    # - Reads saved medications for one patient scope.
    # Parameters:
    # - patient_hash (str | None): Patient ownership key used to scope saved medication lookup.
    # Returns:
    # - API-compatible list response dictionary.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        saved_medications = self._load_saved_medications(normalized_patient_hash)
        return self._build_list_response(saved_medications)

    # 함수이름: _load_saved_medications
    # 함수역할:
    # - 환자 소유 저장 약 중 보관 기간이 만료되지 않은 항목만 조회한다.
    # 매개변수:
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # 반환값:
    # - 보관 대상인 저장 약 행 목록.
    def _load_saved_medications(
        self,
        patient_hash: str,
    ) -> list[_SavedMedication]:
        medications = self.medication_repository.list_by_patient(patient_hash)
        today = application_today()
        return [
            medication
            for medication in medications
            if not self.retention_policy.is_expired(medication, today)
        ]

    # Function Name: _build_list_response
    # Description:
    # - Serializes saved snapshots through the shared medication response adapter.
    # Parameters:
    # - saved_medications (list[_SavedMedication]): Patient-owned medication snapshots selected for serialization.
    # Returns:
    # - Success envelope with the serialized pillbox list.
    def _build_list_response(
        self,
        saved_medications: list[_SavedMedication],
    ) -> dict[str, object]:
        return {
            "success": True,
            "message": "Saved medication lookup succeeded.",
            "data": [
                self._to_response_dict(
                    medication,
                )
                for medication in saved_medications
            ],
        }

    # 함수이름: requestDelete
    # 함수역할: 환자 소유 약품을 확인한 후 돌봄 영수증의 상세를 비식별화하고 완료 기록과 약품을 함께 삭제한다. 실패하면 롤백한다.
    # 매개변수: medication_id (int)는 삭제 대상, patient_hash (str)는 소유 환자 범위이다.
    # 반환값: dict[str, object] 성공 응답. 조회 오류는 유지하고 일반 삭제 오류는 HTTP 500으로 전달한다.
    def requestDelete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        try:
            medication = self._get_existing_medication(medication_id, patient_hash)
            redact_medication_care_receipts(self.db, medication.patient_hash, medication.id)
            self._delete_medication_completions(medication)
            self.db.delete(medication)
            self.db.commit()
            return {"success": True, "message": "Medication was deleted from pillbox."}
        except HTTPException:
            self.db.rollback()
            raise
        except Exception as exc:
            self.db.rollback()
            logger.error(
                "Saved medication deletion failed: %s",
                type(exc).__name__,
            )
            raise HTTPException(
                status_code=500,
                detail="Medication could not be deleted.",
            ) from exc

    # 함수이름: _to_response_dict
    # 함수역할: 저장 약품을 날짜 문자열, 복용 모드·변경 이력, 해석된 시간대 및 안전한 이미지 주소를 포함한 응답으로 변환한다.
    # 매개변수: medication (_SavedMedication)은 응답에 담을 저장 행이다.
    # 반환값: dict[str, object]. 선택적 필드는 계약에 따라 빈 문자열 또는 None으로 보존한다.
    def _to_response_dict(
        self,
        medication: _SavedMedication,
    ) -> dict[str, object]:
        return {
            "id": medication.id,
            "patient_hash": medication.patient_hash,
            "created_date": (
                medication.created_date.isoformat()
                if medication.created_date
                else ""
            ),
            "prescription_date": (
                medication.prescription_date.isoformat()
                if medication.prescription_date
                else ""
            ),
            "prescription_batch_id": medication.prescription_batch_id or "",
            "item_seq": medication.item_seq or "",
            "item_name": medication.item_name,
            "efficacy": medication.efficacy,
            "use_method": medication.use_method,
            "warning_message": medication.warning_message,
            "interaction": medication.interaction or "",
            "side_effect": medication.side_effect or "",
            "storage_method": medication.storage_method or "",
            "dosage_per_time": medication.dosage_per_time,
            "daily_frequency": medication.daily_frequency,
            "total_days": medication.total_days,
            "dosing_mode": medication_dosing_mode(medication),
            "regimen_revision": medication.regimen_revision or 0,
            "regimen_effective_from": medication.regimen_effective_from.isoformat() if medication.regimen_effective_from else None,
            "stopped_on": medication.stopped_on.isoformat() if medication.stopped_on else None,
            "superseded_by_id": medication.superseded_by_id,
            "schedule_slot_keys": decode_medication_schedule_slot_keys(
                medication.schedule_slot_keys
            ),
            "image_url": safe_medication_image_url(medication.image_url),
            "ai_guide": medication.ai_guide,
        }

    # 함수이름: _get_existing_medication
    # 함수역할:
    # - 약 식별자와 환자 소유 범위를 함께 확인한다.
    # 매개변수:
    # - medication_id (int): 선택할 저장 약의 식별자.
    # - patient_hash (str): 작업 대상 환자의 데이터 소유 범위 식별자.
    # 반환값:
    # - 환자 소유 저장 약; 존재하지 않으면 HTTP 404.
    def _get_existing_medication(
        self,
        medication_id: int,
        patient_hash: str,
    ) -> _SavedMedication:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        medication = self.db.query(_SavedMedication).filter(
            _SavedMedication.id == medication_id,
            _SavedMedication.patient_hash == normalized_patient_hash,
        ).with_for_update().populate_existing().first()
        if medication is None:
            raise HTTPException(status_code=404, detail="Medication was not found.")
        return medication

    # Function Name: _delete_medication_completions
    # Description:
    # - Removes per-slot completion rows owned by a saved medication.
    # Parameters:
    # - medication (_SavedMedication): Saved medication row being deleted.
    # Returns:
    # - None.
    def _delete_medication_completions(self, medication: _SavedMedication) -> None:
        self.db.query(_MedicationCompletion).filter(
            _MedicationCompletion.saved_medication_id == medication.id,
            _MedicationCompletion.patient_hash
            == normalize_patient_hash(
                medication.patient_hash or DEFAULT_PATIENT_HASH
            ),
        ).delete(synchronize_session=False)

    # 함수이름: _build_deduplication_key
    # 함수역할: 명시 시간대 또는 복용 횟수에서 정한 시간대로 처방·복약 중복 서명을 만든다.
    # 매개변수: medication (SavedMedicationCreate)은 저장 입력, include_dosing_mode (bool)는 실제 복용 모드를 포함할지 여부이며 False는 이전 정기 복용 서명을 재현한다.
    # 반환값: str 중복 판정 키.
    def _build_deduplication_key(
        self,
        medication: SavedMedicationCreate,
        *,
        include_dosing_mode: bool = True,
    ) -> str:
        normalized_slot_keys = decode_medication_schedule_slot_keys(
            encode_medication_schedule_slot_keys(medication.schedule_slot_keys)
        )
        if not normalized_slot_keys:
            normalized_slot_keys = medication_schedule_slot_keys_for_frequency(
                self.course_policy.read_frequency_count(medication.daily_frequency)
            )
        return build_saved_medication_deduplication_key(
            item_name=medication.item_name,
            prescription_date=medication.prescription_date,
            prescription_batch_id=medication.prescription_batch_id,
            dosage_per_time=medication.dosage_per_time,
            daily_frequency=medication.daily_frequency,
            total_days=medication.total_days,
            schedule_slot_keys=normalized_slot_keys,
            dosing_mode=medication_dosing_mode(medication) if include_dosing_mode else "scheduled",
        )
