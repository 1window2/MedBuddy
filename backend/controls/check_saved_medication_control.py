# File Name: check_saved_medication_control.py
# Role: Control class for saved medication persistence workflows.

from datetime import date, timedelta
import re
from fastapi import HTTPException
from sqlalchemy.orm import Session

from controls.patient_guardian_link_control import PatientGuardianLinkControl
from entities.medication_completion_entity import _MedicationCompletion
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication
from schemas.medication import SavedMedicationCreate
from services.saved_medication_retention import SavedMedicationRetentionPolicy

_TOTAL_DAYS_PATTERN = re.compile(r"\d+")


# Class Name: CheckSavedMedication
# Role: Coordinates saved medication CRUD use cases.
# Responsibilities:
#   - Save medication snapshots.
#   - List saved medications for the requested patient or linked guardian scope.
#   - Delete saved medications with not-found handling.
# Attributes:
#   - db: SQLAlchemy session used for persistence operations.
class CheckSavedMedication:
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: save_medication_detail
    # Description:
    # - Persists a selected medication as a saved medication snapshot.
    # Parameters:
    # - medication: Validated saved medication DTO.
    # Returns:
    # - API-compatible success response dictionary.
    def save_medication_detail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        try:
            patient_hash = normalize_patient_hash(medication.patient_hash)
            duplicate_medication = self._find_today_duplicate(
                patient_hash,
                medication,
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
                prescription_date=medication.prescription_date,
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

    # Function Name: saveMedicationDetail
    # Description:
    # - Class diagram compatible wrapper for save_medication_detail.
    # Parameters:
    # - medication: Validated saved medication DTO.
    # Returns:
    # - API-compatible success response dictionary.
    def saveMedicationDetail(
        self,
        medication: SavedMedicationCreate,
    ) -> dict[str, object]:
        return self.save_medication_detail(medication)

    # Function Name: request_saved_medication_info
    # Description:
    # - Reads saved medications owned by one patient hash or linked guardian scope.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope saved medication lookup.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible list response dictionary.
    def request_saved_medication_info(
        self,
        patient_hash: str | None = None,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        normalized_patient_hash = self._resolve_patient_hash(
            patient_hash,
            user_hash,
            role,
        )
        SavedMedicationRetentionPolicy().cleanup_expired_medications(
            self.db,
            normalized_patient_hash,
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

    # Function Name: requestSavedMedicationInfo
    # Description:
    # - Class diagram compatible wrapper for request_saved_medication_info.
    # Parameters:
    # - patient_hash: Patient ownership key used to scope saved medication lookup.
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # Returns:
    # - API-compatible list response dictionary.
    def requestSavedMedicationInfo(
        self,
        patient_hash: str | None = None,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_saved_medication_info(patient_hash, user_hash, role)

    # Function Name: request_delete
    # Description:
    # - Deletes a saved medication by id.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope deletion.
    # Returns:
    # - API-compatible success response dictionary.
    def request_delete(
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
            raise HTTPException(status_code=500, detail=f"Delete failed: {exc}") from exc

    # Function Name: requestDelete
    # Description:
    # - Class diagram compatible wrapper for request_delete.
    # Parameters:
    # - medication_id: Saved medication primary key.
    # - patient_hash: Patient ownership key used to scope deletion.
    # Returns:
    # - API-compatible delete success dictionary.
    def requestDelete(
        self,
        medication_id: int,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.request_delete(medication_id, patient_hash)

    # Function Name: _to_response_dict
    # Description:
    # - Converts a SavedMedication ORM entity into a JSON-serializable API DTO.
    # Parameters:
    # - medication: SavedMedication entity from persistence layer.
    # Returns:
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
            "prescription_date": (
                medication.prescription_date.isoformat()
                if medication.prescription_date
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

    # Function Name: resolvePatientHash
    # Description:
    # - Class diagram compatible wrapper for patient/guardian scope resolution.
    # Parameters:
    # - patient_hash: Direct patient hash for patient requests.
    # - user_hash: Requesting user hash for guardian requests.
    # - role: Requesting user role.
    # Returns:
    # - Patient hash authorized for this request.
    def resolvePatientHash(
        self,
        patient_hash: str | None = None,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        return self._resolve_patient_hash(patient_hash, user_hash, role)

    def _resolve_patient_hash(
        self,
        patient_hash: str | None = None,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> str:
        return PatientGuardianLinkControl(self.db).resolve_patient_scope(
            patient_hash,
            user_hash,
            role,
        )

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
    # - medication: 저장하려는 복약 정보 DTO
    # 반환값:
    # - 중복 row가 있으면 _SavedMedication
    # - 중복이 없으면 None
    def _find_today_duplicate(
        self,
        patient_hash: str,
        medication: SavedMedicationCreate,
    ) -> _SavedMedication | None:
        normalized_item_name = self._normalize_item_name(medication.item_name)
        if not normalized_item_name:
            return None

        requested_signature = self._build_duplicate_signature(
            item_name=medication.item_name,
            prescription_date=medication.prescription_date,
            dosage_per_time=medication.dosage_per_time,
            daily_frequency=medication.daily_frequency,
            total_days=medication.total_days,
        )

        today_medications = (
            self.db.query(_SavedMedication)
            .filter(
                _SavedMedication.patient_hash == patient_hash,
                _SavedMedication.created_date == date.today(),
            )
            .all()
        )
        for medication in today_medications:
            stored_signature = self._build_duplicate_signature(
                item_name=medication.item_name or "",
                prescription_date=medication.prescription_date,
                dosage_per_time=medication.dosage_per_time,
                daily_frequency=medication.daily_frequency,
                total_days=medication.total_days,
            )
            if stored_signature == requested_signature:
                return medication
        return None

    # 함수명: _build_duplicate_signature
    # 함수역할:
    # - 중복 판정에 사용할 복약 정보의 핵심 식별값을 만든다.
    # - 등록일자는 조회 조건에서 오늘로 이미 제한하므로 실제 복용기간과 약 정보를 묶는다.
    # 매개변수:
    # - item_name: 약품명
    # - prescription_date: 실제 복용 시작일로 쓰는 조제일자
    # - dosage_per_time: 1회 투약량
    # - daily_frequency: 1일 복용 횟수
    # - total_days: 총 복용 일수
    # 반환값:
    # - 중복 비교용 tuple
    def _build_duplicate_signature(
        self,
        *,
        item_name: str,
        prescription_date: date | None,
        dosage_per_time: str | None,
        daily_frequency: str | None,
        total_days: str | None,
    ) -> tuple[str, str, str, str, str, str]:
        start_date = prescription_date or date.today()
        return (
            self._normalize_item_name(item_name),
            start_date.isoformat(),
            self._read_medication_end_date(start_date, total_days).isoformat(),
            self._normalize_schedule_value(dosage_per_time),
            self._normalize_schedule_value(daily_frequency),
            self._normalize_schedule_value(total_days),
        )

    # 함수명: _read_medication_end_date
    # 함수역할:
    # - 조제일자와 총 복용 일수로 실제 복용 종료일을 계산한다.
    # 매개변수:
    # - start_date: 복용 시작일
    # - total_days: "7일" 같은 총 복용 일수 문자열
    # 반환값:
    # - 복용 종료일
    def _read_medication_end_date(
        self,
        start_date: date,
        total_days: str | None,
    ) -> date:
        if not total_days:
            return start_date
        match = _TOTAL_DAYS_PATTERN.search(total_days)
        if match is None:
            return start_date
        days = max(int(match.group(0)), 1)
        return start_date + timedelta(days=days - 1)

    # 함수명: _normalize_schedule_value
    # 함수역할:
    # - 복용량, 횟수, 기간 값의 공백 차이를 제거해 중복 비교를 안정화한다.
    # 매개변수:
    # - value: 원본 복용 정보 문자열
    # 반환값:
    # - 정규화된 문자열
    def _normalize_schedule_value(self, value: str | None) -> str:
        return " ".join((value or "").strip().lower().split())

    # 함수명: _normalize_item_name
    # 함수역할:
    # - 중복 비교에 사용할 약품명을 공백 제거와 소문자 기준으로 정규화한다.
    # 매개변수:
    # - item_name: 원본 약품명
    # 반환값:
    # - 정규화된 약품명
    def _normalize_item_name(self, item_name: str) -> str:
        return " ".join(item_name.strip().lower().split())
