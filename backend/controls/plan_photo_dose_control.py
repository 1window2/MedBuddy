# 파일명: plan_photo_dose_control.py
# 역할: 사진에서 찾은 알약을 본인의 복약 중인 약과 맞추고, 약마다 기록할 날짜·시간대를 정해 계획을
#   만든다. 확인 요청은 같은 사진 시각으로 다시 계산해 한 트랜잭션에 기록한다.
#   규칙은 docs/Photo Dose Recording.md(세 번째 판)를 따른다.

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import math
import re
import secrets
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from typing import Callable
from uuid import UUID, uuid5

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from controls.check_schedule_control import CheckSchedule
from controls.identify_pill_control import has_same_shape_and_colors
from controls.set_notification_control import SetNotification
from core.application_clock import application_now
from entities.medication_care_entity import _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.medication_image_url_entity import safe_medication_image_url
from entities.pill_identification_entity import PillCatalogEntry
from entities.saved_medication_entity import _SavedMedication
from repositories.pill_identification_catalog_repository import (
    PillIdentificationCatalogRepository,
)
from repositories.saved_medication_repository import SavedMedicationRepository
from schemas.photo_dose import PhotoDoseConfirmRequest, PhotoDosePill, PhotoDosePlanRequest
from services.as_needed_caregiver_events import queue_as_needed_taken_event
from services.medication_care_recording import apply_completion_report
from services.medication_course_policy import MedicationCoursePolicy
from services.medication_dosing_mode import medication_dosing_mode

SLOT_ORDER = ("morning", "lunch", "evening", "bedtime")
WINDOW_CAP = timedelta(hours=6)
EARLY_WINDOW = timedelta(hours=3)
EARLY_REST_RATIO = 0.6
SCHEDULED_SPACING = timedelta(hours=2)
AS_NEEDED_SPACING = timedelta(hours=4)
TOKEN_LIFETIME = timedelta(minutes=15)
TOKEN_CLOCK_SKEW = timedelta(minutes=1)
# 서명 키는 프로세스마다 새로 만든다. 서버를 다시 시작하면 열린 계획은 사진을 다시 찍어야 한다.
_TOKEN_KEY = secrets.token_bytes(32)
_PHOTO_OPERATION_NAMESPACE = UUID("3f6b8a52-6c1e-4a77-9b3f-0c5d2e1a9f40")
_EXPIRED = "The photo plan expired. Take the photo again."
_CHANGED = "The medicines or slots changed. Check the photo again."

# 경고 띠에 올리는(기록하지 않는) 상태. skipped와 unknown은 조용히 적는다.
WARNING_STATUSES = ("recently_taken", "already_taken", "too_early", "extra", "unclear_slot", "not_due")
_DOSE_COUNT = re.compile(
    r"^\s*(\d+(?:\.\d+)?)\s*$|(\d+(?:\.\d+)?)\s*(?:정|캡슐|알|개|포|tab|tablet|capsule)",
    re.IGNORECASE,
)


# 함수이름: dose_capacity
# 함수역할: 1회 복용량 문구에서 한 번에 받을 알약 수를 읽는다. 숫자만 있거나 정·캡슐·알·개·포·tab이
#   붙은 경우만 읽는다. "500mg" 같은 함량과 "0.5정"은 알약 하나다.
# 매개변수: dosage (str | None): 1회 복용량 문구.
# 반환값: 1 이상 10 이하의 알약 수.
def dose_capacity(dosage: str | None) -> int:
    match = _DOSE_COUNT.search(dosage or "")
    if match is None:
        return 1
    return max(1, min(10, math.ceil(float(match.group(1) or match.group(2)))))


# 함수이름: issue_plan_token
# 함수역할: 본인과 사진 시각을 서명한 토큰을 만든다.
# 매개변수: owner (str): 본인; as_of (datetime): 사진 시각(서비스 시간대).
# 반환값: "시각.서명" 형식 문자열.
def issue_plan_token(owner: str, as_of: datetime) -> str:
    stamp = base64.urlsafe_b64encode(as_of.isoformat().encode()).decode().rstrip("=")
    signature = hmac.new(_TOKEN_KEY, f"{owner}|{stamp}".encode(), hashlib.sha256).hexdigest()
    return f"{stamp}.{signature}"


# 함수이름: read_plan_token
# 함수역할: 토큰의 서명과 수명을 확인하고 사진 시각을 돌려준다.
# 매개변수: owner (str): 본인; token (str): 토큰; now (datetime): 현재 시각.
# 반환값: 사진 시각. 서명이 틀리거나 15분이 지났으면 HTTP 409.
def read_plan_token(owner: str, token: str, now: datetime) -> datetime:
    try:
        stamp, signature = token.split(".", 1)
        expected = hmac.new(_TOKEN_KEY, f"{owner}|{stamp}".encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected):
            raise ValueError("signature")
        as_of = datetime.fromisoformat(base64.urlsafe_b64decode(stamp + "=" * (-len(stamp) % 4)).decode())
    except (ValueError, UnicodeDecodeError) as error:
        raise HTTPException(409, _EXPIRED) from error
    if as_of.tzinfo is None or as_of > now + TOKEN_CLOCK_SKEW or now - as_of > TOKEN_LIFETIME:
        raise HTTPException(409, _EXPIRED)
    return as_of.astimezone(now.tzinfo)


# 클래스명: Slot
# 역할: 날짜·시간대 한 칸과 기준 시각, 창의 끝을 담는다.
@dataclass
class Slot:
    day: date
    key: str
    at: datetime
    end: datetime

    @property
    def ref(self) -> tuple[date, str]:
        return self.day, self.key


# 클래스명: Decision
# 역할: 약 하나를 지금 기록할 수 있는지와 그 시간대·시각 구분을 담는다.
@dataclass
class Decision:
    status: str
    slot: Slot | None = None
    timing: str = ""
    detail_at: datetime | None = None


# 클래스명: PlanPhotoDose
# 역할: 사진으로 복용 기록의 계획과 기록을 맡는다.
# 주요 책임: 본인 약·복용 기록·알림 시각·카탈로그를 읽고 약별 시간대와 알약 배정을 정한다.
#   확인 요청은 같은 사진 시각으로 다시 계산해 앱이 본 기록 묶음과 같을 때만 한 트랜잭션에 기록한다.
# 속성: db (Session): 요청 세션; clock: 서비스 시간대의 현재 시각 공급자.
class PlanPhotoDose:
    # 함수이름: __init__
    # 함수역할: 세션과 시계를 보관한다.
    # 매개변수: db (Session): 요청 세션; clock (Callable[[], datetime] | None): 테스트용 시계.
    # 반환값: 없음.
    def __init__(self, db: Session, clock: Callable[[], datetime] | None = None) -> None:
        self.db = db
        self.clock = clock or application_now
        self.policy = MedicationCoursePolicy()
        self.schedule = CheckSchedule(db)

    # 함수이름: plan
    # 함수역할: 요청한 알약과 답으로 계획을 만든다. 토큰이 없으면 지금을 사진 시각으로 정한다.
    # 매개변수: owner (str): 본인; request (PhotoDosePlanRequest): 알약·답·토큰.
    # 반환값: 계획 응답 dict.
    def plan(self, owner: str, request: PhotoDosePlanRequest) -> dict[str, object]:
        now = self.clock()
        as_of = read_plan_token(owner, request.plan_token, now) if request.plan_token else now
        result = self._compute(owner, request, as_of)
        result["plan_token"] = request.plan_token or issue_plan_token(owner, as_of)
        return result

    # 함수이름: confirm
    # 함수역할: 같은 사진 시각으로 다시 계산해 앱이 본 기록 묶음과 같으면 한 트랜잭션에 기록한다.
    # 매개변수: owner (str): 본인; request (PhotoDoseConfirmRequest): 계획 입력, 작업 ID, 기대한 기록.
    # 반환값: (응답, 보호자 알림 이벤트). 기록 묶음이 다르면 409, 같은 작업 ID의 다른 요청도 409.
    def confirm(
        self, owner: str, request: PhotoDoseConfirmRequest,
    ) -> tuple[dict[str, object], list[dict[str, object]]]:
        operation_id = str(request.operation_id)
        fingerprint = hashlib.sha256(
            json.dumps(request.model_dump(mode="json"), sort_keys=True).encode()
        ).hexdigest()
        receipt = self.db.query(_MedicationCareOperation).filter_by(
            patient_hash=owner, operation_id=operation_id,
        ).first()
        if receipt is not None:
            if receipt.request_hash != fingerprint:
                raise HTTPException(409, "The operation ID was already used for a different request.")
            return json.loads(receipt.response_json), []

        now = self.clock()
        as_of = read_plan_token(owner, request.plan_token, now)
        computed = self._compute(owner, request, as_of)
        if not computed["ready"] or computed["write"] != _normalized_write(request.expected.model_dump(mode="json")):
            raise HTTPException(409, _CHANGED)

        write = computed["write"]
        events: list[dict[str, object]] = []
        try:
            for group in write["groups"]:
                events.extend(self._record_slot(
                    owner, date.fromisoformat(group["schedule_date"]), group["slot_key"],
                    group["medication_ids"], as_of, today=now.date(),
                ))
            for medication_id in write["as_needed_medication_ids"]:
                outbox_id = self._record_as_needed(owner, medication_id, operation_id, as_of, today=now.date())
                if outbox_id is not None:
                    events.append({"outbox_id": outbox_id})
            # 영수증에는 약 정보를 남기지 않는다. 약을 지워도 재시도 응답이 그대로 유효하다.
            response = {"success": True, "operation_id": operation_id, "taken_at": as_of.isoformat()}
            self.db.add(_MedicationCareOperation(
                patient_hash=owner, operation_id=operation_id, request_hash=fingerprint,
                response_json=json.dumps(response, ensure_ascii=False), medication_id=None,
            ))
            self.db.commit()
        except IntegrityError as error:
            self.db.rollback()
            # 같은 요청이 먼저 커밋됐으면 그 결과를 돌려준다(응답이 늦어 다시 보낸 경우).
            receipt = self.db.query(_MedicationCareOperation).filter_by(
                patient_hash=owner, operation_id=operation_id,
            ).first()
            if receipt is not None and receipt.request_hash == fingerprint:
                return json.loads(receipt.response_json), []
            raise HTTPException(409, _CHANGED) from error
        except Exception:
            self.db.rollback()
            raise
        return response, events

    # 함수이름: _compute
    # 함수역할: 사진 시각 기준으로 약별 판단과 알약 배정을 계산한다.
    # 매개변수: owner (str): 본인; request: 알약·답; as_of (datetime): 사진 시각.
    # 반환값: 계획 응답 dict(토큰 제외).
    def _compute(self, owner: str, request: PhotoDosePlanRequest, as_of: datetime) -> dict[str, object]:
        now = as_of
        today = now.date()
        yesterday = today - timedelta(days=1)
        medications = [m for m in SavedMedicationRepository(self.db).list_by_patient(owner) if m.id is not None]
        by_id = {int(m.id): m for m in medications}
        item_seq_of = {mid: (m.item_seq or "").strip() for mid, m in by_id.items()}
        due = {day: [m for m in medications if self.policy.is_due_on(m, day)] for day in (yesterday, today)}
        as_needed = [
            m for m in medications
            if medication_dosing_mode(m) == "as_needed" and self.policy.is_active_on(m, today)
        ]
        all_slots = self._slots(due, self._reminder_times(owner), now.tzinfo)
        # 어제 칸은 창이 지금까지 이어질 때만 판단에 쓴다. 복용 시각 보정에는 닫힌 창도 쓴다.
        slots = [s for s in all_slots if s.day == today or s.end > now]
        rows = {
            day: self.schedule._completion_rows_by_medication_id(
                list({int(m.id): m for m in [*due[day], *as_needed]}.values()), owner, day,
            )
            for day in (yesterday, today)
        }
        handled = self._handled(due, rows)
        dose_times = self._dose_times(rows, all_slots, now)

        decisions: dict[int, Decision] = {}
        for medication in {int(m.id): m for m in [*due[yesterday], *due[today]]}.values():
            decisions[int(medication.id)] = self._decide_scheduled(
                medication, slots, handled, dose_times, by_id, now,
            )
        for medication in as_needed:
            last = self._last_dose(dose_times, by_id, int(medication.id))
            decisions[int(medication.id)] = (
                Decision("recently_taken", detail_at=last)
                if last is not None and now - last < AS_NEEDED_SPACING else Decision("recordable")
            )
        for medication in medications:
            mid = int(medication.id)
            if mid not in decisions and medication_dosing_mode(medication) == "scheduled" \
                    and self.policy.is_active_on(medication, today):
                decisions[mid] = Decision("not_due")

        recordable = {mid for mid, d in decisions.items() if d.status == "recordable"}
        capacity = {mid: dose_capacity(by_id[mid].dosage_per_time) for mid in by_id}
        catalog = PillIdentificationCatalogRepository(self.db).list_by_item_sequences(
            {seq for seq in item_seq_of.values() if seq}
        )
        pill_rows, assigned, ignored = _Assigner(
            request, recordable, decisions, capacity, item_seq_of, catalog,
        ).run()

        groups: dict[tuple[date, str], dict[str, object]] = {}
        for mid in sorted(assigned):
            slot = decisions[mid].slot
            if slot is None:
                continue
            group = groups.setdefault(slot.ref, {
                "schedule_date": slot.day.isoformat(),
                "slot_key": slot.key,
                "reminder_at": slot.at.isoformat(),
                "timing": decisions[mid].timing,
                "medication_ids": [],
            })
            group["medication_ids"].append(mid)  # type: ignore[union-attr]
        for (day, key), group in groups.items():
            pending = {
                int(m.id) for m in due[day]
                if key in self._slot_keys(m) and key not in handled.get((day, int(m.id)), set())
            }
            group["missing_medication_ids"] = sorted(pending - set(group["medication_ids"]))  # type: ignore[arg-type]
        ordered = sorted(groups.values(), key=lambda g: (g["schedule_date"], SLOT_ORDER.index(g["slot_key"])))
        as_needed_ids = sorted(mid for mid in assigned if decisions[mid].slot is None)

        referenced = set(assigned)
        for row in pill_rows:
            if row["medication_id"] is not None:
                referenced.add(int(row["medication_id"]))
            referenced.update(int(m) for m in row["options"])  # type: ignore[union-attr]
        for group in ordered:
            referenced.update(group["missing_medication_ids"])  # type: ignore[arg-type]

        write = {
            "groups": [
                {"schedule_date": g["schedule_date"], "slot_key": g["slot_key"], "medication_ids": g["medication_ids"]}
                for g in ordered
            ],
            "as_needed_medication_ids": as_needed_ids,
            "regimen_revisions": {str(mid): int(by_id[mid].regimen_revision or 0) for mid in sorted(assigned)},
        }
        has_write = bool(write["groups"] or as_needed_ids)
        return {
            "success": True,
            "as_of": as_of.isoformat(),
            "pills": pill_rows,
            "groups": ordered,
            "as_needed": [
                {
                    "medication_id": mid,
                    "taken_today": sum(
                        1 for r in rows[today].get(mid, [])
                        if r.completed and str(r.slot_key).startswith("as_needed")
                    ),
                    "last_taken_at": _iso(self._last_dose(dose_times, by_id, mid)),
                }
                for mid in as_needed_ids
            ],
            "ignored_answer_indexes": ignored,
            "medications": self._medications_json(by_id, referenced, catalog, item_seq_of, decisions),
            "write": write,
            "ready": has_write and not any(row["status"] == "needs_choice" for row in pill_rows),
        }

    # 함수이름: _slots
    # 함수역할: 어제와 오늘 약이 있는 시간대의 기준 시각과 창을 만든다.
    #   04시 전으로 정한 자기 전 알림은 그날 밤으로 보고, 기준 시각이 같은 칸은 창을 함께 쓴다.
    # 매개변수: due: 날짜별 먹을 약; reminder: 시간대별 (시, 분); zone: 서비스 시간대.
    # 반환값: 시각 순 시간대 목록.
    def _slots(
        self, due: dict[date, list[_SavedMedication]], reminder: dict[str, tuple[int, int]], zone,  # noqa: ANN001
    ) -> list[Slot]:
        starts: list[tuple[date, str, datetime]] = []
        for day, medications in sorted(due.items()):
            used = {key for m in medications for key in self._slot_keys(m)}
            for key in SLOT_ORDER:
                if key not in used:
                    continue
                hour, minute = reminder.get(key, (8, 0))
                at = datetime.combine(day, time(hour, minute), tzinfo=zone)
                if key == "bedtime" and hour < 4:
                    at += timedelta(days=1)
                starts.append((day, key, at))
        starts.sort(key=lambda s: (s[2], SLOT_ORDER.index(s[1])))
        slots = []
        for day, key, at in starts:
            later = next((other for _, _, other in starts if other > at), None)
            cap = at + WINDOW_CAP
            slots.append(Slot(day, key, at, min(later, cap) if later is not None else cap))
        return slots

    # 함수이름: _handled
    # 함수역할: 날짜·약별 처리한 시간대(복용 완료·건너뜀, 이전 앱의 하루 완료 표시)를 읽는다.
    # 매개변수: due: 날짜별 먹을 약; rows: 날짜별 약별 기록.
    # 반환값: (날짜, 약 ID)별 처리한 시간대 집합.
    def _handled(self, due, rows) -> dict[tuple[date, int], set[str]]:  # noqa: ANN001
        handled: dict[tuple[date, int], set[str]] = {}
        for day, medications in due.items():
            for medication in medications:
                mid = int(medication.id)
                done = set(self._slot_keys(medication)) if self.schedule._is_legacy_completed_on(medication, day) else set()
                for row in rows[day].get(mid, []):
                    if row.completed or row.report_status == "skipped":
                        done.add(row.slot_key)
                    else:
                        done.discard(row.slot_key)
                handled[(day, mid)] = done
        return handled

    # 함수이름: _dose_times
    # 함수역할: 약별 복용 시각을 읽는다. 복용 시각이 없는 기록은 기록 시각과 그 시간대 창 끝 중 이른 쪽이다.
    # 매개변수: rows: 날짜별 약별 기록; slots: 시간대; now: 시간대 기준.
    # 반환값: 약 ID별 복용 시각 목록.
    @staticmethod
    def _dose_times(rows, slots, now) -> dict[int, list[datetime]]:  # noqa: ANN001
        windows = {s.ref: s.end for s in slots}
        result: dict[int, list[datetime]] = {}
        for day, by_medication in rows.items():
            for mid, completion_rows in by_medication.items():
                for row in completion_rows:
                    if not row.completed:
                        continue
                    taken = _aware(row.actual_taken_at, now)
                    if taken is None:
                        candidates = [t for t in (_aware(row.completed_at, now), windows.get((day, row.slot_key))) if t]
                        taken = min(candidates) if candidates else None
                    if taken is not None:
                        result.setdefault(mid, []).append(taken)
        return result

    # 함수이름: _decide_scheduled
    # 함수역할: 정기 복용 약의 기록 시간대를 시간대 규칙과 최근 복용 간격으로 정한다.
    # 매개변수: medication: 약; slots: 시간대; handled: 처리한 시간대; dose_times: 복용 시각; by_id: 저장 약; now: 기준.
    # 반환값: Decision.
    def _decide_scheduled(self, medication, slots, handled, dose_times, by_id, now) -> Decision:  # noqa: ANN001
        mid = int(medication.id)
        keys = set(self._slot_keys(medication))
        due_days = {day for (day, other) in handled if other == mid}
        mine = [s for s in slots if s.key in keys and s.day in due_days]
        pending = [s for s in mine if s.key not in handled.get((s.day, mid), set())]
        if not pending:
            # 어제만 먹는 날이었던 약(격일 등)은 오늘 먹는 날이 아니다.
            return Decision("already_taken" if now.date() in due_days else "not_due")
        last_dose = self._last_dose(dose_times, by_id, mid)
        current = [s for s in pending if s.at <= now < s.end]
        if current:
            chosen = current[0]
            timing = "overnight" if chosen.day < now.date() else "on_time"
        else:
            today = now.date()
            upcoming = [s for s in pending if s.day == today and now < s.at <= now + EARLY_WINDOW]
            early = None
            if upcoming:
                candidate = upcoming[0]
                before = [s for s in mine if s.day == candidate.day and s.at < candidate.at]
                if not before or last_dose is None or (
                    now - last_dose >= (candidate.at - before[-1].at) * EARLY_REST_RATIO
                ):
                    early = candidate
            past = [s for s in pending if s.day == today and s.end <= now]
            future = [s for s in pending if s.day == today and s.at > now]
            if early is not None:
                chosen, timing = early, "early"
            elif past and not future:
                chosen, timing = past[-1], "late"
            elif past and future:
                return Decision("unclear_slot", detail_at=future[0].at)
            elif future:
                return Decision("too_early", detail_at=future[0].at)
            else:
                return Decision("already_taken")
        if last_dose is not None and now - last_dose < self._scheduled_spacing(mine, chosen):
            return Decision("recently_taken", detail_at=last_dose)
        return Decision("recordable", chosen, timing)

    # 함수이름: _scheduled_spacing
    # 함수역할: 정기 복용 약의 최근 복용 간격을 정한다. 2시간과, 기록할 시간대와 그 약의 바로 앞 시간대 사이
    #   간격의 절반 가운데 짧은 쪽이다. 앞 시간대가 없으면 2시간이다.
    # 매개변수: mine: 그 약의 시간대(시각 순); chosen: 기록할 시간대.
    # 반환값: timedelta.
    @staticmethod
    def _scheduled_spacing(mine: list[Slot], chosen: Slot) -> timedelta:
        before = [slot.at for slot in mine if slot.at < chosen.at]
        if not before:
            return SCHEDULED_SPACING
        return min(SCHEDULED_SPACING, (chosen.at - max(before)) / 2)

    # 함수이름: _last_dose
    # 함수역할: 같은 약 또는 같은 품목의 다른 약(정기·필요시)의 가장 최근 복용 시각을 찾는다.
    # 매개변수: dose_times: 약별 복용 시각; by_id: 저장 약; mid: 약 ID.
    # 반환값: datetime 또는 None.
    @staticmethod
    def _last_dose(dose_times, by_id, mid) -> datetime | None:  # noqa: ANN001
        seq = (by_id[mid].item_seq or "").strip()
        related = {mid} | {other for other, m in by_id.items() if seq and (m.item_seq or "").strip() == seq}
        return max((t for other in related for t in dose_times.get(other, [])), default=None)

    # 함수이름: _record_slot
    # 함수역할: 한 시간대의 약들을 복용 완료로 기록하고, 오늘이면 보호자 완료 이벤트를 예약한다.
    # 매개변수: owner: 본인; day, slot_key: 시간대; medication_ids: 약; taken_at: 사진 시각; today: 오늘.
    # 반환값: 보호자 알림 이벤트 목록.
    def _record_slot(self, owner, day, slot_key, medication_ids, taken_at, *, today) -> list[dict[str, object]]:  # noqa: ANN001
        active, completions = self.schedule._load_day(owner, day)
        before = self.schedule._slot_completion_states(active, completions, day, [slot_key])
        for mid in medication_ids:
            medication = self.db.get(_SavedMedication, mid)
            if medication is None or medication.patient_hash != owner:
                raise HTTPException(409, _CHANGED)
            if self.schedule._is_legacy_completed_on(medication, day):
                self.schedule._materialize_missing_completion_slots(
                    medication, owner, day,
                    self.schedule._slot_statuses_for_medication(medication, day, completions.get(mid, [])),
                    completions.setdefault(mid, []),
                )
                self.db.flush()
            row = self.db.query(_MedicationCompletion).filter_by(
                patient_hash=owner, saved_medication_id=mid, schedule_date=day, slot_key=slot_key,
            ).with_for_update().populate_existing().first()
            if row is None:
                row = _MedicationCompletion(
                    patient_hash=owner, saved_medication_id=mid, schedule_date=day, slot_key=slot_key,
                    completed=False, completed_at=None,
                )
                self.db.add(row)
            apply_completion_report(self.db, row, status="taken", actual_taken_at=taken_at, source="photo")
            if day == today:
                self.db.flush()
                statuses = self.schedule._slot_statuses_for_medication(medication, day)
                medication.medication_status = bool(statuses) and all(statuses.values())
                medication.medication_status_date = day
        self.db.flush()
        if day != today:
            return []
        active, updated = self.schedule._load_day(owner, day)
        return self.schedule._queue_slot_completion_events(
            patient_hash=owner, schedule_date=day, target_slot_keys=[slot_key],
            active_medications=active, completion_rows_by_medication_id=updated,
            previous_slot_completion_states=before, alertable=True,
        )

    # 함수이름: _record_as_needed
    # 함수역할: 필요시 복용 1회를 사진 시각으로 기록한다. 기록 키는 작업 ID와 약에서 정해 재시도해도 같다.
    # 매개변수: owner: 본인; mid: 약; operation_id: 작업 ID; taken_at: 사진 시각; today: 오늘.
    # 반환값: 보호자 알림 outbox ID 또는 None.
    def _record_as_needed(self, owner, mid, operation_id, taken_at, *, today) -> int | None:  # noqa: ANN001
        row = _MedicationCompletion(
            patient_hash=owner, saved_medication_id=mid, schedule_date=taken_at.date(),
            slot_key=f"as_needed:{uuid5(_PHOTO_OPERATION_NAMESPACE, f'{operation_id}:{mid}')}",
            completed=False, completed_at=None,
        )
        self.db.add(row)
        apply_completion_report(self.db, row, status="taken", actual_taken_at=taken_at, source="photo")
        self.db.flush()
        if taken_at.date() != today:
            return None
        return queue_as_needed_taken_event(self.db, row)

    # 함수이름: _slot_keys
    # 함수역할: 약의 복용 시간대를 일정 규칙으로 읽는다. 필요시 복용 약은 시간대가 없다.
    # 매개변수: medication (_SavedMedication): 저장 약.
    # 반환값: 시간대 키 목록.
    def _slot_keys(self, medication: _SavedMedication) -> list[str]:
        if medication_dosing_mode(medication) == "as_needed":
            return []
        return list(self.policy.read_slot_keys(medication.schedule_slot_keys, medication.daily_frequency))

    # 함수이름: _reminder_times
    # 함수역할: 시간대별 알림 시각을 읽는다. 꺼 둔 알림도 저장한 시각을 쓰고, 없으면 앱 기본값이다.
    # 매개변수: owner (str): 본인.
    # 반환값: 시간대 키별 (시, 분).
    def _reminder_times(self, owner: str) -> dict[str, tuple[int, int]]:
        alarms = SetNotification(self.db).requestMedicationAlarm(owner)["data"]
        return {
            str(alarm["slot_key"]): (int(alarm["hour"]), int(alarm["minute"]))
            for alarm in alarms  # type: ignore[union-attr]
        }

    # 함수이름: _medications_json
    # 함수역할: 화면에 쓸 약 정보만 만든다. 사진은 저장한 약 사진, 없으면 카탈로그 사진이다.
    # 매개변수: by_id: 저장 약; ids: 포함할 약 ID; catalog: 품목별 카탈로그; item_seq_of: 약별 품목; decisions: 판단.
    # 반환값: 약 목록(ID 순).
    def _medications_json(self, by_id, ids, catalog, item_seq_of, decisions) -> list[dict[str, object]]:  # noqa: ANN001
        result = []
        for mid in sorted(set(ids)):
            medication = by_id.get(mid)
            if medication is None:
                continue
            entry: PillCatalogEntry | None = catalog.get(item_seq_of.get(mid, ""))
            image = safe_medication_image_url(medication.image_url) or (
                safe_medication_image_url(entry.image_url) if entry is not None else ""
            )
            decision = decisions.get(mid)
            result.append({
                "id": mid,
                "name": medication.item_name or "",
                "dosage": medication.dosage_per_time or "",
                "dosing_mode": medication_dosing_mode(medication),
                "slot_keys": self._slot_keys(medication),
                "image_url": image,
                "slot": (
                    {"schedule_date": decision.slot.day.isoformat(), "slot_key": decision.slot.key}
                    if decision is not None and decision.slot is not None else None
                ),
            })
        return result


# 클래스명: _Assigner
# 역할: 답, 각인, 모양·색 묶음, 질문 순서로 알약을 약에 배정한다(설계 문서 "알약과 약 맞추기").
# 속성: request: 알약·답; recordable: 지금 기록할 수 있는 약; decisions: 약별 판단;
#   capacity: 1회 알약 수; item_seq_of: 약별 품목; catalog: 품목별 카탈로그.
class _Assigner:
    def __init__(self, request, recordable, decisions, capacity, item_seq_of, catalog) -> None:  # noqa: ANN001
        self.pills = {pill.index: pill for pill in request.pills}
        self.answers = {answer.index: answer.medication_id for answer in request.answers}
        self.recordable = recordable
        self.decisions = decisions
        self.item_seq_of = item_seq_of
        self.catalog = catalog
        self.remaining = {mid: capacity[mid] for mid in recordable}
        self.rows: dict[int, dict[str, object]] = {}
        self.assigned: set[int] = set()

    # 함수이름: run
    # 함수역할: 네 단계로 배정한다.
    # 매개변수: 없음.
    # 반환값: (알약 줄, 배정한 약 ID 집합, 무시한 답의 알약 번호).
    def run(self) -> tuple[list[dict[str, object]], set[int], list[int]]:
        ignored: list[int] = []
        for index, mid in self.answers.items():
            if mid is None:
                self._row(index, "skipped")
            elif mid in self.recordable:
                self._take(index, mid, "answer")
            else:
                ignored.append(index)
        open_pills = [i for i in sorted(self.pills) if i not in self.rows]
        open_pills = self._by_imprint(open_pills)
        open_pills = self._by_look(open_pills)
        for index in open_pills:
            self._ask_or_explain(index)
        return [self.rows[i] for i in sorted(self.rows)], self.assigned, ignored

    def _row(self, index: int, status: str, medication_id: int | None = None, evidence: str | None = None,
             options: list[int] | None = None, lookalikes: list[int] | None = None) -> None:
        decision = self.decisions.get(medication_id) if medication_id is not None else None
        self.rows[index] = {
            "index": index, "status": status, "medication_id": medication_id, "evidence": evidence,
            "options": options or [], "lookalike_ids": lookalikes or [],
            "detail_at": _iso(decision.detail_at) if decision is not None and status in WARNING_STATUSES else None,
        }

    def _take(self, index: int, mid: int, evidence: str) -> None:
        if self.remaining.get(mid, 0) > 0:
            self.remaining[mid] -= 1
            self.assigned.add(mid)
            self._row(index, "matched", mid, evidence)
        else:
            self._row(index, "extra", mid, evidence)

    def _looks_like(self, pill: PhotoDosePill, mid: int) -> bool:
        entry = self.catalog.get(self.item_seq_of.get(mid, ""))
        return entry is not None and has_same_shape_and_colors(pill.shape, list(pill.colors), entry)

    def _available(self) -> list[int]:
        return [m for m in sorted(self.recordable) if self.remaining.get(m, 0) > 0]

    # 함수이름: _by_imprint
    # 함수역할: 각인이 보이는 알약은 각인이 맞은 기록 가능 약이 하나일 때만 자동으로 고른다.
    # 매개변수: open_pills: 남은 알약 번호.
    # 반환값: 아직 정하지 못한 알약 번호.
    def _by_imprint(self, open_pills: list[int]) -> list[int]:
        left = []
        for index in open_pills:
            pill = self.pills[index]
            if not pill.has_imprint:
                left.append(index)
                continue
            matches = [m for m in sorted(self.recordable) if self.item_seq_of.get(m) in set(pill.imprint_item_seqs)]
            own = [m for m in self.decisions if self.item_seq_of.get(m) in set(pill.imprint_item_seqs)]
            if len(matches) == 1:
                self._take(index, matches[0], "imprint")
            elif len(matches) > 1:
                self._row(index, "needs_choice", options=matches)
            elif own:
                # 각인이 내 약과 맞았지만 지금 기록할 수 없는 약이다(이미 드심 등). 닮은 다른 약을 묻지 않고 이유를 알린다.
                self._explain(index, own)
            else:
                left.append(index)
        return left

    # 함수이름: _by_look
    # 함수역할: 각인 없는 알약을 관찰한 모양·색으로 묶고, 같은 모양·색 약의 1회 복용량 합이 알약 수와
    #   같을 때만 자동으로 고른다.
    # 매개변수: open_pills: 남은 알약 번호.
    # 반환값: 아직 정하지 못한 알약 번호.
    def _by_look(self, open_pills: list[int]) -> list[int]:
        groups: dict[tuple[str, tuple[str, ...]], list[int]] = {}
        for index in open_pills:
            pill = self.pills[index]
            if pill.has_imprint or pill.shape in {"", "unknown"} or not pill.colors:
                continue
            groups.setdefault((pill.shape, tuple(sorted(set(pill.colors)))), []).append(index)
        left = list(open_pills)
        for members in groups.values():
            first = self.pills[members[0]]
            same_look = [
                m for m in self._available()
                if self._looks_like(first, m)
                and all(self.item_seq_of.get(m) in set(self.pills[i].item_seqs) for i in members)
            ]
            total = sum(self.remaining[m] for m in same_look)
            if total == 0:
                continue
            for index in members:
                left.remove(index)
            if total > len(members):
                for index in members:
                    self._row(index, "needs_choice", options=same_look, lookalikes=same_look)
                continue
            units = [m for m in same_look for _ in range(self.remaining[m])]
            for index, mid in zip(members, units):
                self._take(index, mid, "look")
            for index in members[len(units):]:
                self._row(index, "extra", same_look[0], "look")
        return left

    # 함수이름: _ask_or_explain
    # 함수역할: 남은 알약은 후보에 들었거나 모양·색이 같은 기록 가능 약이 있으면 묻고, 없으면 이유를 붙인다.
    #   이유는 각인이 맞았거나 후보이면서 모양·색이 같은 약에서만 고른다.
    # 매개변수: index: 알약 번호.
    # 반환값: 없음.
    def _ask_or_explain(self, index: int) -> None:
        pill = self.pills[index]
        candidates = set(pill.item_seqs)
        available = self._available()
        lookalike = [m for m in available if self._looks_like(pill, m)]
        options = [m for m in lookalike if self.item_seq_of.get(m) in candidates] + \
            [m for m in lookalike if self.item_seq_of.get(m) not in candidates] + \
            [m for m in available if self.item_seq_of.get(m) in candidates and m not in lookalike]
        if options:
            self._row(index, "needs_choice", options=options, lookalikes=lookalike)
            return
        strong = [
            m for m in self.decisions
            if self.item_seq_of.get(m) and (
                self.item_seq_of[m] in set(pill.imprint_item_seqs)
                or (self.item_seq_of[m] in candidates and self._looks_like(pill, m))
            )
        ]
        self._explain(index, strong)

    # 함수이름: _explain
    # 함수역할: 기록하지 않는 알약에 이유를 붙인다. 근거가 있는 내 약 가운데 정해진 양을 넘긴 약, 최근·오늘 이미 드신 약,
    #   아직 때가 아닌 약, 시간대를 알 수 없는 약, 오늘 먹는 날이 아닌 약 순으로 고른다.
    # 매개변수: index: 알약 번호; strong: 근거가 있는 내 약 ID.
    # 반환값: 없음.
    def _explain(self, index: int, strong: list[int]) -> None:
        full = [m for m in strong if m in self.recordable]
        if full:
            self._row(index, "extra", full[0])
            return
        for status in ("recently_taken", "already_taken", "too_early", "unclear_slot", "not_due"):
            for mid in strong:
                if self.decisions[mid].status == status:
                    self._row(index, status, mid)
                    return
        self._row(index, "unknown")


# 함수이름: _aware
# 함수역할: 저장된 UTC 기준 naive 시각을 서비스 시간대 시각으로 바꾼다.
# 매개변수: value (datetime | None): 저장 값; now (datetime): 시간대 기준.
# 반환값: 시간대가 있는 datetime 또는 None.
def _aware(value: datetime | None, now: datetime) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(now.tzinfo)


# 함수이름: _iso
# 함수역할: 시각을 ISO 문자열로 바꾼다.
# 매개변수: value (datetime | None).
# 반환값: 문자열 또는 None.
def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


# 함수이름: _normalized_write
# 함수역할: 앱이 보낸 기대 기록을 계산 결과와 같은 모양으로 맞춘다.
# 매개변수: expected (dict): 앱의 기록 묶음.
# 반환값: 정렬한 dict.
def _normalized_write(expected: dict) -> dict:
    return {
        "groups": sorted(
            (
                {"schedule_date": str(g["schedule_date"]), "slot_key": g["slot_key"],
                 "medication_ids": sorted(g["medication_ids"])}
                for g in expected.get("groups", [])
            ),
            key=lambda g: (g["schedule_date"], SLOT_ORDER.index(g["slot_key"])),
        ),
        "as_needed_medication_ids": sorted(expected.get("as_needed_medication_ids", [])),
        "regimen_revisions": {
            str(k): int(v) for k, v in sorted(expected.get("regimen_revisions", {}).items(), key=lambda kv: int(kv[0]))
        },
    }
