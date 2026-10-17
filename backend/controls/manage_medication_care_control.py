# 파일명: manage_medication_care_control.py
# 역할: 환자 권한·버전을 검증하고 약 변경 및 날짜별 사용자 복용 보고를 처리한다.

from datetime import date, timedelta
import hashlib
import json
from uuid import UUID
from types import SimpleNamespace

from fastapi import HTTPException
from sqlalchemy import or_, update
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import Session

from controls.authorization_control import AuthorizationControl
from controls.check_saved_medication_control import CheckSavedMedication, SAVED_MEDICATION_LIMIT_DETAIL
from core.account_database_lock import ACCOUNT_BUSY_DETAIL, lock_account_operations
from core.application_clock import application_now, application_today
from core.config import settings
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.medication_care_entity import _MedicationCareAudit, _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.medication_schedule_entity import encode_medication_schedule_slot_keys
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from schemas.medication import SavedMedicationCreate
from schemas.medication_care import DoseHistoryUpdate, RegimenChangeRequest
from services.medication_care_recording import apply_completion_report, completion_snapshot
from services.medication_course_policy import MedicationCoursePolicy
from services.medication_dosing_mode import medication_dosing_mode

_CONFLICT = "This record has changed. Refresh it before trying again."


# 클래스명: ManageMedicationCare
# 역할: 정기·필요시 약 관리와 복용 기록의 원자적 변경을 조정한다.
# 주요 책임: 소유권, 날짜, 재전송·동시 변경, 과거 기록 보존을 검증한다.
# 속성: db: 요청 세션, policy: 일정 규칙, saved: 기존 저장 약 응답 어댑터.
class ManageMedicationCare:
    # 함수이름: __init__
    # 함수역할: 요청 세션과 기존 정책·저장 약 어댑터를 공유한다.
    # 매개변수: db: 세션. 반환값: 없음.
    def __init__(self, db: Session) -> None:
        self.db = db
        self.policy = MedicationCoursePolicy()
        self.saved = CheckSavedMedication(db)
        self._completion_events: list[dict[str, int]] = []

    def consumeCompletionEvents(self) -> list[dict[str, int]]:
        """커밋된 필요시 알림만 응답 후 즉시 전송 경계에 넘긴다."""
        events, self._completion_events = self._completion_events, []
        return events

    # 함수이름: _scope
    # 함수역할: 변경은 본인만, 조회는 활성 연동 보호자까지 허용하며 삭제된 계정을 거부한다.
    # 매개변수: principal: 인증 주체, requested: 대상, write: 변경 여부.
    # 반환값: 검증한 환자 범위.
    def _scope(self, principal: AuthenticatedPrincipal, requested: str | None, *, write: bool) -> str:
        if write and not principal.authentication_disabled and requested and requested != principal.user_hash:
            raise HTTPException(403, "Only the patient may change medication care records.")
        if not self.db.in_transaction():
            lock_account_operations(self.db, [principal.user_hash])
        if not principal.authentication_disabled:
            actor = self.db.get(_UserAccount, principal.user_hash)
            if actor is None or actor.deletion_requested_at is not None:
                raise HTTPException(410, "This MedBuddy account has been deleted.")
        owner = AuthorizationControl(self.db).resolvePatientScope(principal, requested, allow_caregiver=not write)
        account = self.db.get(_UserAccount, owner)
        if account is None or account.deletion_requested_at is not None:
            raise HTTPException(410, "This MedBuddy account has been deleted.")
        return owner

    # 함수이름: _medication
    # 함수역할: 소유권을 포함해 약을 잠가 두 변경의 검증·저장이 교차하지 않도록 한다.
    # 매개변수: owner: 환자, medication_id: 약 식별자. 반환값: 저장 약 또는 404.
    def _medication(self, owner: str, medication_id: int) -> _SavedMedication:
        row = self.db.query(_SavedMedication).filter(
            _SavedMedication.patient_hash == owner, _SavedMedication.id == medication_id,
        ).with_for_update().populate_existing().first()
        if row is None:
            raise HTTPException(404, "Medication was not found.")
        return row

    # 함수이름: _fingerprint
    # 함수역할: 경로와 검증된 본문을 해시하여 작업 ID의 다른 용도 재사용을 거부한다.
    # 매개변수: target: 대상 경로, payload: 본문. 반환값: SHA-256 서명.
    @staticmethod
    def _fingerprint(target: str, payload: dict[str, object]) -> str:
        return hashlib.sha256(json.dumps([target, payload], sort_keys=True, default=str).encode()).hexdigest()

    # 함수이름: _replay
    # 함수역할: 이미 성공한 동일 작업의 응답을 돌려주고 다른 요청이면 충돌 처리한다.
    # 매개변수: owner: 환자, operation_id: UUID, fingerprint: 서명. 반환값: 기존 응답 또는 None.
    def _replay(self, owner: str, operation_id: UUID, fingerprint: str) -> dict[str, object] | None:
        receipt = self.db.query(_MedicationCareOperation).filter_by(patient_hash=owner, operation_id=str(operation_id)).first()
        if receipt is None:
            return None
        if receipt.request_hash != fingerprint:
            raise HTTPException(409, "The operation ID was already used for a different request.")
        return json.loads(receipt.response_json)

    # 함수이름: _commit
    # 함수역할: 변경 결과와 재전송 영수증을 함께 커밋한다.
    # 매개변수: owner: 환자, operation_id: UUID, fingerprint: 서명, response: 응답.
    # 반환값: 성공 응답.
    def _commit(self, owner: str, operation_id: UUID, fingerprint: str, response: dict[str, object]) -> dict[str, object]:
        self.db.add(_MedicationCareOperation(
            patient_hash=owner, operation_id=str(operation_id), request_hash=fingerprint,
            response_json=json.dumps(response, ensure_ascii=False),
        ))
        self.db.commit()
        return response

    # 함수이름: change_medication
    # 함수역할: 기존 기록을 보존한 채 적용일 이후 중단하거나 새 약 버전을 추가한다.
    # 매개변수: principal: 인증 주체, medication_id: 기존 약, request: 변경 요청.
    # 반환값: 새 약/중단 약의 ID와 증가한 버전. 오래된 버전·과거 적용은 거부한다.
    def change_medication(self, principal: AuthenticatedPrincipal, medication_id: int, request: RegimenChangeRequest) -> dict[str, object]:
        try:
            owner = self._scope(principal, request.patient_hash, write=True)
            fingerprint = self._fingerprint(f"change/{medication_id}", request.model_dump(mode="json"))
            replay = self._replay(owner, request.operation_id, fingerprint)
            if replay is not None:
                return replay
            medication = self._medication(owner, medication_id)
            replay = self._replay(owner, request.operation_id, fingerprint)
            if replay is not None:
                return replay
            today = application_today()
            if not today <= request.effective_date <= today + timedelta(days=365):
                raise HTTPException(422, "The effective date must be today or within the next year; past regimens cannot be rewritten.")
            if request.expected_revision != (medication.regimen_revision or 0) or medication.stopped_on is not None:
                raise HTTPException(409, _CONFLICT)
            if request.effective_date < self.policy.read_start_date(medication, today):
                raise HTTPException(422, "The effective date cannot precede this regimen's start date.")
            if request.action == "stop" and request.changes.model_fields_set:
                raise HTTPException(422, "A stop request must not include replacement fields.")
            if request.action == "edit" and not request.changes.model_fields_set:
                raise HTTPException(422, "Choose at least one field to change.")
            # 오늘 중단은 이미 남긴 당일 보고를 허용하지만 미래 보고가 있는 경계는 바꾸지 않는다.
            record_boundary = (
                max(request.effective_date, today + timedelta(days=1))
                if request.action == "stop" else request.effective_date
            )
            has_records = self.db.query(_MedicationCompletion.id).filter(
                _MedicationCompletion.patient_hash == owner,
                _MedicationCompletion.saved_medication_id == medication_id,
                _MedicationCompletion.schedule_date >= record_boundary,
                or_(_MedicationCompletion.completed.is_(True), _MedicationCompletion.revision > 0),
            ).first()
            if has_records or (
                medication.medication_status and medication.medication_status_date
                and medication.medication_status_date >= record_boundary
            ):
                raise HTTPException(409, "This date already has dose records. Choose a later effective date to preserve them.")
            if request.action == "stop" and medication.medication_status and medication.medication_status_date:
                from controls.check_schedule_control import CheckSchedule
                schedule = CheckSchedule(self.db)
                previous_day = medication.medication_status_date
                existing = schedule._completion_rows_by_medication_id([medication], owner, previous_day).get(medication_id, [])
                schedule._materialize_missing_completion_slots(
                    medication, owner, previous_day,
                    schedule._slot_statuses_for_medication(medication, previous_day, existing), existing,
                )
            before = self.saved._to_response_dict(medication)
            next_revision = request.expected_revision + 1
            replacement: _SavedMedication | None = None
            if request.action != "stop":
                replacement = self._replacement(medication, request, owner)
                replacement.regimen_revision = next_revision
                self.db.add(replacement)
                self.db.flush()
            changed = self.db.execute(update(_SavedMedication).where(
                _SavedMedication.id == medication_id, _SavedMedication.patient_hash == owner,
                _SavedMedication.regimen_revision == request.expected_revision, _SavedMedication.stopped_on.is_(None),
            ).values(
                stopped_on=request.effective_date, regimen_revision=next_revision,
                superseded_by_id=replacement.id if replacement else None,
            ).execution_options(synchronize_session=False))
            if changed.rowcount != 1:
                raise HTTPException(409, _CONFLICT)
            self.db.refresh(medication)
            result = replacement or medication
            response = {"success": True, "id": result.id, "revision": next_revision}
            self.db.add(_MedicationCareAudit(
                patient_hash=owner, medication_id=medication_id, kind=request.action,
                before_json=json.dumps(before, ensure_ascii=False),
                after_json=json.dumps({"previous": self.saved._to_response_dict(medication), "current": self.saved._to_response_dict(result)}, ensure_ascii=False),
            ))
            return self._commit(owner, request.operation_id, fingerprint, response)
        except (IntegrityError, OperationalError) as exc:
            self.db.rollback()
            raise HTTPException(409 if isinstance(exc, IntegrityError) else 503, _CONFLICT if isinstance(exc, IntegrityError) else ACCOUNT_BUSY_DETAIL) from exc
        except Exception:
            self.db.rollback()
            raise

    # 함수이름: _replacement
    # 함수역할: 변경 필드만 복사한 새 스냅샷을 만들고 새 이름에 이전 약의 설명을 붙이지 않는다.
    # 매개변수: old: 이전 약, request: 변경, owner: 환자. 반환값: 아직 커밋하지 않은 새 약.
    def _replacement(self, old: _SavedMedication, request: RegimenChangeRequest, owner: str) -> _SavedMedication:
        if self.saved.medication_repository.count_by_patient(owner) >= settings.SAVED_MEDICATION_MAX_PER_ACCOUNT:
            raise HTTPException(409, SAVED_MEDICATION_LIMIT_DETAIL)
        changes = request.changes.model_dump(exclude_unset=True)
        values = {column.name: getattr(old, column.name) for column in _SavedMedication.__table__.columns if column.name not in {
            "id", "created_date", "regimen_revision", "regimen_effective_from", "stopped_on", "superseded_by_id",
            "deduplication_key", "medication_status", "medication_status_date",
        }}
        values.update(changes)
        if "prescription_date" not in changes:
            values["prescription_date"] = old.prescription_date or old.created_date
        if "schedule_slot_keys" in changes:
            values["schedule_slot_keys"] = encode_medication_schedule_slot_keys(changes["schedule_slot_keys"])
        values["dosing_mode"] = medication_dosing_mode(SimpleNamespace(**values))
        if "prescription_date" in changes:
            try:
                SavedMedicationCreate.validate_prescription_date(changes["prescription_date"])
            except ValueError as exc:
                raise HTTPException(422, str(exc)) from exc
            if changes["prescription_date"] < request.effective_date:
                raise HTTPException(422, "A newly specified prescription date cannot precede the effective date.")
        if values["item_name"] != old.item_name:
            for key in ("item_seq", "image_url", "ai_guide"):
                values[key] = None
            for key in ("efficacy", "use_method", "warning_message", "interaction", "side_effect", "storage_method"):
                values[key] = ""
        result = _SavedMedication(**values, created_date=application_today(), regimen_effective_from=request.effective_date)
        if not self.policy.is_active_on(result, request.effective_date):
            raise HTTPException(422, "The replacement course must include the effective date. Check its prescription date and duration.")
        # 버전 변경은 의도한 별도 스냅샷이다. 일반 등록의 당일 중복 방지 키는 바꾸지 않는다.
        result.deduplication_key = hashlib.sha256(f"care:{owner}:{old.id}:{request.operation_id}".encode()).hexdigest()
        return result

    # 함수이름: _validate_range
    # 함수역할: 기록 조회·수정을 오늘 포함 최근 90일, 한 번에 31일로 제한한다.
    # 매개변수: start/end: 포함 날짜. 반환값: 없음, 잘못된 범위는 422.
    @staticmethod
    def _validate_range(start: date, end: date) -> None:
        today = application_today()
        if start > end or start < today - timedelta(days=89) or end > today or (end - start).days >= 31:
            raise HTTPException(422, "Choose up to 31 days within the last 90 days, ending no later than today.")

    # 함수이름: history
    # 함수역할: 예정일의 미기록 항목과 모든 실제 보고를 결합하되 필요시 약은 빈 일정을 만들지 않는다.
    # 매개변수: principal: 주체, start/end: 날짜, patient_hash: 선택 환자.
    # 반환값: 항목·저장 약·조회 범위를 담은 응답.
    def history(self, principal: AuthenticatedPrincipal, start: date, end: date, patient_hash: str | None = None) -> dict[str, object]:
        self._validate_range(start, end)
        owner = self._scope(principal, patient_hash, write=False)
        medications = self.saved.medication_repository.list_by_patient(owner)
        by_id = {med.id: med for med in medications}
        rows = self.db.query(_MedicationCompletion).filter(
            _MedicationCompletion.patient_hash == owner, _MedicationCompletion.schedule_date >= start,
            _MedicationCompletion.schedule_date <= end,
        ).all()
        items: dict[tuple[int, date, str], dict[str, object]] = {}
        for row in rows:
            med = by_id.get(row.saved_medication_id)
            if med is not None:
                items[(med.id, row.schedule_date, row.slot_key)] = self._history_item(med, row.schedule_date, row.slot_key, row)
        for offset in range((end - start).days + 1):
            target = start + timedelta(days=offset)
            for med in medications:
                if not self.policy.is_due_on(med, target):
                    continue
                for slot in self.policy.read_slot_keys(med.schedule_slot_keys, med.daily_frequency):
                    items.setdefault((med.id, target, slot), self._history_item(med, target, slot))
        return {
            "items": [items[key] for key in sorted(items, key=lambda key: (-key[1].toordinal(), key[0], key[2]))],
            "medications": [
                {
                    **self.saved._to_response_dict(med),
                    "can_record_as_needed": (
                        medication_dosing_mode(med) == "as_needed"
                        and self.policy.is_active_on(med, end)
                    ),
                }
                for med in medications
            ],
            "start_date": start.isoformat(), "end_date": end.isoformat(),
        }

    # 함수이름: _history_item
    # 함수역할: 저장 기록 또는 이전 버전의 행 단위 완료 상태를 같은 응답으로 표현한다.
    # 매개변수: med: 약, day: 예정일, slot: 시간대, row: 선택 기록.
    # 반환값: 실제 복용 증명이 아닌 사용자 보고 항목.
    @staticmethod
    def _history_item(med: _SavedMedication, day: date, slot: str, row: _MedicationCompletion | None = None) -> dict[str, object]:
        legacy_taken = med.medication_status and med.medication_status_date == day
        data = completion_snapshot(row) if row is not None else {
            "medication_id": med.id, "schedule_date": day.isoformat(), "slot_key": slot,
            "status": "taken" if legacy_taken else "unrecorded", "actual_taken_at": None,
            "recorded_at": None, "reason": "", "revision": 0,
        }
        return {**data, "item_name": med.item_name, "dosing_mode": medication_dosing_mode(med)}

    # 함수이름: update_history
    # 함수역할: 버전과 날짜·시간대·실제 시각을 검증한 뒤 사용자 보고 및 수정 이력을 저장한다.
    # 매개변수: principal: 주체, medication_id/day/slot: 대상, request: 정정 요청.
    # 반환값: 갱신한 기록. 필요시 복용은 UUID별 독립 기록을 사용한다.
    def update_history(self, principal: AuthenticatedPrincipal, medication_id: int, day: date, slot: str, request: DoseHistoryUpdate) -> dict[str, object]:
        self._completion_events = []
        try:
            owner = self._scope(principal, request.patient_hash, write=True)
            fingerprint = self._fingerprint(f"history/{medication_id}/{day}/{slot}", request.model_dump(mode="json"))
            replay = self._replay(owner, request.operation_id, fingerprint)
            if replay is not None:
                return replay
            med = self._medication(owner, medication_id)
            replay = self._replay(owner, request.operation_id, fingerprint)
            if replay is not None:
                return replay
            self._validate_range(day, day)
            row = self.db.query(_MedicationCompletion).filter_by(
                patient_hash=owner, saved_medication_id=medication_id, schedule_date=day, slot_key=slot,
            ).with_for_update().populate_existing().first()
            correct_existing = row is not None and (row.completed or (row.revision or 0) > 0)
            if medication_dosing_mode(med) == "as_needed":
                try:
                    prefix, event_id = slot.split(":", 1)
                    if prefix != "as_needed" or str(UUID(event_id)) != event_id:
                        raise ValueError()
                except ValueError as exc:
                    raise HTTPException(422, "PRN records require an as_needed:<UUID> slot key.") from exc
                if not self.policy.is_active_on(med, day) and not correct_existing:
                    raise HTTPException(422, "This PRN medication was not active on the selected date.")
            elif (not self.policy.is_due_on(med, day) and not correct_existing) or slot not in self.policy.read_slot_keys(med.schedule_slot_keys, med.daily_frequency):
                raise HTTPException(422, "This medication has no scheduled dose in the selected date and slot.")
            if request.actual_taken_at is not None:
                now = application_now()
                actual = request.actual_taken_at.astimezone(now.tzinfo)
                if actual > now or actual.date() < application_today() - timedelta(days=89):
                    raise HTTPException(422, "The actual dose time must be within the last 90 days and not in the future.")
            # 실제 복용 시각이 예정일과 달라도 예정일은 옮기지 않는다. 다음 날 복용도 사용자 보고로 남긴다.
            from controls.check_schedule_control import CheckSchedule
            schedule = CheckSchedule(self.db)
            active, completions = schedule._load_day(owner, day, include=med)
            before_states = schedule._slot_completion_states(active, completions, day, [slot])
            if schedule._is_legacy_completed_on(med, day) and medication_dosing_mode(med) == "scheduled":
                schedule._materialize_missing_completion_slots(
                    med, owner, day, schedule._slot_statuses_for_medication(med, day, completions.get(med.id, [])),
                    completions.setdefault(med.id, []),
                )
                self.db.flush()
            row = self.db.query(_MedicationCompletion).filter_by(
                patient_hash=owner, saved_medication_id=medication_id, schedule_date=day, slot_key=slot,
            ).with_for_update().populate_existing().first()
            if request.expected_revision != (row.revision or 0 if row is not None else 0):
                raise HTTPException(409, _CONFLICT)
            if row is None:
                row = _MedicationCompletion(
                    patient_hash=owner, saved_medication_id=medication_id, schedule_date=day, slot_key=slot,
                    completed=bool(med.medication_status and med.medication_status_date == day), completed_at=None,
                )
                self.db.add(row)
            apply_completion_report(self.db, row, status=request.status, actual_taken_at=request.actual_taken_at, reason=request.reason)
            self.db.flush()
            # 오늘만 이전 앱의 전체 완료 표시를 갱신한다. 과거 정정은 오늘 상태를 건드리지 않는다.
            if day == application_today() and medication_dosing_mode(med) == "scheduled":
                statuses = schedule._slot_statuses_for_medication(med, day)
                med.medication_status = bool(statuses) and all(statuses.values())
                med.medication_status_date = day
                active, updated = schedule._load_day(owner, day)
                schedule._queue_slot_completion_events(
                    patient_hash=owner, schedule_date=day, target_slot_keys=[slot],
                    active_medications=active, completion_rows_by_medication_id=updated,
                    previous_slot_completion_states=before_states, alertable=True,
                )
            response = {"success": True, **self._history_item(med, day, slot, row)}
            result = self._commit(owner, request.operation_id, fingerprint, response)
            return result
        except (IntegrityError, OperationalError) as exc:
            self.db.rollback()
            raise HTTPException(409 if isinstance(exc, IntegrityError) else 503, _CONFLICT if isinstance(exc, IntegrityError) else ACCOUNT_BUSY_DETAIL) from exc
        except Exception:
            self.db.rollback()
            raise
