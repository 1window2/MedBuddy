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

    # Function Name: saveMedicationDetail
    # Description:
    # - Persists a selected medication as a saved medication snapshot.
    # Parameters:
    # - medication (SavedMedicationCreate): Validated saved medication DTO.
    # Returns:
    # - API-compatible success response dictionary.
    def saveMedicationDetail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        try:
            patient_hash = normalize_patient_hash(medication.patient_hash)
            self.retention_policy.cleanup_expired_medications(self.db, patient_hash)
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
            ) == "as_needed":
                duplicate_medication = self.medication_repository.find_daily_duplicate(
                    patient_hash=patient_hash, registration_date=registration_date,
                    deduplication_key=self._build_deduplication_key(medication, include_dosing_mode=False),
                )
            if duplicate_medication is not None:
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

    # Function Name: requestDelete
    # Description:
    # - Deletes a saved medication by id.
    # Parameters:
    # - medication_id (int): Saved medication primary key.
    # - patient_hash (str): Patient ownership key used to scope deletion.
    # Returns:
    # - API-compatible success response dictionary.
    def requestDelete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        try:
            medication = self._get_existing_medication(medication_id, patient_hash)
            self._delete_medication_completions(medication)
            self.db.delete(medication)
            self.db.commit()
            return {"success": True, "message": "Medication was deleted from pillbox."}
        except HTTPException:
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

    # Function Name: _to_response_dict
    # Description:
    # - Converts a SavedMedication ORM entity into a JSON-serializable API DTO.
    # Parameters:
    # - medication (_SavedMedication): SavedMedication entity from persistence layer.
    # Returns:
    # - JSON-compatible saved medication dictionary.
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
        medication = self.medication_repository.find_owned_by_id(
            medication_id,
            normalized_patient_hash,
        )
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

    # Function Name: _build_deduplication_key
    # Description:
    # - Uses confirmed slots, or frequency-derived slots when absent, to build the shared prescription snapshot fingerprint.
    # Parameters:
    # - medication (SavedMedicationCreate): Validated medication snapshot and course fields selected for saving.
    # Returns:
    # - Stable deduplication hash for the medication and its course fields.
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
