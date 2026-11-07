# 파일명: test_hospital_chat_share.py
# 역할: 병원 공유의 권한·할당량, 서버 스냅샷, 날짜 검증과 멱등 재시도를 검증한다.

"""병원 공유의 신뢰 경계·공휴일 시간표·권한·재전송 및 삭제를 검증한다."""

from collections.abc import Iterator
from dataclasses import replace
from datetime import UTC, date, datetime
from types import SimpleNamespace
from typing import Any
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


# 함수이름: anyio_backend
# 함수역할:
# - 병원 공유의 비동기 경로를 asyncio에서 실행한다.
# 매개변수:
# - 없음.
# 반환값:
# - str; asyncio.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


# 함수이름: chat
# 함수역할:
# - 격리 데이터베이스에 환자·보호자 연동을 만들고 종료 후 세션과 엔진을 정리한다.
# 매개변수:
# - 없음.
# 반환값:
# - Iterator[tuple]; 채팅 컨트롤과 연동 ID.
@pytest.fixture
def chat() -> Iterator[tuple[ManageLinkedChat, int]]:
    """실제 사용자·대화와 분리된 DB에서 환자와 보호자를 연결한다."""
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with sessionmaker(bind=engine)() as db:
        links = LinkPatientCaregiver(db)
        code = links.generatePatientHash("patient-a")["data"]["patient_code"]
        link_id = links.requestPatientCaregiverLink("caregiver-a", code)["data"]["id"]
        yield ManageLinkedChat(db), link_id
    engine.dispose()


# 함수이름: payload
# 함수역할:
# - 병원 ID와 선택 날짜를 포함한 공유 요청을 만들고 지정 필드를 덮어쓴다.
# 매개변수:
# - changes: dict; 공유 요청에 덮어쓸 필드.
# 반환값:
# - ChatMessageCreate; 필드가 유효하지 않으면 ValidationError.
def payload(**changes: Any) -> ChatMessageCreate:
    """클라이언트는 병원 ID와 날짜만 보낸다."""
    return ChatMessageCreate(**dict({
        "client_message_id": "hospital_share_001", "body": "병원 정보를 공유해요.",
        "message_kind": "hospital_share", "hospital_id": "A123", "hospital_schedule_date": "2026-10-05",
    }, **changes))


# 함수이름: context
# 함수역할:
# - 서버가 확인한 병원의 신원·선택 날짜·시간표 문맥을 합성한다.
# 매개변수:
# - 없음.
# 반환값:
# - dict; 병원 공유 문맥.
def context() -> dict[str, str | float | list[str]]:
    return {"hospital_id": "A123", "name": "서버 확인 병원", "address": "서울",
            "telephone": "02-000-0000", "latitude": 37.55, "longitude": 126.92,
            "departments": ["내과"], "schedule_date": "2026-10-05", "today_hours": "10:00 - 13:00",
            "source_updated_at": "2026-09-28T01:00:00+00:00"}


# Function Name: send
# Description:
# - Runs the real route and persistence path with provider and quota doubles, asserting every send attempt consumes chat quota once.
# Parameters:
# - chat: tuple[ManageLinkedChat, int]; isolated control and active link ID.
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# - sender: str; sender identity.
# - request: ChatMessageCreate | None; request or default hospital share.
# - provider: object | None; hospital sharing control.
# - hospital_quota: AsyncMock | None; hospital quota checker.
# Returns:
# - dict; route response. Authorization, quota and provider errors propagate.
async def send(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch, *, sender: str = "patient-a", request: ChatMessageCreate | None = None, provider: SimpleNamespace | None = None,
               hospital_quota: AsyncMock | None = None) -> dict[str, Any]:
    """외부 통신만 대역으로 바꾸고 실제 저장·멱등 처리 경로를 실행한다."""
    control, link_id = chat
    quota = AsyncMock()
    monkeypatch.setattr(chat_router, "enforce_chat_daily_quota", quota)
    monkeypatch.setattr(chat_router, "enforce_hospital_share_daily_quota",
                        hospital_quota or AsyncMock())
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


# 함수이름: test_share_uses_server_snapshot_and_retry_skips_provider
# 함수역할:
# - 양측 모두 공유 가능하며 응답 유실 후 재시도는 제공자 장애에도 중복 저장하지 않는다.
# 매개변수:
# - chat: tuple[ManageLinkedChat, int]; 격리 채팅 컨트롤과 활성 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# - sender: str; 공유하는 연동 참여자 식별자.
# 반환값:
# - None.
@pytest.mark.parametrize("sender", ["patient-a", "caregiver-a"])
@pytest.mark.anyio
async def test_share_uses_server_snapshot_and_retry_skips_provider(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch, sender: str) -> None:
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


# Function Name: test_share_spends_the_hospital_search_quota_but_its_retry_does_not
# Description:
# - Requires one hospital quota charge and lookup for a new share, with neither repeated on idempotent retry.
# Parameters:
# - chat: tuple[ManageLinkedChat, int]; isolated chat control and link ID.
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - None.
@pytest.mark.anyio
async def test_share_spends_the_hospital_search_quota_but_its_retry_does_not(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch) -> None:
    """병원 공유는 공공 병원 API를 조회하므로 병원 검색 하루 한도를 쓰고, 이미 저장된 공유의 재시도는 쓰지 않는다."""
    hospital_quota = AsyncMock()
    lookup = AsyncMock(return_value=context())
    await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup),
               hospital_quota=hospital_quota)
    await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup),
               hospital_quota=hospital_quota)
    assert hospital_quota.await_count == 1
    assert lookup.await_count == 1


# Function Name: test_exhausted_hospital_quota_refuses_the_share_before_any_lookup
# Description:
# - Requires exhausted hospital quota to return 429 before provider work and leave no message.
# Parameters:
# - chat: tuple[ManageLinkedChat, int]; isolated chat control and link ID.
# - monkeypatch: pytest.MonkeyPatch; restores temporary dependency replacements.
# Returns:
# - None.
@pytest.mark.anyio
async def test_exhausted_hospital_quota_refuses_the_share_before_any_lookup(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch) -> None:
    """하루 한도를 다 쓴 계정의 병원 공유는 제공자 조회 전에 429로 거절된다."""
    from fastapi import HTTPException
    lookup = AsyncMock(return_value=context())
    refused = AsyncMock(side_effect=HTTPException(429, "quota"))
    with pytest.raises(HTTPException) as error:
        await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup),
                   hospital_quota=refused)
    assert error.value.status_code == 429
    lookup.assert_not_awaited()
    assert chat[0].db.query(_ChatMessage).count() == 0


# 함수이름: test_unauthorized_share_does_not_lookup_hospital
# 함수역할:
# - 다른 연동의 사용자는 외부 API 호출 전에 거절한다.
# 매개변수:
# - chat: tuple[ManageLinkedChat, int]; 격리 채팅 컨트롤과 활성 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_unauthorized_share_does_not_lookup_hospital(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch) -> None:
    """다른 연동의 사용자는 외부 API 호출 전에 거절한다."""
    lookup = AsyncMock(return_value=context())
    with pytest.raises(HTTPException) as caught:
        await send(chat, monkeypatch, sender="outsider", provider=SimpleNamespace(requestShareContext=lookup))
    assert caught.value.status_code == 404 and lookup.await_count == 0


# 함수이름: test_unlinked_during_lookup_cannot_send
# 함수역할:
# - 조회 중 연동 해제도 저장 직전 다시 확인한다.
# 매개변수:
# - chat: tuple[ManageLinkedChat, int]; 격리 채팅 컨트롤과 활성 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_unlinked_during_lookup_cannot_send(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch) -> None:
    """조회 중 연동 해제도 저장 직전 다시 확인한다."""
    # 함수이름: lookup
    # 함수역할:
    # - 상세 조회 중 연동을 해제·커밋하고 준비된 병원 문맥을 반환한다.
    # 매개변수:
    # - _: tuple; 사용하지 않는 상세 조회 인수.
    # 반환값:
    # - dict; 연동 해제 이후의 병원 문맥.
    async def lookup(*_: str | date) -> dict[str, str | float | list[str]]:
        chat[0].db.query(_PatientCaregiverLink).filter_by(id=chat[1]).update({"linked": False})
        chat[0].db.commit()
        return context()
    with pytest.raises(HTTPException) as caught:
        await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup))
    assert caught.value.status_code == 404
    assert chat[0].db.query(_ChatMessage).count() == 0


# 함수이름: test_provider_failure_is_retryable_without_partial_message
# 함수역할:
# - 제공자 오류 세부정보를 노출하거나 불완전한 카드를 저장하지 않는다.
# 매개변수:
# - chat: tuple[ManageLinkedChat, int]; 격리 채팅 컨트롤과 활성 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_provider_failure_is_retryable_without_partial_message(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch) -> None:
    """제공자 오류 세부정보를 노출하거나 불완전한 카드를 저장하지 않는다."""
    lookup = AsyncMock(side_effect=HospitalApiUnavailableError("private provider URL"))
    with pytest.raises(HTTPException) as caught:
        await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=lookup))
    assert caught.value.status_code == 503 and "private" not in caught.value.detail
    assert chat[0].db.query(_ChatMessage).count() == 0


# 함수이름: test_deleted_share_has_no_hospital_context
# 함수역할:
# - 공유 메시지 삭제 후 병원 정보도 상대방에게 반환하지 않는다.
# 매개변수:
# - chat: tuple[ManageLinkedChat, int]; 격리 채팅 컨트롤과 활성 연동 ID.
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_deleted_share_has_no_hospital_context(chat: tuple[ManageLinkedChat, int], monkeypatch: pytest.MonkeyPatch) -> None:
    """공유 메시지 삭제 후 병원 정보도 상대방에게 반환하지 않는다."""
    result = await send(chat, monkeypatch, provider=SimpleNamespace(requestShareContext=AsyncMock(return_value=context())))
    chat[0].delete_messages(link_id=chat[1], user_hash="patient-a",
                            message_ids=[result["data"]["message_id"]], scope="everyone")
    history = chat[0].request_history(link_id=chat[1], user_hash="caregiver-a", before_message_id=None, limit=50)
    assert not history["data"][0].get("context")


# 함수이름: test_invalid_hospital_requests_rejected
# 함수역할:
# - 필수 문맥 누락·다른 공유 유형 혼합·비정상 ID를 거절한다.
# 매개변수:
# - changes: dict; 공유 요청에 덮어쓸 필드.
# 반환값:
# - None.
@pytest.mark.parametrize("changes", [
    {"hospital_id": None}, {"hospital_schedule_date": None}, {"hospital_id": "../../other"},
    {"pharmacy_id": "P123"}, {"message_kind": "text"}, {"hospital_schedule_date": "9999-01-01"},
])
def test_invalid_hospital_requests_rejected(changes: dict[str, str | None]) -> None:
    """필수 문맥 누락·다른 공유 유형 혼합·비정상 ID를 거절한다."""
    with pytest.raises(ValidationError):
        payload(**changes)


# Function Name: test_shared_hours_follow_selected_date_not_current_time
# Description:
# - Checks selected-date holiday hours, unknown-calendar fallback and source timestamp; missing verified location must reject sharing.
# Parameters:
# - holiday: bool | None; holiday state for the selected date.
# - expected: str; expected displayed opening hours.
# Returns:
# - None.
@pytest.mark.parametrize("holiday,expected", [(True, "10:00 - 13:00"), (False, "09:00 - 19:00"), (None, "")])
@pytest.mark.anyio
async def test_shared_hours_follow_selected_date_not_current_time(holiday: bool | None, expected: str) -> None:
    """공휴일 판단 실패 시 평일표를 대신 공유하지 않는다."""
    detail = HospitalDetails("A123", departments=("내과",),
        weekly_hours=(("1", "0900", "1900"), ("8", "1000", "1300")),
        location=HospitalLocationRecord("A123", "병원", "서울", "", 37.55, 126.92),
        fetched_at=datetime(2026, 9, 28, 1, tzinfo=UTC))
    control = CheckNearbyHospital(
        SimpleNamespace(fetchDetails=AsyncMock(return_value=detail)),
        clock=lambda: datetime(2026, 10, 1, 9, tzinfo=UTC),
    )
    control._is_holiday = AsyncMock(return_value=holiday)
    shared = await control.requestShareContext("A123", date(2026, 10, 5))
    assert shared["today_hours"] == expected and shared["schedule_date"] == "2026-10-05"
    assert shared["source_updated_at"] == detail.fetched_at.isoformat()
    control._boundary.fetchDetails.return_value = replace(detail, location=None)
    with pytest.raises(ValueError):
        await control.requestShareContext("A123", date(2026, 10, 5))


# Function Name: test_share_date_outside_the_search_window_is_rejected_before_any_lookup
# Description:
# - Requires an out-of-window share date to fail before hospital detail or holiday lookup.
# Parameters:
# - schedule_date: date; date outside the permitted search window.
# Returns:
# - None.
@pytest.mark.parametrize("schedule_date", [
    date(2026, 9, 22), date(2027, 10, 4), date(1, 1, 1), date(9999, 12, 31),
])
@pytest.mark.anyio
async def test_share_date_outside_the_search_window_is_rejected_before_any_lookup(schedule_date: date) -> None:
    """검색이 받는 날짜 범위 밖이면 병원 상세도 공휴일도 조회하지 않고 거절한다."""
    boundary = SimpleNamespace(fetchDetails=AsyncMock())
    control = CheckNearbyHospital(boundary, clock=lambda: datetime(2026, 10, 1, 9, tzinfo=UTC))
    control._is_holiday = AsyncMock()
    with pytest.raises(ValueError):
        await control.requestShareContext("A123", schedule_date)
    boundary.fetchDetails.assert_not_awaited()
    control._is_holiday.assert_not_awaited()


# 함수이름: test_detail_identity_is_parsed_from_provider
# 함수역할:
# - 공유용 이름·전화·좌표는 공식 상세 응답에서 추출한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_detail_identity_is_parsed_from_provider() -> None:
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
