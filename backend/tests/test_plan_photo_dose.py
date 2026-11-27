# 파일명: test_plan_photo_dose.py
# 역할: 사진으로 복용 기록의 알약 배정, 약별 시간대, 최근 복용 간격, 토큰과 한 번에 기록하는 확인을
#   설계 문서(docs/Photo Dose Recording.md, 세 번째 판)의 사례로 검증한다.
"""Photos record only what the evidence and the clock justify; everything else is asked or explained."""
from collections.abc import Iterator
from datetime import date, datetime, timedelta, timezone
from uuid import uuid4
from zoneinfo import ZoneInfo

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from controls.identify_pill_control import has_same_shape_and_colors
from controls.plan_photo_dose_control import PlanPhotoDose, dose_capacity
from core.database import Base
from entities.medication_alarm_entity import _MedicationAlarm
from entities.medication_care_entity import _MedicationCareOperation
from entities.medication_completion_entity import _MedicationCompletion
from entities.pill_identification_entity import PillCatalogEntry, PillIdentificationReference
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from schemas.photo_dose import PhotoDoseConfirmRequest, PhotoDosePlanRequest

SEOUL = ZoneInfo("Asia/Seoul")
TODAY = date(2026, 11, 27)
YESTERDAY = TODAY - timedelta(days=1)
OWNER = "photo-owner"


@pytest.fixture
def db() -> Iterator[Session]:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as session:
        session.add_all([_UserAccount(user_hash=OWNER), _UserAccount(user_hash="someone-else")])
        session.commit()
        yield session
    engine.dispose()


# 함수이름: medicine
# 함수역할: 약 하나와 그 카탈로그 행(모양·색)을 저장한다.
# 매개변수: db: 세션; item_seq: 품목; slots: 시간대; look: (모양, 색) 카탈로그 값; 나머지는 저장 필드.
# 반환값: 저장한 약 ID.
def medicine(
    db: Session, item_seq: str | None, slots: list[str], *, look: tuple[str, str] = ("원형", "하양"),
    dosage: str = "1정", owner: str = OWNER, dosing_mode: str = "scheduled", frequency: str | None = None,
) -> int:
    row = _SavedMedication(
        patient_hash=owner, item_seq=item_seq, item_name=f"약 {item_seq}",
        created_date=TODAY - timedelta(days=3), prescription_date=TODAY - timedelta(days=3), total_days="30",
        daily_frequency=frequency or str(len(slots) or 1), dosage_per_time=dosage,
        schedule_slot_keys=str(slots).replace("'", '"'), dosing_mode=dosing_mode,
    )
    db.add(row)
    if item_seq and db.get(PillIdentificationReference, item_seq) is None:
        db.add(PillIdentificationReference(item_seq=item_seq, item_name=row.item_name, shape=look[0], color_primary=look[1]))
    db.commit()
    return int(row.id)


def at(clock: str, day: date = TODAY) -> datetime:
    return datetime.combine(day, datetime.strptime(clock, "%H:%M").time(), tzinfo=SEOUL)


# 함수이름: taken
# 함수역할: 한 시간대 기록을 저장한다. 복용 시각과 기록 시각은 서비스 시간대 "HH:MM"이다.
def taken(
    db: Session, medication_id: int, slot: str, day: date = TODAY, *, actual: str | None = None,
    recorded: str | None = None, status: str = "taken",
) -> None:
    def utc(clock: str | None) -> datetime | None:
        return at(clock, day).astimezone(timezone.utc).replace(tzinfo=None) if clock else None
    db.add(_MedicationCompletion(
        patient_hash=OWNER, saved_medication_id=medication_id, schedule_date=day, slot_key=slot,
        completed=status == "taken", report_status=status, actual_taken_at=utc(actual),
        completed_at=utc(recorded or actual) if status == "taken" else None,
    ))
    db.commit()


def alarm(db: Session, slot: str, hour: int, minute: int = 0) -> None:
    db.add(_MedicationAlarm(patient_hash=OWNER, slot_key=slot, hour=hour, minute=minute, enabled=False))
    db.commit()


# 함수이름: pill
# 함수역할: 알약 하나의 요청 값을 만든다. 각인이 맞은 후보를 주면 각인이 보인 알약이다.
def pill(index: int, *seqs: str, imprint: tuple[str, ...] = (), look: tuple[str, list[str]] = ("round", ["white"]),
         has_imprint: bool | None = None) -> dict:
    return {
        "index": index, "item_seqs": list(seqs) + [s for s in imprint if s not in seqs],
        "imprint_item_seqs": list(imprint), "has_imprint": bool(imprint) if has_imprint is None else has_imprint,
        "shape": look[0], "colors": look[1],
    }


def planner(db: Session, now: datetime) -> PlanPhotoDose:
    return PlanPhotoDose(db, clock=lambda: now)


def plan(db: Session, when: str | datetime, pills: list[dict], **request: object) -> dict:
    now = when if isinstance(when, datetime) else at(when)
    return planner(db, now).plan(OWNER, PhotoDosePlanRequest.model_validate({"pills": pills, **request}))


def statuses(result: dict) -> dict[int, tuple[str, int | None]]:
    return {row["index"]: (row["status"], row["medication_id"]) for row in result["pills"]}


def group_map(result: dict) -> dict[str, list[int]]:
    return {g["slot_key"]: g["medication_ids"] for g in result["groups"]}


# --- matching -----------------------------------------------------------------------------------


def test_imprint_matches_pick_the_morning_set_whatever_the_candidate_order(db: Session) -> None:
    ids = [medicine(db, seq, ["morning", "evening"]) for seq in ("A1", "B1", "C1", "D1")]
    result = plan(db, "08:20", [
        pill(1, "X9", "Y9", imprint=("A1",)), pill(2, imprint=("B1",)), pill(3, "Z9", imprint=("C1",)),
        pill(4, "Q9", "R9", "S9", imprint=("D1",)),
    ])
    assert group_map(result) == {"morning": sorted(ids)}
    assert result["groups"][0]["timing"] == "on_time"
    assert result["ready"] is True
    assert {row["evidence"] for row in result["pills"]} == {"imprint"}


def test_two_plain_pills_and_two_same_look_medicines_due_are_recorded_together(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    b = medicine(db, "B1", ["morning"])
    result = plan(db, "08:00", [pill(1, "A1", "B1", "V9"), pill(2, "B1", "A1", "V9")])
    assert group_map(result) == {"morning": sorted([a, b])}
    assert {row["evidence"] for row in result["pills"]} == {"look"}


def test_one_plain_pill_with_two_same_look_medicines_due_is_asked(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    b = medicine(db, "B1", ["morning"])
    result = plan(db, "08:00", [pill(1, "A1", "B1")])
    assert statuses(result)[1] == ("needs_choice", None)
    assert result["pills"][0]["options"] == [a, b]
    assert result["ready"] is False
    answered = plan(db, "08:00", [pill(1, "A1", "B1")], answers=[{"index": 1, "medication_id": b}],
                    plan_token=result["plan_token"])
    assert group_map(answered) == {"morning": [b]}
    assert answered["groups"][0]["missing_medication_ids"] == [a]


def test_visible_imprint_that_matched_nothing_is_never_auto_selected(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    # 각인이 보이는데 내 약 후보의 각인과 맞지 않았다: 모양·색이 같아도 자동으로 고르지 않는다.
    result = plan(db, "08:00", [pill(1, "A1", has_imprint=True)])
    assert statuses(result)[1] == ("needs_choice", None)
    assert result["pills"][0]["lookalike_ids"] == [a]


def test_candidate_without_the_same_look_is_asked_not_picked(db: Session) -> None:
    pink = medicine(db, "P1", ["morning"], look=("원형", "분홍"))
    result = plan(db, "08:00", [pill(1, "P1")])
    assert statuses(result)[1] == ("needs_choice", None)
    assert result["pills"][0]["options"] == [pink]
    assert result["pills"][0]["lookalike_ids"] == []


def test_lookalike_outside_the_candidates_is_offered_and_no_means_not_recorded(db: Session) -> None:
    white = medicine(db, "A1", ["morning"])
    result = plan(db, "08:00", [pill(1, "Z9")])
    assert result["pills"][0]["options"] == [white] and result["pills"][0]["lookalike_ids"] == [white]
    no = plan(db, "08:00", [pill(1, "Z9")], answers=[{"index": 1, "medication_id": None}], plan_token=result["plan_token"])
    assert statuses(no)[1] == ("skipped", None)
    assert no["ready"] is False and no["write"]["groups"] == []


def test_answers_are_assigned_first_and_capacity_marks_the_other_pill_extra(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    result = plan(db, "08:00", [pill(1, "A1"), pill(2, "Z9")], answers=[{"index": 2, "medication_id": a}])
    assert statuses(result) == {1: ("extra", a), 2: ("matched", a)}


def test_more_pills_than_one_dose_are_extra_and_two_tablet_doses_are_not(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    result = plan(db, "08:00", [pill(1, "A1"), pill(2, "A1")])
    assert sorted(s for s, _ in statuses(result).values()) == ["extra", "matched"]
    assert group_map(result) == {"morning": [a]}
    medicine(db, "B1", ["morning"], look=("장방형", "하양"), dosage="2정")
    two = plan(db, "08:00", [pill(1, "B1", look=("oblong", ["white"])), pill(2, "B1", look=("oblong", ["white"]))])
    assert [s for s, _ in statuses(two).values()] == ["matched", "matched"]


def test_dose_capacity_reads_counts_not_strengths() -> None:
    assert dose_capacity("1정") == 1 and dose_capacity("2캡슐") == 2 and dose_capacity("2") == 2
    assert dose_capacity("0.5정") == 1 and dose_capacity("500mg") == 1 and dose_capacity("2.5mg") == 1
    assert dose_capacity(None) == 1 and dose_capacity("1~2정") == 2


def test_other_accounts_medicines_never_match(db: Session) -> None:
    medicine(db, "A1", ["morning"], owner="someone-else")
    assert statuses(plan(db, "08:00", [pill(1, imprint=("A1",))]))[1] == ("unknown", None)


def test_answers_outside_what_can_be_recorded_are_ignored(db: Session) -> None:
    medicine(db, "A1", ["morning"])
    evening = medicine(db, "E1", ["evening"])
    result = plan(db, "08:00", [pill(1, imprint=("A1",))], answers=[{"index": 1, "medication_id": evening}])
    assert result["ignored_answer_indexes"] == [1]
    assert evening not in group_map(result).get("morning", [])


# --- slots --------------------------------------------------------------------------------------


def test_late_dose_flows_back_to_the_unhandled_morning_until_the_lunch_reminder(db: Session) -> None:
    alarm(db, "lunch", 12, 30)
    a = medicine(db, "A1", ["morning", "lunch"])
    assert group_map(plan(db, "10:00", [pill(1, imprint=("A1",))])) == {"morning": [a]}
    assert group_map(plan(db, "12:40", [pill(1, imprint=("A1",))])) == {"lunch": [a]}


def test_each_medicine_goes_to_its_own_slot_in_one_photo(db: Session) -> None:
    alarm(db, "lunch", 12, 30)
    a = medicine(db, "A1", ["morning", "lunch"])
    b = medicine(db, "B1", ["morning"])
    result = plan(db, "12:40", [pill(1, imprint=("A1",)), pill(2, imprint=("B1",))])
    assert group_map(result) == {"morning": [b], "lunch": [a]}
    timings = {g["slot_key"]: g["timing"] for g in result["groups"]}
    assert timings == {"morning": "late", "lunch": "on_time"}
    # 점심 A를 막 기록했으므로 5분 뒤 같은 사진은 남은 아침 칸이 있어도 최근 복용으로 막힌다.
    taken(db, a, "lunch", actual="12:40")
    taken(db, b, "morning", actual="12:40")
    again = plan(db, "12:45", [pill(1, imprint=("A1",))])
    assert statuses(again)[1] == ("recently_taken", a)
    assert again["pills"][0]["detail_at"] == at("12:40").isoformat()


def test_photo_of_an_already_taken_multi_slot_medicine_is_not_recorded_for_later(db: Session) -> None:
    a = medicine(db, "A1", ["morning", "evening"])
    taken(db, a, "morning", actual="08:10")
    # 방금(2시간 안) 먹은 약은 다음 시각보다 "8:10에 이미 드셨어요"를 먼저 알린다(폰 테스트에서 확인).
    result = plan(db, "09:00", [pill(1, imprint=("A1",))])
    assert statuses(result)[1] == ("recently_taken", a)
    assert result["pills"][0]["detail_at"] == at("08:10").isoformat()
    # 간격이 지나면 다음 시각을 알린다.
    later = plan(db, "10:30", [pill(1, imprint=("A1",))])
    assert statuses(later)[1] == ("too_early", a)
    assert later["pills"][0]["detail_at"] == at("18:00").isoformat()


def test_early_dose_needs_enough_rest_since_the_previous_one(db: Session) -> None:
    a = medicine(db, "A1", ["morning", "lunch"])
    taken(db, a, "morning", actual="08:10")
    # 12시 점심, 8:10 복용: 10:15는 간격(4시간)의 60%가 안 지났다.
    assert statuses(plan(db, "10:15", [pill(1, imprint=("A1",))]))[1] == ("too_early", a)
    early = plan(db, "10:40", [pill(1, imprint=("A1",))])
    assert group_map(early) == {"lunch": [a]}
    assert early["groups"][0]["timing"] == "early"


def test_spacing_uses_the_real_dose_time_not_a_late_tap(db: Session) -> None:
    a = medicine(db, "A1", ["morning", "evening"])
    # 아침 약을 저녁 18:05에 뒤늦게 체크했다. 복용 시각이 없으면 아침 창의 끝(14:00)을 쓴다.
    taken(db, a, "morning", recorded="18:05")
    assert group_map(plan(db, "19:30", [pill(1, imprint=("A1",))])) == {"evening": [a]}


def test_spacing_is_capped_by_half_the_gap_between_close_reminders(db: Session) -> None:
    alarm(db, "evening", 20)
    alarm(db, "bedtime", 21, 30)
    a = medicine(db, "A1", ["evening", "bedtime"])
    taken(db, a, "evening", actual="20:00")
    # 간격 90분의 절반인 45분이 지났으므로 자기 전 약을 막지 않는다.
    assert group_map(plan(db, "21:35", [pill(1, imprint=("A1",))])) == {"bedtime": [a]}


def test_skipped_slot_counts_as_handled_but_a_snoozed_reminder_does_not(db: Session) -> None:
    alarm(db, "lunch", 12, 30)
    a = medicine(db, "A1", ["morning", "lunch"])
    assert group_map(plan(db, "08:10", [pill(1, imprint=("A1",))])) == {"morning": [a]}
    taken(db, a, "morning", status="skipped")
    assert group_map(plan(db, "10:00", [pill(1, imprint=("A1",))])) == {"lunch": [a]}


def test_unused_slot_does_not_end_the_window_and_the_window_is_capped(db: Session) -> None:
    a = medicine(db, "A1", ["morning", "evening"])
    on_time = plan(db, "13:00", [pill(1, imprint=("A1",))])
    assert group_map(on_time) == {"morning": [a]} and on_time["groups"][0]["timing"] == "on_time"
    late = plan(db, "14:30", [pill(1, imprint=("A1",))])
    # 14시에 아침 창이 닫혔고 저녁(18시)은 3시간 넘게 남았다: 어느 쪽인지 알 수 없다.
    assert statuses(late)[1] == ("unclear_slot", a)


def test_once_daily_morning_medicine_taken_at_night_is_recorded_as_late(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    result = plan(db, "23:00", [pill(1, imprint=("A1",))])
    assert group_map(result) == {"morning": [a]} and result["groups"][0]["timing"] == "late"


def test_after_midnight_the_bedtime_dose_belongs_to_yesterday_only_inside_its_window(db: Session) -> None:
    a = medicine(db, "A1", ["bedtime"])
    night = plan(db, "00:30", [pill(1, imprint=("A1",))])
    assert night["groups"][0]["schedule_date"] == YESTERDAY.isoformat()
    assert night["groups"][0]["timing"] == "overnight"
    # 22시 창은 04시에 닫힌다. 04:10의 같은 약은 오늘 밤 약이므로 기록하지 않는다.
    assert statuses(plan(db, "04:10", [pill(1, imprint=("A1",))]))[1] == ("too_early", a)


def test_bedtime_reminder_after_midnight_belongs_to_the_night_before(db: Session) -> None:
    alarm(db, "bedtime", 0, 30)
    a = medicine(db, "A1", ["bedtime"])
    result = plan(db, "23:50", [pill(1, imprint=("A1",))])
    assert group_map(result) == {"bedtime": [a]}
    assert result["groups"][0]["schedule_date"] == TODAY.isoformat() and result["groups"][0]["timing"] == "early"


def test_slots_with_the_same_reminder_time_share_one_window(db: Session) -> None:
    alarm(db, "lunch", 8)
    a = medicine(db, "A1", ["morning"])
    b = medicine(db, "B1", ["lunch"], look=("원형", "분홍"))
    result = plan(db, "08:10", [pill(1, imprint=("A1",)), pill(2, imprint=("B1",), look=("round", ["pink"]))])
    assert group_map(result) == {"morning": [a], "lunch": [b]}
    assert {g["timing"] for g in result["groups"]} == {"on_time"}


def test_user_reminder_order_wins_over_slot_names(db: Session) -> None:
    alarm(db, "morning", 9)
    alarm(db, "lunch", 7)
    a = medicine(db, "A1", ["morning", "lunch"])
    assert group_map(plan(db, "08:00", [pill(1, imprint=("A1",))])) == {"lunch": [a]}


def test_not_due_and_unknown_pills_are_explained(db: Session) -> None:
    other_day = medicine(db, "W1", ["morning"], frequency="격일")
    db.get(_SavedMedication, other_day).prescription_date = YESTERDAY
    db.commit()
    result = plan(db, "08:00", [pill(1, imprint=("W1",)), pill(2, "Z9", look=("unknown", []))])
    assert statuses(result) == {1: ("not_due", other_day), 2: ("unknown", None)}


# --- as-needed ----------------------------------------------------------------------------------


def test_as_needed_medicine_is_recorded_once_and_spaced_by_four_hours(db: Session) -> None:
    prn = medicine(db, "P1", [], dosing_mode="as_needed", look=("장방형", "하양"))
    photo = pill(1, imprint=("P1",), look=("oblong", ["white"]))
    result = plan(db, "15:00", [photo])
    assert result["write"]["as_needed_medication_ids"] == [prn] and result["groups"] == []
    assert result["as_needed"] == [{"medication_id": prn, "taken_today": 0, "last_taken_at": None}]
    taken(db, prn, "as_needed:5e1f3c2a-4d6b-4e8f-9a1b-2c3d4e5f6a7b", actual="14:00")
    assert statuses(plan(db, "15:00", [photo]))[1] == ("recently_taken", prn)


def test_scheduled_dose_of_the_same_product_blocks_an_as_needed_photo(db: Session) -> None:
    scheduled = medicine(db, "T1", ["bedtime"])
    prn = _SavedMedication(
        patient_hash=OWNER, item_seq="T1", item_name="필요시 T1", created_date=TODAY - timedelta(days=3),
        total_days="30", daily_frequency="1", dosage_per_time="1정", schedule_slot_keys="[]", dosing_mode="as_needed",
    )
    db.add(prn)
    db.commit()
    taken(db, scheduled, "bedtime", actual="22:00")
    result = plan(db, "23:00", [pill(1, imprint=("T1",))])
    assert result["write"]["as_needed_medication_ids"] == []


# --- token and confirm ----------------------------------------------------------------------------


def test_the_plan_token_freezes_the_photo_time(db: Session) -> None:
    alarm(db, "lunch", 12, 30)
    medicine(db, "A1", ["morning", "lunch"])
    first = plan(db, "12:29", [pill(1, imprint=("A1",))])
    assert group_map(first).keys() == {"morning"}
    later = plan(db, "12:35", [pill(1, imprint=("A1",))], plan_token=first["plan_token"])
    assert group_map(later).keys() == {"morning"}
    with pytest.raises(HTTPException) as expired:
        plan(db, "12:45", [pill(1, imprint=("A1",))], plan_token=first["plan_token"])
    assert expired.value.status_code == 409
    forged = first["plan_token"][:-1] + ("0" if first["plan_token"][-1] != "0" else "1")
    with pytest.raises(HTTPException):
        plan(db, "12:30", [pill(1, imprint=("A1",))], plan_token=forged)


def confirm_request(result: dict, pills: list[dict], **extra: object) -> PhotoDoseConfirmRequest:
    return PhotoDoseConfirmRequest.model_validate({
        "pills": pills, "plan_token": result["plan_token"], "operation_id": str(uuid4()),
        "expected": result["write"], **extra,
    })


def test_confirm_records_every_slot_and_as_needed_dose_once_at_the_photo_time(db: Session) -> None:
    alarm(db, "lunch", 12, 30)
    a = medicine(db, "A1", ["morning", "lunch"])
    b = medicine(db, "B1", ["morning"], look=("원형", "분홍"))
    prn = medicine(db, "P1", [], dosing_mode="as_needed", look=("장방형", "하양"))
    pills = [pill(1, imprint=("A1",)), pill(2, imprint=("B1",), look=("round", ["pink"])),
             pill(3, imprint=("P1",), look=("oblong", ["white"]))]
    result = plan(db, "12:40", pills)
    request = confirm_request(result, pills)
    response, events = planner(db, at("12:42")).confirm(OWNER, request)
    assert response == {"success": True, "operation_id": str(request.operation_id), "taken_at": at("12:40").isoformat()}
    # 영수증에는 약 정보를 남기지 않는다.
    assert db.query(_MedicationCareOperation).one().medication_id is None
    rows = {(r.saved_medication_id, r.slot_key.split(":")[0]): r for r in db.query(_MedicationCompletion).all()}
    assert set(rows) == {(a, "lunch"), (b, "morning"), (prn, "as_needed")}
    expected_time = at("12:40").astimezone(timezone.utc).replace(tzinfo=None)
    assert {r.actual_taken_at for r in rows.values()} == {expected_time}
    assert all(r.completed and r.report_status == "taken" for r in rows.values())
    assert events  # 오늘 기록이므로 보호자 알림 이벤트가 있다.
    replay, replay_events = planner(db, at("12:43")).confirm(OWNER, request)
    assert replay == response and replay_events == []
    assert db.query(_MedicationCompletion).count() == 3
    assert db.query(_MedicationCareOperation).count() == 1


def test_confirm_refuses_when_the_write_set_changed(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    pills = [pill(1, imprint=("A1",))]
    result = plan(db, "08:00", pills)
    taken(db, a, "morning", actual="08:01")  # 다른 기기가 먼저 기록했다.
    with pytest.raises(HTTPException) as changed:
        planner(db, at("08:02")).confirm(OWNER, confirm_request(result, pills))
    assert changed.value.status_code == 409
    assert db.query(_MedicationCareOperation).count() == 0


def test_confirm_refuses_a_reused_operation_id_with_another_request(db: Session) -> None:
    medicine(db, "A1", ["morning"])
    pills = [pill(1, imprint=("A1",))]
    result = plan(db, "08:00", pills)
    request = confirm_request(result, pills)
    planner(db, at("08:01")).confirm(OWNER, request)
    other = request.model_copy(update={"answers": []})
    other_payload = other.model_dump(mode="json")
    other_payload["pills"][0]["shape"] = "oval"
    with pytest.raises(HTTPException) as reused:
        planner(db, at("08:02")).confirm(OWNER, PhotoDoseConfirmRequest.model_validate(other_payload))
    assert reused.value.status_code == 409


def test_confirming_yesterdays_bedtime_sends_no_caregiver_alert(db: Session) -> None:
    medicine(db, "A1", ["bedtime"])
    pills = [pill(1, imprint=("A1",))]
    result = plan(db, "00:30", pills)
    _, events = planner(db, at("00:31")).confirm(OWNER, confirm_request(result, pills))
    assert db.query(_MedicationCompletion).one().schedule_date == YESTERDAY
    assert events == []


# --- validation and helpers -----------------------------------------------------------------------


def test_request_rejects_duplicate_indexes_bad_labels_and_foreign_imprint_matches() -> None:
    with pytest.raises(ValidationError):
        PhotoDosePlanRequest.model_validate({"pills": [{"index": 1}, {"index": 1}]})
    with pytest.raises(ValidationError):
        PhotoDosePlanRequest.model_validate({"pills": [{"index": 1}], "answers": [{"index": 2, "medication_id": 1}]})
    with pytest.raises(ValidationError):
        PhotoDosePlanRequest.model_validate({"pills": [{"index": 1, "shape": "Round<script>"}]})
    with pytest.raises(ValidationError):
        PhotoDosePlanRequest.model_validate({"pills": [{"index": 1, "item_seqs": ["A1"], "imprint_item_seqs": ["B1"]}]})


def test_shape_and_colour_lookalike_requires_the_full_colour_set() -> None:
    two_tone = PillCatalogEntry(item_seq="A1", item_name="x", shape="원형", color_primary="하양", color_secondary="분홍")
    assert has_same_shape_and_colors("round", ["white", "pink"], two_tone)
    assert not has_same_shape_and_colors("round", ["white"], two_tone)
    assert not has_same_shape_and_colors("oval", ["white", "pink"], two_tone)
    assert not has_same_shape_and_colors("unknown", ["white", "pink"], two_tone)
    repeated = PillCatalogEntry(item_seq="B1", item_name="y", shape="원형", color_primary="하양", color_secondary="하양")
    assert has_same_shape_and_colors("round", ["white"], repeated)
    ellipse = PillCatalogEntry(item_seq="C1", item_name="z", shape="타원형", color_primary="분홍")
    assert has_same_shape_and_colors("oblong", ["pink"], ellipse)
    assert not has_same_shape_and_colors("round", ["pink"], ellipse)


def test_plain_back_of_an_extra_tablet_on_an_adjacent_shape_is_extra_not_unknown(db: Session) -> None:
    # 폰 테스트: 카탈로그 타원형 애니펜정의 두 알이 모두 장방형으로 읽혔다. 각인 면은 그 약으로 고르고,
    # 각인 없는 면은 "내 약이 아닌 알약"이 아니라 정해진 양보다 많이 찍힌 같은 약이다.
    a = medicine(db, "A1", ["morning"], look=("타원형", "분홍"))
    result = plan(db, "08:00", [
        # 각인 없는 알약은 동점 후보를 많이 받으므로 그 약도 후보에 든다.
        pill(1, "A1", look=("oblong", ["pink"]), has_imprint=False),
        pill(2, imprint=("A1",), look=("oblong", ["pink"])),
    ])
    assert statuses(result) == {1: ("extra", a), 2: ("matched", a)}


# --- regressions from the implementation review ---------------------------------------------------


def test_spacing_uses_the_gap_before_the_slot_being_recorded(db: Session) -> None:
    alarm(db, "bedtime", 19)
    a = medicine(db, "A1", ["morning", "lunch", "evening", "bedtime"])
    taken(db, a, "morning", actual="11:50")
    # 저녁 18시와 자기 전 19시가 가까워도 점심 기록의 간격은 아침~점심(4시간)에서 정한다.
    assert statuses(plan(db, "12:25", [pill(1, imprint=("A1",))]))[1] == ("recently_taken", a)


def test_imprint_of_an_already_taken_medicine_warns_instead_of_asking_about_a_lookalike(db: Session) -> None:
    a = medicine(db, "A1", ["morning"])
    medicine(db, "B1", ["morning"])
    taken(db, a, "morning", actual="08:05")
    result = plan(db, "08:40", [pill(1, imprint=("A1",))])
    assert statuses(result)[1] == ("already_taken", a)
    assert result["pills"][0]["options"] == []


def test_a_late_upload_of_yesterdays_bedtime_does_not_block_this_morning(db: Session) -> None:
    a = medicine(db, "A1", ["morning", "bedtime"])
    # 어제 자기 전 체크가 오늘 07:50에야 올라왔다(복용 시각 없음). 어제 창은 04시에 닫혔다.
    db.add(_MedicationCompletion(
        patient_hash=OWNER, saved_medication_id=a, schedule_date=YESTERDAY, slot_key="bedtime",
        completed=True, completed_at=at("07:50").astimezone(timezone.utc).replace(tzinfo=None),
    ))
    db.commit()
    assert group_map(plan(db, "08:10", [pill(1, imprint=("A1",))])) == {"morning": [a]}


def test_a_retry_that_loses_the_commit_race_gets_the_first_result(db: Session, monkeypatch: pytest.MonkeyPatch) -> None:
    medicine(db, "A1", ["morning"])
    pills = [pill(1, imprint=("A1",))]
    result = plan(db, "08:00", pills)
    request = confirm_request(result, pills)
    first, _ = planner(db, at("08:01")).confirm(OWNER, request)
    stored_id = db.query(_MedicationCareOperation).one().id
    real_query = Session.query
    hidden = {"done": False}

    # 두 번째(같은) 요청이 영수증을 확인할 때는 첫 요청이 아직 커밋 전이었던 것처럼 만든다.
    def hide_receipt_once(self, *entities, **kwargs):  # noqa: ANN001, ANN002, ANN003
        query = real_query(self, *entities, **kwargs)
        if entities and entities[0] is _MedicationCareOperation and not hidden["done"]:
            hidden["done"] = True
            return query.filter(_MedicationCareOperation.id != stored_id)
        return query

    computed = {"ready": True, "write": result["write"]}
    monkeypatch.setattr(Session, "query", hide_receipt_once)
    monkeypatch.setattr(PlanPhotoDose, "_compute", lambda self, owner, req, as_of: computed)
    monkeypatch.setattr(PlanPhotoDose, "_record_slot", lambda self, *a, **k: [])
    second, events = planner(db, at("08:02")).confirm(OWNER, request)
    assert second == first and events == []
    assert db.query(_MedicationCareOperation).count() == 1


def test_regimen_revision_keys_must_be_medicine_ids() -> None:
    with pytest.raises(ValidationError):
        PhotoDoseConfirmRequest.model_validate({
            "pills": [{"index": 1}], "plan_token": "x" * 20, "operation_id": str(uuid4()),
            "expected": {"groups": [], "as_needed_medication_ids": [], "regimen_revisions": {"x": 0}},
        })


def test_a_photographed_medicine_with_a_warning_is_not_listed_as_missing(db: Session) -> None:
    # 폰 테스트: 아침에 먹은 B를 점심 사진에 다시 찍으면 "이미 드셨어요"로 막히는데, 같은 B가
    # "아직 안 찍힌 점심 약"에도 나왔다. 사진에 있는 약은 안 찍힌 약 목록에 넣지 않는다.
    alarm(db, "lunch", 12, 30)
    a = medicine(db, "A1", ["morning", "lunch"])
    b = medicine(db, "B1", ["morning", "lunch"])
    c = medicine(db, "C1", ["morning", "lunch"])
    taken(db, a, "morning", actual="08:05")
    taken(db, b, "morning", actual="12:00")
    taken(db, c, "morning", actual="08:05")
    result = plan(db, "12:40", [pill(1, imprint=("A1",)), pill(2, imprint=("B1",))])
    assert statuses(result) == {1: ("matched", a), 2: ("recently_taken", b)}
    assert group_map(result) == {"lunch": [a]}
    assert result["groups"][0]["missing_medication_ids"] == [c]


def test_a_just_taken_medicine_is_recently_taken_not_unclear(db: Session) -> None:
    # 폰 테스트: 아침을 놓치고 점심(12:30)에 A를 먹은 직후 다시 찍으면, 아침은 지났고 저녁은 멀어
    # "언제 드실 약인지 알 수 없어요. 일정에서 직접 기록해 주세요"가 나와 아침 칸에 또 기록하게 했다.
    alarm(db, "lunch", 12, 30)
    a = medicine(db, "A1", ["morning", "lunch", "evening"])
    b = medicine(db, "B1", ["morning", "evening"])
    taken(db, a, "lunch", actual="12:35")
    result = plan(db, "12:40", [pill(1, imprint=("A1",)), pill(2, imprint=("B1",))])
    assert statuses(result) == {1: ("recently_taken", a), 2: ("unclear_slot", b)}
    assert result["pills"][0]["detail_at"] == at("12:35").isoformat()

