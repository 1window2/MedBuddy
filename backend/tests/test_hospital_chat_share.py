"""병원 공유의 신뢰 경계·공휴일 시간표·권한·재전송 및 삭제를 검증한다."""

from dataclasses import replace
from datetime import UTC, date, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock
from xml.etree import ElementTree as ET

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from api import chat_router, route_support
from boundaries.hospital_api_boundary import NationalEmergencyMedicalCenterHospitalAPI, HospitalApiUnavailableError
from controls.check_nearby_hospital_control import CheckNearbyHospital
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from core.database import Base
from entities.chat_message_entity import _ChatMessage
from entities.nearby_hospital_entity import HospitalDetails, HospitalLocationRecord
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from schemas.chat import ChatMessageCreate


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.fixture
def chat():
    """실제 사용자·대화와 분리된 DB에서 환자와 보호자를 연결한다."""
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine)() as db:
        links = LinkPatientCaregiver(db)
        code = links.generatePatientHash("patient-a")["data"]["patient_code"]
        link_id = links.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"]
        yield ManageLinkedChat(db), link_id
    engine.dispose()


def payload(**changes):
    """클라이언트는 병원 ID와 날짜만 보낸다."""
    return ChatMessageCreate(**dict({
        "client_message_id": "hospital_share_001", "body": "병원 정보를 공유해요.",
        "message_kind": "hospital_share", "hospital_id": "A123", "hospital_schedule_date": "2026-10-05",
    }, **changes))


def context():
    return {"hospital_id": "A123", "name": "서버 확인 병원", "address": "서울",
            "telephone": "02-000-0000", "latitude": 37.55, "longitude": 126.92,
            "departments": ["내과"], "schedule_date": "2026-10-05", "today_hours": "10:00 - 13:00",
            "source_updated_at": "2026-09-28T01:00:00+00:00"}


async def send(chat, monkeypatch, *, sender="patient-a", request=None, provider=None):
    """외부 통신만 대역으로 바꾸고 실제 저장·멱등 처리 경로를 실행한다."""
    control, link_id = chat
    quota = AsyncMock()
    monkeypatch.setattr(chat_router, "enforce_chat_daily_quota", quota)
    monkeypatch.setattr(route_support, "get_chat_connection_manager", lambda _: SimpleNamespace(broadcast=AsyncMock()))
    try:
        return await chat_router.post_chat_message(
            link_id=link_id, payload=request or payload(), request=object(), user_hash=sender,
            principal=object(), authorization=SimpleNamespace(resolveOwnUserHash=lambda _, value: value),
            chat=control, hospital=provider,
        )
    finally:
        # 성공·거절과 무관하게 전송 시도는 일일 한도를 한 번 소비한다.
        quota.assert_awaited_once()


@pytest.mark.parametrize("sender", ["patient-a", "caregiver-a"])
@pytest.mark.anyio
async def test_share_uses_server_snapshot_and_retry_skips_provider(chat, monkeypatch, sender):
    """양측 모두 공유 가능하며 응답 유실 후 재시도는 제공자 장애에도 중복 저장하지 않는다."""
    lookup = AsyncMock(return_value=context())
    request = payload(hospital_context={"name": "위조 병원"})
    first = await send(chat, monkeypatch, sender=sender, request=request,
                       provider=SimpleNamespace(requestShareContext=lookup))
    assert first["created"] and first["data"]["context"]["hospital_context"] == context()
    lookup.side_effect = HospitalApiUnavailableError("provider down")
    second = await send(chat, monkeypatch, sender=sender, provider=SimpleNamespace(requestShareContext=lookup))
    assert not second["created"] and second["data"]["message_id"] == first["data"]["message_id"]
    assert lookup.await_count == 1
    assert chat[0].db.query(_ChatMessage).count() == 1


@pytest.mark.anyio
async def test_unauthorized_share_does_not_lookup_hospital(chat, monkeypatch):
    """다른 연동의 사용자는 외부 API 호출 전에 거절한다."""
    lookup = AsyncMock(return_value=context())
    with pytest.raises(HTTPException) as caught:
        await send(chat, monkeypatch, sender="outsider", provider=SimpleNamespace(requestShareContext=lookup))
    assert caught.value.status_code == 404 and lookup.await_count == 0


@pytest.mark.anyio
async def test_unlinked_during_lookup_cannot_send(chat, monkeypatch):
    """조회 중 연동 해제도 저장 직전 다시 확인한다."""
    async def lookup(*_):
        chat[0].db.query(_PatientCaregiverLink).filter_by(id=chat[1]).update({"linked": False})
        chat[0].db.commit()
        return context()
    with pytest.raises(HTTPException) as caught:
        await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup))
    assert caught.value.status_code == 404
    assert chat[0].db.query(_ChatMessage).count() == 0


@pytest.mark.anyio
async def test_provider_failure_is_retryable_without_partial_message(chat, monkeypatch):
    """제공자 오류 세부정보를 노출하거나 불완전한 카드를 저장하지 않는다."""
    lookup = AsyncMock(side_effect=HospitalApiUnavailableError("private provider URL"))
    with pytest.raises(HTTPException) as caught:
        await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup))
    assert caught.value.status_code == 503 and "private" not in caught.value.detail
    assert chat[0].db.query(_ChatMessage).count() == 0


@pytest.mark.anyio
async def test_deleted_share_has_no_hospital_context(chat, monkeypatch):
    """공유 메시지 삭제 후 병원 정보도 상대방에게 반환하지 않는다."""
    result = await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=AsyncMock(return_value=context())))
    chat[0].delete_messages(link_id=chat[1], user_hash="patient-a",
                            message_ids=[result["data"]["message_id"]], scope="everyone")
    history = chat[0].request_history(link_id=chat[1], user_hash="caregiver-a", before_message_id=None, limit=50)
    assert not history["data"][0].get("context")


@pytest.mark.parametrize("changes", [
    {"hospital_id": None}, {"hospital_schedule_date": None}, {"hospital_id": "../../other"},
    {"pharmacy_id": "P123"}, {"message_kind": "text"}, {"hospital_schedule_date": "9999-01-01"},
])
def test_invalid_hospital_requests_rejected(changes):
    """필수 문맥 누락·다른 공유 유형 혼합·비정상 ID를 거절한다."""
    with pytest.raises(ValidationError):
        payload(**changes)


@pytest.mark.parametrize("holiday,expected", [(True, "10:00 - 13:00"), (False, "09:00 - 19:00"), (None, "")])
@pytest.mark.anyio
async def test_shared_hours_follow_selected_date_not_current_time(holiday, expected):
    """공휴일 판단 실패 시 평일표를 대신 공유하지 않는다."""
    detail = HospitalDetails("A123", departments=("내과",),
        weekly_hours=(("1", "0900", "1900"), ("8", "1000", "1300")),
        location=HospitalLocationRecord("A123", "병원", "서울", "", 37.55, 126.92),
        fetched_at=datetime(2026, 9, 28, 1, tzinfo=UTC))
    control = CheckNearbyHospital(SimpleNamespace(fetchDetails=AsyncMock(return_value=detail)))
    control._is_holiday = AsyncMock(return_value=holiday)
    shared = await control.requestShareContext("A123", date(2026, 10, 5))
    assert shared["today_hours"] == expected and shared["schedule_date"] == "2026-10-05"
    assert shared["source_updated_at"] == detail.fetched_at.isoformat()
    control._boundary.fetchDetails.return_value = replace(detail, location=None)
    with pytest.raises(ValueError):
        await control.requestShareContext("A123", date(2026, 10, 5))


def test_detail_identity_is_parsed_from_provider():
    """공유용 이름·전화·좌표는 공식 상세 응답에서 추출한다."""
    root = ET.fromstring('''<response><body><totalCount>1</totalCount><items><item>
      <hpid>A123</hpid><dutyName>병원</dutyName><dutyAddr>서울</dutyAddr>
      <dutyTel1>02-000-0000</dutyTel1><wgs84Lat>37.55</wgs84Lat><wgs84Lon>126.92</wgs84Lon>
    </item></items></body></response>''')
    details = NationalEmergencyMedicalCenterHospitalAPI._parse_details(root, "A123")
    assert details.location.name == "병원" and details.location.latitude == 37.55
    assert details.fetched_at.tzinfo is not None
    root.find("body/items/item/wgs84Lat").text = "nan"
    assert NationalEmergencyMedicalCenterHospitalAPI._parse_details(root, "A123").location is None
