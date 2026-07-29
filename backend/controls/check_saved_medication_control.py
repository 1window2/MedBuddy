# File Name: check_saved_medication_control.py
# Role: Control class for saved medication persistence workflows.

import asyncio
import logging
from datetime import date
from typing import Protocol

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from core.application_clock import application_today
from entities.medication_completion_entity import _MedicationCompletion
from entities.medication_detail_entity import _DrugApprovalInfo, _DrugBasicInfo
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
from services.medication_course_policy import MedicationCoursePolicy
from services.saved_medication_retention import SavedMedicationRetentionPolicy

logger = logging.getLogger(__name__)


class _MedicationImageLookup(Protocol):
    async def searchMedicationImage(
        self,
        item_name: str,
        item_seq: str = "",
    ) -> str: ...


# Class Name: CheckSavedMedication
# Role: Coordinates saved medication CRUD use cases.
# Responsibilities:
#   - Save medication snapshots.
#   - List saved medications for one patient-owned scope.
#   - Delete saved medications with not-found handling.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class CheckSavedMedication:
    _MAX_IMAGE_ENRICHMENTS_PER_REQUEST = 4
    _IMAGE_ENRICHMENT_CONCURRENCY = 2

    def __init__(
        self,
        db: Session,
        course_policy: MedicationCoursePolicy | None = None,
        medication_image_lookup: _MedicationImageLookup | None = None,
    ) -> None:
        self.db = db
        self.course_policy = course_policy or MedicationCoursePolicy()
        self.retention_policy = SavedMedicationRetentionPolicy(self.course_policy)
        self.medication_image_lookup = medication_image_lookup

    # Function Name: saveMedicationDetail
    # Description:
    # - Persists a selected medication as a saved medication snapshot.
    # Parameters:
    # - medication: Validated saved medication DTO.
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
            duplicate_medication = self._find_today_duplicate(
                patient_hash,
                registration_date,
                deduplication_key,
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
                created_date=registration_date,
                prescription_date=medication.prescription_date,
                item_seq=(medication.item_seq or "").strip() or None,
                item_name=medication.item_name.strip(),
                efficacy=medication.efficacy,
                use_method=medication.use_method,
                warning_message=medication.warning_message,
                dosage_per_time=medication.dosage_per_time,
                daily_frequency=medication.daily_frequency,
                total_days=medication.total_days,
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
                duplicate_medication = self._find_today_duplicate(
                    patient_hash,
                    registration_date,
                    deduplication_key,
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
    # - patient_hash: Patient ownership key used to scope saved medication lookup.
    # Returns:
    # - API-compatible list response dictionary.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        saved_medications = self._load_saved_medications(normalized_patient_hash)
        return self._build_list_response(saved_medications)

    # Function Name: requestSavedMedicationInfoWithImages
    # Description:
    # - HTTP-boundary extension that enriches missing image metadata without
    #   changing the synchronous UML control contract.
    async def requestSavedMedicationInfoWithImages(
        self,
        patient_hash: str | None = None,
    ) -> dict[str, object]:
        normalized_patient_hash = normalize_patient_hash(patient_hash)
        saved_medications = self._load_saved_medications(normalized_patient_hash)
        enrichment = await self._enrich_missing_medication_images(
            saved_medications
        )
        return self._build_list_response(saved_medications, enrichment)

    def _load_saved_medications(
        self,
        patient_hash: str,
    ) -> list[_SavedMedication]:
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        today = application_today()
        return [
            medication
            for medication in medications
            if not self.retention_policy.is_expired(medication, today)
        ]

    def _build_list_response(
        self,
        saved_medications: list[_SavedMedication],
        enrichment: dict[int, tuple[str, str]] | None = None,
    ) -> dict[str, object]:
        enrichment = enrichment or {}
        return {
            "success": True,
            "message": "Saved medication lookup succeeded.",
            "data": [
                self._to_response_dict(
                    medication,
                    item_seq_override=enrichment.get(medication.id, ("", ""))[0],
                    image_url_override=enrichment.get(medication.id, ("", ""))[1],
                )
                for medication in saved_medications
            ],
        }

    async def _enrich_missing_medication_images(
        self,
        saved_medications: list[_SavedMedication],
    ) -> dict[int, tuple[str, str]]:
        if self.medication_image_lookup is None:
            return {}

        candidates = [
            medication
            for medication in saved_medications
            if not (medication.image_url or "").strip()
        ][: self._MAX_IMAGE_ENRICHMENTS_PER_REQUEST]
        if not candidates:
            return {}

        semaphore = asyncio.Semaphore(self._IMAGE_ENRICHMENT_CONCURRENCY)
        resolved_item_sequences: dict[int, str] = {}

        async def resolve_image(medication: _SavedMedication) -> str:
            item_seq = (medication.item_seq or "").strip()
            if not item_seq:
                item_seq = self._resolve_catalog_item_seq(
                    medication.item_name or ""
                )
                if item_seq:
                    resolved_item_sequences[medication.id] = item_seq
            async with semaphore:
                return await self.medication_image_lookup.searchMedicationImage(
                    medication.item_name or "",
                    item_seq,
                )

        results = await asyncio.gather(
            *(resolve_image(medication) for medication in candidates),
            return_exceptions=True,
        )
        enrichment: dict[int, tuple[str, str]] = {}
        has_persistence_changes = False
        for medication, result in zip(candidates, results, strict=True):
            if isinstance(result, asyncio.CancelledError):
                raise result
            item_seq = resolved_item_sequences.get(
                medication.id,
                (medication.item_seq or "").strip(),
            )
            image_url = "" if isinstance(result, Exception) else result.strip()
            if isinstance(result, Exception):
                logger.warning(
                    "Saved medication image lookup failed: %s",
                    type(result).__name__,
                )
            if item_seq and not (medication.item_seq or "").strip():
                medication.item_seq = item_seq
                has_persistence_changes = True
            if image_url:
                medication.image_url = image_url
                has_persistence_changes = True
            enrichment[medication.id] = (item_seq, image_url)

        if has_persistence_changes:
            try:
                self.db.commit()
            except Exception as exc:
                self.db.rollback()
                logger.warning(
                    "Saved medication image metadata persistence failed: %s",
                    type(exc).__name__,
                )
        return enrichment

    def _resolve_catalog_item_seq(self, item_name: str) -> str:
        normalized_name = "".join(item_name.strip().lower().split())
        if not normalized_name:
            return ""

        item_sequences: set[str] = set()
        for model in (_DrugApprovalInfo, _DrugBasicInfo):
            rows = (
                self.db.query(model.item_seq)
                .filter(model.normalized_item_name == normalized_name)
                .all()
            )
            item_sequences.update(
                str(row[0]).strip()
                for row in rows
                if row[0] is not None and str(row[0]).strip()
            )
        return next(iter(item_sequences)) if len(item_sequences) == 1 else ""

    # Function Name: requestDelete
    # Description:
    # - Deletes a saved medication by id.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope deletion.
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
    # - medication: SavedMedication entity from persistence layer.
    # Returns:
    # - JSON-compatible saved medication dictionary.
    def _to_response_dict(
        self,
        medication: _SavedMedication,
        *,
        item_seq_override: str = "",
        image_url_override: str = "",
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
            "item_seq": item_seq_override or medication.item_seq or "",
            "item_name": medication.item_name,
            "efficacy": medication.efficacy,
            "use_method": medication.use_method,
            "warning_message": medication.warning_message,
            "dosage_per_time": medication.dosage_per_time,
            "daily_frequency": medication.daily_frequency,
            "total_days": medication.total_days,
            "schedule_slot_keys": decode_medication_schedule_slot_keys(
                medication.schedule_slot_keys
            ),
            "image_url": image_url_override or medication.image_url,
            "ai_guide": medication.ai_guide,
        }

    # Function Name: _get_existing_medication
    # Description:
    # - Finds an existing saved medication or raises a 404 error.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope lookup.
    # Returns:
    # - Existing _SavedMedication row.
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

    # Function Name: _delete_medication_completions
    # Description:
    # - Removes per-slot completion rows owned by a saved medication.
    # Parameters:
    # - medication: Saved medication row being deleted.
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

    # 함수명: _find_today_duplicate
    # 함수역할:
    # - 같은 환자와 오늘 날짜에 이미 저장된 동일 복약 정보를 확인한다.
    # - 약 이름이 같아도 조제일자나 실제 복용기간이 다르면 별도 정보로 취급한다.
    # 매개변수:
    # - patient_hash: 저장 범위를 구분하는 환자 해시
    # - registration_date: 등록일자
    # - deduplication_key: 처방 핵심값을 정규화한 중복 키
    # 반환값:
    # - 중복 row가 있으면 _SavedMedication
    # - 중복이 없으면 None
    def _find_today_duplicate(
        self,
        patient_hash: str,
        registration_date: date,
        deduplication_key: str,
    ) -> _SavedMedication | None:
        return (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.patient_hash == patient_hash,
                _SavedMedication.created_date == registration_date,
                _SavedMedication.deduplication_key == deduplication_key,
            )
            .first()
        )

    # 함수명: _build_deduplication_key
    # 역할:
    # - DB 유니크 제약과 사전 중복 조회가 공유할 결정적 처방 키를 만든다.
    def _build_deduplication_key(
        self,
        medication: SavedMedicationCreate,
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
            dosage_per_time=medication.dosage_per_time,
            daily_frequency=medication.daily_frequency,
            total_days=medication.total_days,
            schedule_slot_keys=normalized_slot_keys,
        )
