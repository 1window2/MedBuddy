# 파일명: check_schedule_control.py
# 역할: ClassDiagram2의 CheckSchedule 박스에 대응하는 제어 클래스이다.

from datetime import date, timedelta
import re

from fastapi import HTTPException
from sqlalchemy.orm import Session

from controls.link_patient_caregiver_control import LinkPatientCaregiver
from entities.medication_schedule_entity import MedicationSchedule
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH, normalize_patient_hash
from entities.saved_medication_entity import _SavedMedication

_TOTAL_DAYS_PATTERN = re.compile(r"\d+")
_GUARDIAN_ROLES = {"guardian", "caregiver"}

# 클래스명: CheckSchedule
# 역할: 복약 일정을 조회하고 상태를 변경한다.
# 주요 책임:
#   - 환자 또는 연동 보호자 권한 범위의 오늘 복약 일정을 읽는다.
#   - Persist a medication completion status for one saved medication row.
# 속성:
#   - db: 복약 일정 저장/변경 작업에 사용하는 SQLAlchemy 세션
class CheckSchedule:
    def __init__(self, db: Session) -> None:
        self.db = db

    # 함수명: requestMedicationSchedule
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 오늘 복약 일정 조회 wrapper이다.
    # 매개변수:
    # - patient_hash: 복약 일정 조회 범위를 구분하는 환자 해시
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # 반환값:
    # - API-compatible schedule list response dictionary.
    def requestMedicationSchedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_today_medication_schedule(patient_hash, user_hash, role)

    # 함수명: requestTodayMedicationSchedule
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 오늘 복약 일정 조회 wrapper이다.
    # 매개변수:
    # - patient_hash: 복약 일정 조회 범위를 구분하는 환자 해시
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # 반환값:
    # - API-compatible schedule list response dictionary.
    def requestTodayMedicationSchedule(
        self,
        patient_hash: str = DEFAULT_PATIENT_HASH,
        user_hash: str | None = None,
        role: str = "patient",
    ) -> dict[str, object]:
        return self.request_today_medication_schedule(patient_hash, user_hash, role)

    # 함수명: request_today_medication_schedule
    # 함수역할:
    # - Reads active medication schedules for today's date.
    # 매개변수:
    # - patient_hash: 복약 일정 조회 범위를 구분하는 환자 해시
    # - user_hash: Requesting user hash. Used for guardian role resolution.
    # - role: Requesting user role such as patient or guardian.
    # 반환값:
    # - API-compatible schedule list response dictionary.
    def request_today_medication_schedule(
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
        today = date.today()
        medications = (
            self.db.query(_SavedMedication)
            .filter(_SavedMedication.patient_hash == normalized_patient_hash)
            .order_by(_SavedMedication.id.asc())
            .all()
        )
        active_schedules = [
            self._to_schedule_dict(medication)
            for medication in medications
            if self._is_active_today(medication, today)
        ]
        return {
            "success": True,
            "message": "Today medication schedule lookup succeeded.",
            "data": active_schedules,
        }

    # 함수명: updateMedicationStatus
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 복약 상태 저장 wrapper이다.
    # 매개변수:
    # - medication_id: Saved medication primary key.
    # - medication_status: New medication completion status.
    # - patient_hash: 변경 범위를 구분하는 환자 해시
    # 반환값:
    # - API-compatible status update response dictionary.
    def updateMedicationStatus(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        return self.update_medication_status(
            medication_id,
            medication_status,
            patient_hash,
        )

    # 함수명: update_medication_status
    # 함수역할:
    # - 저장된 약 하나의 복약 완료 상태를 저장한다.
    # 매개변수:
    # - medication_id: Saved medication primary key.
    # - medication_status: New medication completion status.
    # - patient_hash: 변경 범위를 구분하는 환자 해시
    # 반환값:
    # - API-compatible status update response dictionary.
    def update_medication_status(
        self,
        medication_id: int,
        medication_status: bool,
        patient_hash: str = DEFAULT_PATIENT_HASH,
    ) -> dict[str, object]:
        medication = self._get_existing_medication(medication_id, patient_hash)
        schedule = self._to_schedule(medication)
        schedule.saveMedicationStatus(medication_status)

        try:
            medication.medication_status = schedule.medcation_status
            self.db.commit()
            self.db.refresh(medication)
        except Exception as exc:
            self.db.rollback()
            raise HTTPException(
                status_code=500,
                detail=f"Status update failed: {exc}",
            ) from exc

        return {
            "success": True,
            "message": "Medication status was updated.",
            "data": self._to_schedule_dict(medication),
        }

    # 함수명: _get_existing_medication
    # 함수역할:
    # - 환자 범위 안에서 기존 저장 약을 찾고 없으면 404를 발생시킨다.
    # 매개변수:
    # - medication_id: Saved medication primary key.
    # - patient_hash: 조회 범위를 구분하는 환자 해시
    # 반환값:
    # - Existing saved medication row.
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
            raise HTTPException(
                status_code=404,
                detail="Medication schedule was not found.",
            )
        return medication

    # 함수명: _to_schedule_dict
    # 함수역할:
    # - 저장 복약 row를 JSON 호환 복약 일정 DTO로 변환한다.
    # 매개변수:
    # - medication: Saved medication row.
    # 반환값:
    # - JSON-compatible medication schedule dictionary.
    def _to_schedule_dict(self, medication: _SavedMedication) -> dict[str, object]:
        schedule = self._to_schedule(medication).getTodayMedicationSchedule()
        return {
            "medication_id": schedule.medication_id,
            "drug_name": schedule.medication_name,
            "dosage_per_time": schedule.dosage,
            "daily_frequency": schedule.intake_time,
            "medication_status": schedule.medcation_status,
            "patient_hash": schedule.patient_id,
            "patient_id": schedule.patient_id,
            "total_days": schedule.medication_time,
            "created_date": (
                schedule.created_date.isoformat()
                if schedule.created_date is not None
                else ""
            ),
        }

    # 함수명: resolvePatientHash
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 환자/보호자 권한 범위 확인 wrapper이다.
    # 매개변수:
    # - patient_hash: Direct patient hash for patient requests.
    # - user_hash: Requesting user hash for guardian requests.
    # - role: Requesting user role.
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

    # 함수명: _to_schedule
    # 함수역할:
    # - 저장 복약 row를 MedicationSchedule 엔티티로 변환한다.
    # 매개변수:
    # - medication: Saved medication row.
    # 반환값:
    # - MedicationSchedule entity.
    def _to_schedule(self, medication: _SavedMedication) -> MedicationSchedule:
        return MedicationSchedule(
            created_date=self._read_created_date(
                medication.created_date,
                date.today(),
            ),
            medication_id=str(medication.id),
            medication_name=medication.item_name or "",
            dosage=medication.dosage_per_time or "",
            intake_time=medication.daily_frequency or "",
            medcation_status=bool(medication.medication_status),
            patient_id=medication.patient_hash or DEFAULT_PATIENT_HASH,
            medication_time=medication.total_days or "",
        )

    # 함수명: _is_active_today
    # 함수역할:
    # - Checks whether a saved medication is active for today's schedule window.
    # 매개변수:
    # - medication: Saved medication row.
    # - today: Date used for deterministic evaluation.
    # 반환값:
    # - True when the medication should be shown in today's schedule.
    def _is_active_today(self, medication: _SavedMedication, today: date) -> bool:
        start_date = self._read_created_date(medication.created_date, today)
        total_days = self._read_total_days(medication.total_days)
        if total_days <= 0:
            return start_date <= today

        end_date = start_date + timedelta(days=total_days - 1)
        return start_date <= today <= end_date

    # 함수명: _read_created_date
    # 함수역할:
    # - Reads a saved medication created date with a safe fallback.
    # 매개변수:
    # - raw_date: SQLAlchemy에서 읽은 원본 created_date 값
    # - fallback_date: Date used when raw_date is empty or invalid.
    # 반환값:
    # - Parsed date.
    def _read_created_date(
        self,
        raw_date: object,
        fallback_date: date,
    ) -> date:
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
    # - Extracts a numeric medication duration from a schedule label.
    # 매개변수:
    # - raw_total_days: "7 days" 또는 "7일" 같은 원본 total_days 값
    # 반환값:
    # - Parsed duration in days, or 0 when unavailable.
    def _read_total_days(self, raw_total_days: str | None) -> int:
        if not raw_total_days:
            return 0
        match = _TOTAL_DAYS_PATTERN.search(raw_total_days)
        if match is None:
            return 0
        return int(match.group(0))
