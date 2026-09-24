# 파일명: test_pharmacy_search_chat_flow.py
# 역할: 카탈로그가 없어 공공 API로 찾은 약국을 안전하게 채팅에 공유하는 흐름을 검증한다.

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from controls.check_nearby_pharmacy_control import CheckNearbyPharmacy, PharmacySearchMode
from controls.link_patient_caregiver_control import LinkPatientCaregiver
from controls.manage_linked_chat_control import ManageLinkedChat
from core.database import Base
from entities.nearby_pharmacy_entity import NearbyPharmacySearchResult, PharmacyLocationRecord
from entities.pharmacy_catalog_entity import PharmacyCatalogRecord, PharmacySearchCacheRecord
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository

PharmacyChatFlow = tuple[
    Session, PharmacyCatalogRepository, CheckNearbyPharmacy, AsyncMock, int,
]


# 함수이름: flow
# 함수역할: 실제 데모 DB와 분리한 저장소·연동·공공 검색 대역을 준비한다.
# 매개변수: 없음. 반환값: 검색·공유 시험에 필요한 의존성.
@pytest.fixture
def flow() -> Iterator[PharmacyChatFlow]:
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        links = LinkPatientCaregiver(db)
        code = links.generatePatientHash("patient-share")["data"]["patient_code"]
        link_id = links.requestPatientCaregiverLink("caregiver-share", code)["data"]["id"]
        boundary = AsyncMock()
        boundary.searchNearby.return_value = [PharmacyLocationRecord(
            pharmacy_id="public-pharmacy", name="공유 시험 약국", address="시험 주소",
            telephone="02-000-0000", latitude=37.5, longitude=127.0,
            distance_km=None, start_time="0900", end_time="2200",
        )]
        repository = PharmacyCatalogRepository(db)
        control = CheckNearbyPharmacy(pharmacy_boundary=boundary, pharmacy_repository=repository)
        yield db, repository, control, boundary, int(link_id)
    engine.dispose()


# 함수이름: _search
# 함수역할: 날짜·시각에 무관하게 고정 좌표의 전체 약국 검색을 실행한다.
# 매개변수: control 실제 검색 제어기. 반환값: 서버 검색 결과.
async def _search(control: CheckNearbyPharmacy) -> NearbyPharmacySearchResult:
    return await control.requestNearbyPharmacySearch(
        latitude=37.5, longitude=127.0, search_mode=PharmacySearchMode.ALL,
    )


# 함수이름: test_live_search_result_is_shareable_by_both_participants
# 함수역할: 카탈로그 없이 검색한 약국을 양측이 공유하되 확인하지 않은 운영시간을 만들지 않는다.
# 매개변수: flow 격리 흐름, sender 발신 역할, kind 공유 종류. 반환값: 없음.
@pytest.mark.anyio
@pytest.mark.parametrize("sender", ["patient-share", "caregiver-share"])
@pytest.mark.parametrize("kind", ["pharmacy_share", "pharmacy_phone_verified"])
async def test_live_search_result_is_shareable_by_both_participants(
    flow: PharmacyChatFlow, sender: str, kind: str,
) -> None:
    db, repository, control, _, link_id = flow
    result = await _search(control)
    assert len(result.data) == 1
    assert repository.count() == 0
    assert repository.latest_updated_at() is None
    # 별도 요청 세션에서도 조회되어 서버 프로세스의 메모리 상태에 의존하지 않는다.
    with Session(db.get_bind()) as sharing_db:
        sent = ManageLinkedChat(sharing_db).send_message(
            link_id=link_id, sender_hash=sender, client_message_id="search-share-0001",
            body="검색한 약국 공유", message_kind=kind, pharmacy_id=result.data[0].pharmacy_id,
        )
        context = sent.message.to_response_dict()["context"]["pharmacy_context"]
        assert context["name"] == "공유 시험 약국"
        assert context["address"] == "시험 주소"
        assert context["today_hours"] == ""
        assert context["source_updated_at"] is None


# 함수이름: test_repeated_search_updates_cache_without_disabling_public_search
# 함수역할: 재검색은 캐시 한 건만 갱신하며 부분 결과를 전국 카탈로그로 오인하지 않는다.
# 매개변수: flow 격리 흐름. 반환값: 없음.
@pytest.mark.anyio
async def test_repeated_search_updates_cache_without_disabling_public_search(
    flow: PharmacyChatFlow,
) -> None:
    db, repository, control, boundary, _ = flow
    await _search(control)
    await _search(control)
    assert boundary.searchNearby.await_count == 2
    assert db.query(PharmacySearchCacheRecord).count() == 1
    assert repository.count() == 0


# 함수이름: test_expired_and_unknown_search_ids_cannot_be_shared
# 함수역할: 조회한 적 없거나 24시간이 지난 약국은 거절하고 다음 검색 때 만료 캐시를 제거한다.
# 매개변수: flow 격리 흐름. 반환값: 없음.
@pytest.mark.anyio
async def test_expired_and_unknown_search_ids_cannot_be_shared(flow: PharmacyChatFlow) -> None:
    db, repository, control, boundary, link_id = flow
    await _search(control)
    cached = db.get(PharmacySearchCacheRecord, "public-pharmacy")
    cached.fetched_at = datetime.now(UTC).replace(tzinfo=None) - timedelta(hours=25)
    db.commit()
    for pharmacy_id in ["public-pharmacy", "untrusted-client-id"]:
        assert repository.find_by_id(pharmacy_id) is None
        with pytest.raises(HTTPException) as error:
            ManageLinkedChat(db).send_message(
                link_id=link_id, sender_hash="patient-share", client_message_id="rejected-share",
                body="만료된 약국", message_kind="pharmacy_share", pharmacy_id=pharmacy_id,
            )
        assert error.value.status_code == 400
    boundary.searchNearby.return_value = []
    await _search(control)
    assert db.query(PharmacySearchCacheRecord).count() == 0


# 함수이름: test_catalog_entry_takes_precedence_over_search_cache
# 함수역할: 전국 카탈로그가 준비되면 임시 캐시보다 정식 정보·주간 시간표를 우선한다.
# 매개변수: flow 격리 흐름. 반환값: 없음.
@pytest.mark.anyio
async def test_catalog_entry_takes_precedence_over_search_cache(flow: PharmacyChatFlow) -> None:
    db, repository, control, _, _ = flow
    await _search(control)
    db.add(PharmacyCatalogRecord(
        pharmacy_id="public-pharmacy", name="갱신된 약국", address="확인된 주소",
        telephone="02-000-0001", latitude=37.5, longitude=127.0,
        weekly_hours={"1": ["0800", "2300"]},
    ))
    db.commit()
    entry = repository.find_by_id("public-pharmacy")
    assert entry.name == "갱신된 약국"
    assert entry.weekly_hours == {"1": ("0800", "2300")}


# 함수이름: test_cache_failure_does_not_hide_usable_search_results
# 함수역할: 캐시 저장소 장애가 있어도 사용 가능한 공공 검색 결과는 반환한다.
# 매개변수: flow 격리 흐름. 반환값: 없음.
@pytest.mark.anyio
async def test_cache_failure_does_not_hide_usable_search_results(flow: PharmacyChatFlow) -> None:
    _, repository, control, _, _ = flow
    with patch.object(repository, "cache_search_results", side_effect=RuntimeError("cache unavailable")):
        result = await _search(control)
    assert result.data[0].pharmacy_id == "public-pharmacy"


# 함수이름: test_cache_commit_failure_rolls_back_partial_rows
# 함수역할: 저장 도중 DB 오류가 나면 부분 캐시를 남기지 않고 다음 조회를 허용한다.
# 매개변수: flow 격리 흐름. 반환값: 없음.
@pytest.mark.anyio
async def test_cache_commit_failure_rolls_back_partial_rows(flow: PharmacyChatFlow) -> None:
    db, repository, control, _, _ = flow
    with patch.object(db, "commit", side_effect=RuntimeError("commit unavailable")):
        result = await _search(control)
    assert result.data[0].pharmacy_id == "public-pharmacy"
    assert db.query(PharmacySearchCacheRecord).count() == 0
    await _search(control)
    assert repository.find_by_id("public-pharmacy") is not None
