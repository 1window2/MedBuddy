# 파일명: manage_medication_care_control.py
# 역할: 환자 권한·버전을 검증하고 약 변경 및 날짜별 사용자 복용 보고를 처리한다.

from collections import Counter
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
from services.as_needed_caregiver_events import queue_as_needed_taken_event
from services.medication_course_policy import MedicationCoursePolicy
from services.medication_dosing_mode import medication_dosing_mode

_CONFLICT = "This record has changed. Refresh it before trying again."
_CLIENT_CLOCK_SKEW = timedelta(seconds=60)


# 클래스명: ManageMedicationCare
# 역할: 정기·필요시 약 관리와 복용 기록의 원자적 변경을 조정한다.
# 주요 책임: 소유권, 날짜, 재전송·동시 변경, 과거 기록 보존을 검증한다.
# 속성: db: 요청 세션, policy: 일정 규칙, saved: 기존 저장 약 응답 어댑터.
class ManageMedicationCare:
    # 함수이름: __init__
    # 함수역할: 돌봄 기록에 사용할 세션·복약 기간 정책·저장 약품 제어기를 구성하고 완료 이벤트 대기 목록을 초기화한다.
    # 매개변수: db (Session)는 변경 작업에 사용할 세션이다.
    # 반환값: 없음.
    def __init__(self, db: Session) -> None:
        self.db = db
        self.policy = MedicationCoursePolicy()
        self.saved = CheckSavedMedication(db)
        self._completion_events: list[dict[str, int]] = []

    # 함수이름: consumeCompletionEvents
    # 함수역할: 성공적으로 저장된 필요시 복용 알림 목록을 넘기고 내부 대기 목록을 비운다.
    # 매개변수: 없음.
    # 반환값: 이벤트 ID를 담은 dict 목록. 같은 목록은 다음 호출에서 다시 반환하지 않는다.
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
    # 함수역할: 환자 소유 약품을 행 잠금으로 읽고 세션의 기존 상태를 새로 고친다.
    # 매개변수: owner (str)는 소유 환자, medication_id (int)는 대상 약품 ID이다.
    # 반환값: _SavedMedication. 소유 범위에 약품이 없으면 HTTP 404이며 잠금은 호출자의 트랜잭션에 속한다.
    def _medication(self, owner: str, medication_id: int) -> _SavedMedication:
        row = self.db.query(_SavedMedication).filter(
            _SavedMedication.patient_hash == owner, _SavedMedication.id == medication_id,
        ).with_for_update().populate_existing().first()
        if row is None:
            raise HTTPException(404, "Medication was not found.")
        return row

    # 함수이름: _fingerprint
    # 함수역할: 대상과 정렬된 JSON 요청을 SHA-256으로 해시하여 같은 작업 ID의 요청 변경을 판별할 서명을 만든다.
    # 매개변수: target (str)는 작업 대상, payload (dict[str, object])는 요청 내용이다.
    # 반환값: str 16진수 요청 서명.
    @staticmethod
    def _fingerprint(target: str, payload: dict[str, object]) -> str:
        return hashlib.sha256(json.dumps([target, payload], sort_keys=True, default=str).encode()).hexdigest()

    # 함수이름: _replay
    # 함수역할: 기존 작업 영수증을 조회하여 같은 요청의 저장 응답을 재사용한다.
    # 매개변수: owner (str)는 환자, operation_id (UUID)는 작업 ID, fingerprint (str)는 현재 요청 서명이다.
    # 반환값: dict[str, object] 저장 응답 또는 미존재 시 None. 요청이 다르면 409, 삭제로 응답이 비식별화됐으면 410이다.
    def _replay(self, owner: str, operation_id: UUID, fingerprint: str) -> dict[str, object] | None:
        receipt = self.db.query(_MedicationCareOperation).filter_by(patient_hash=owner, operation_id=str(operation_id)).first()
        if receipt is None:
            return None
        if receipt.request_hash != fingerprint:
            raise HTTPException(409, "The operation ID was already used for a different request.")
        if receipt.response_redacted:
            raise HTTPException(410, "The medication for this operation has been deleted.")
        return json.loads(receipt.response_json)

    # 함수이름: _commit
    # 함수역할: 변경 결과와 재전송 영수증을 함께 커밋한다.
    # 매개변수: owner (str)는 환자, operation_id (UUID)는 재전송 키, fingerprint (str)는 요청 서명, response (dict)는 응답이다.
    #   medication_id (int)는 원본 약, replacement_medication_id (int | None)는 대체 약으로 삭제 시 응답 정리에 사용한다.
    # 반환값: 저장된 성공 응답. commit 오류는 호출자로 전달한다.
    def _commit(
        self, owner: str, operation_id: UUID, fingerprint: str, response: dict[str, object],
        *, medication_id: int, replacement_medication_id: int | None = None,
    ) -> dict[str, object]:
        self.db.add(_MedicationCareOperation(
            patient_hash=owner, operation_id=str(operation_id), request_hash=fingerprint,
            response_json=json.dumps(response, ensure_ascii=False),
            medication_id=medication_id, replacement_medication_id=replacement_medication_id,
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
            return self._commit(
                owner, request.operation_id, fingerprint, response,
                medication_id=medication_id,
                replacement_medication_id=replacement.id if replacement else None,
            )
        except (IntegrityError, OperationalError) as exc:
            self.db.rollback()
            raise HTTPException(409 if isinstance(exc, IntegrityError) else 503, _CONFLICT if isinstance(exc, IntegrityError) else ACCOUNT_BUSY_DETAIL) from exc
        except Exception:
            self.db.rollback()
            raise

    # 함수이름: _replacement
    # 함수역할: 기존 약품에서 복약 변경 스냅샷을 만들고 변경된 처방 날짜·활성 기간을 검증한다. 약 이름 변경 시 기존 품목 설명·이미지·AI 안내를 제거한다.
    # 매개변수: old (_SavedMedication)는 원본, request (RegimenChangeRequest)는 변경 내용과 적용일, owner (str)는 소유 환자이다.
    # 반환값: _SavedMedication 미저장 대체 행. 저장 개수 한도는 409, 유효하지 않은 새 과정은 422이다.
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
    # 함수역할: 오늘까지 최근 90일 안에서 시작·종료 순서와 최대 31일의 조회 기간을 검증한다.
    # 매개변수: start (date)는 포함 시작일, end (date)는 포함 종료일이다.
    # 반환값: 없음. 잘못된 범위는 HTTP 422로 거절한다.
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
        return self._history_for_patient(owner, start, end)

    # 함수이름: history_share_context
    # 함수역할: 권한 확인된 환자의 이력을 정기·필요시와 taken·skipped·unrecorded 건수로 요약하며 복약률로 해석하지 않는다.
    # 매개변수: patient_hash (str)는 호출자가 활성 연동으로 검증한 환자, start·end (date)는 포함 조회 범위다.
    # 반환값: 기간·건수 dict. 허용 범위를 벗어나면 HTTP 422, DB 오류는 전달한다.
    def history_share_context(self, patient_hash: str, start: date, end: date) -> dict[str, object]:
        """호출자가 활성 연동으로 권한을 확인한 환자의 이력을 건수로만 요약한다."""
        self._validate_range(start, end)
        history = self._history_for_patient(patient_hash, start, end)
        # CSV와 같은 전체 항목을 세므로 필요시 기록도 포함하며 복약률로 해석하지 않는다.
        counts = Counter(item["status"] for item in history["items"])
        # 기존 합계는 이전 앱과 호환하고 새 그래프용 정기·필요시 집계를 따로 보존한다.
        scheduled = Counter(item["status"] for item in history["items"]
                            if item["dosing_mode"] != "as_needed")
        prn_taken = sum(item["dosing_mode"] == "as_needed" and item["status"] == "taken"
                        for item in history["items"])
        return {
            "start_date": history["start_date"], "end_date": history["end_date"],
            "taken_count": counts["taken"], "skipped_count": counts["skipped"],
            "unrecorded_count": counts["unrecorded"],
            "scheduled_taken_count": scheduled["taken"],
            "scheduled_skipped_count": scheduled["skipped"],
            "scheduled_unrecorded_count": scheduled["unrecorded"],
            "as_needed_taken_count": prn_taken,
        }

    # 함수이름: _history_for_patient
    # 함수역할: 실제 기록을 우선하고 예정된 정기 복용일의 빈 슬롯을 보충해 날짜 내림차순 이력을 만든다.
    # 매개변수: owner (str)는 권한 확인된 환자, start·end (date)는 검증된 포함 조회 범위다.
    # 반환값: 이력 항목·저장 약·기간 dict. 삭제된 약의 기록은 제외하며 필요시 약의 미기록 일정을 생성하지 않는다.
    def _history_for_patient(self, owner: str, start: date, end: date) -> dict[str, object]:
        """권한과 기간 검증을 마친 조회·공유에 동일한 이력 항목을 제공한다."""
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

    # Function Name: update_history
    # Description: Apply an idempotent, revision-checked scheduled or PRN dose correction, preserving audit history; only today's newly completed doses can enqueue alerts.
    # Parameters: principal authenticates the writer; medication_id, day and slot select the record; request (DoseHistoryUpdate) supplies patient scope, operation/revision, status, actual time and reason.
    # Returns: dict[str, object] saved or replayed response. Invalid dates/slots raise 422, revision/integrity conflicts 409, database contention 503; failures roll back.
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
            actual_taken_at = request.actual_taken_at
            if actual_taken_at is not None:
                now = application_now()
                try:
                    actual = actual_taken_at.astimezone(now.tzinfo)
                except OverflowError:
                    # 달력 끝의 시각은 앱 시간대로 옮길 수 없다. 허용 범위 밖이므로 같은 오류로 답한다.
                    actual = None
                # 기기 시계가 서버보다 조금 빠르면 '지금 복용'도 미래가 되므로 재인증 시각과 같은 허용치를 둔다.
                if actual is None or actual > now + _CLIENT_CLOCK_SKEW or actual.date() < application_today() - timedelta(days=89):
                    raise HTTPException(422, "The actual dose time must be within the last 90 days and not in the future.")
                # 허용치 안의 미래 시각은 서버가 받은 시각으로 저장해 기록이 미래에 놓이지 않게 한다.
                actual_taken_at = min(actual, now)
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
            was_taken = row is not None and bool(row.completed)
            if row is None:
                row = _MedicationCompletion(
                    patient_hash=owner, saved_medication_id=medication_id, schedule_date=day, slot_key=slot,
                    completed=bool(med.medication_status and med.medication_status_date == day), completed_at=None,
                )
                self.db.add(row)
            apply_completion_report(self.db, row, status=request.status, actual_taken_at=actual_taken_at, reason=request.reason)
            self.db.flush()
            prn_outbox_id = None
            if (
                day == application_today() and medication_dosing_mode(med) == "as_needed"
                and request.status == "taken" and not was_taken
            ):
                prn_outbox_id = queue_as_needed_taken_event(self.db, row)
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
            result = self._commit(
                owner, request.operation_id, fingerprint, response, medication_id=medication_id,
            )
            if prn_outbox_id is not None:
                self._completion_events.append({"outbox_id": prn_outbox_id})
            return result
        except (IntegrityError, OperationalError) as exc:
            self.db.rollback()
            raise HTTPException(409 if isinstance(exc, IntegrityError) else 503, _CONFLICT if isinstance(exc, IntegrityError) else ACCOUNT_BUSY_DETAIL) from exc
        except Exception:
            self.db.rollback()
            raise
