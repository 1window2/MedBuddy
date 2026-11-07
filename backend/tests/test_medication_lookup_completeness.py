# 파일명: test_medication_lookup_completeness.py
# 역할: 약품 후보 요약 실패 시 불완전성 유지, 재시도 복구와 캐시 안전성을 검증한다.

import json
from collections.abc import Generator
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from boundaries.medication_detail_cache_boundary import MedicationDetailCache
from controls.check_medication_detail_control import CheckMedicationDetail
from entities.medication_detail_entity import MedicationDetail, _DrugApprovalInfo, _DrugBasicInfo
from entities.medication_lookup_result import MedicationLookupResult
from services.local_medication_catalog import LocalMedicationCatalog
from support.fakes import FakeRedis


PRODUCT_NAME = "테스트정10mg"
PRODUCT_IDS = ["111", "222"]


# 함수이름: _detail
# 함수역할:
# - 지정 ID·이름과 고정된 비민감 설명을 갖는 약품 상세를 만든다.
# 매개변수:
# - item_seq: str; 합성 약품의 공공 제품 ID.
# - name: str; 합성 제품명.
# 반환값:
# - MedicationDetail; 합성 요약 결과.
def _detail(item_seq: str = "111", *, name: str = PRODUCT_NAME) -> MedicationDetail:
    return MedicationDetail(
        item_seq=item_seq,
        item_name=name,
        efficacy="synthetic effect",
        usage_method="synthetic usage",
        warning="synthetic warning",
    )


# 실제 조회·요약 취합·캐시는 유지하고 외부 서비스만 합성 응답으로 대체한다.
# 함수이름: lookup_case
# 함수역할:
# - 로컬 또는 공공 조회 경로의 동일 제품 자료와 선택적 요약 실패를 준비하고 종료 후 DB 자원을 정리한다.
# 매개변수:
# - request: pytest.FixtureRequest; local 또는 public 조회 경로.
# - tmp_path: Path; 테스트 전용 임시 디렉터리.
# 반환값:
# - Generator[SimpleNamespace]; 컨트롤·캐시·대체 제공자와 실패 ID 집합.
@pytest.fixture(params=["public", "local"])
def lookup_case(request, tmp_path) -> Generator[SimpleNamespace, None, None]:
    rows = [
        {
            "ITEM_SEQ": item_seq,
            "ITEM_NAME": PRODUCT_NAME,
            "EE_DOC_DATA": "synthetic effect document",
            "UD_DOC_DATA": "synthetic usage document",
            "NB_DOC_DATA": "synthetic warning document",
        }
        for item_seq in PRODUCT_IDS
    ]
    failed_ids: set[str] = set()

    # 함수이름: summarize
    # 함수역할:
    # - 실패 ID 집합에 속한 제품은 오류를 내고 나머지는 해당 제품의 합성 상세를 반환한다.
    # 매개변수:
    # - drug_name: str; 요청 약품명(대체 요약에서 사용하지 않음).
    # - item: dict; 공공 허가 제품 행.
    # 반환값:
    # - MedicationDetail; 실패 대상이면 RuntimeError.
    async def summarize(drug_name, item):
        if item["ITEM_SEQ"] in failed_ids:
            raise RuntimeError("synthetic summary failure")
        return _detail(item["ITEM_SEQ"], name=item["ITEM_NAME"])

    generator = SimpleNamespace(summarize_advanced_item=AsyncMock(side_effect=summarize))
    engine = None
    db = None
    if request.param == "local":
        engine = create_engine(f"sqlite:///{tmp_path / 'catalog.sqlite'}")
        _DrugBasicInfo.__table__.create(engine)
        _DrugApprovalInfo.__table__.create(engine)
        with Session(engine) as writer:
            writer.add_all([
                _DrugApprovalInfo(
                    item_seq=row["ITEM_SEQ"],
                    item_name=PRODUCT_NAME,
                    normalized_item_name=PRODUCT_NAME.lower(),
                    efficacy_doc=row["EE_DOC_DATA"],
                    use_method_doc=row["UD_DOC_DATA"],
                    warning_doc=row["NB_DOC_DATA"],
                    raw_json=json.dumps(row),
                )
                for row in rows
            ])
            writer.commit()
        db = Session(engine)

    redis = FakeRedis()
    cache = MedicationDetailCache(redis_client=redis)
    catalog = LocalMedicationCatalog(db=db, summary_generator=generator)
    basic_api = SimpleNamespace(searchMedication=AsyncMock(return_value=[]))
    advanced_api = SimpleNamespace(searchMedication=AsyncMock(return_value=rows))
    control = CheckMedicationDetail(
        medication_cache=cache,
        local_medication_catalog=catalog,
        summary_generator=generator,
        public_drug_small_api=basic_api,
        public_drug_large_api=advanced_api,
        pill_image_api=SimpleNamespace(
            searchMedicationImage=AsyncMock(return_value="https://example.org/synthetic.png"),
        ),
    )
    try:
        yield SimpleNamespace(
            control=control, redis=redis, cache=cache, catalog=catalog,
            generator=generator, failed_ids=failed_ids, source=request.param,
            engine=engine, rows=rows, advanced_api=advanced_api, basic_api=basic_api,
        )
    finally:
        if db is not None:
            db.close()
        if engine is not None:
            engine.dispose()


# 같은 이름이라도 품목 코드가 다른 후보의 실패는 자동 확정의 근거가 될 수 없다.
# 함수이름: test_partial_summary_keeps_confirmation_and_recovers_missing_product
# 함수역할:
# - 일부 요약 실패는 성공 후보를 확인 대상으로 유지하며 전체 결과 캐시를 쓰지 않고 이후 복구 시 누락 제품도 반환하는지 확인한다.
# 매개변수:
# - lookup_case: SimpleNamespace; 실제 조회 컨트롤과 대체 캐시·요약기·자료.
# - failed_id: str; 요약 실패를 주입할 제품 ID.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("failed_id", PRODUCT_IDS)
async def test_partial_summary_keeps_confirmation_and_recovers_missing_product(
    lookup_case, failed_id,
):
    case = lookup_case
    case.failed_ids.add(failed_id)

    partial = await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert partial.success and partial.requires_confirmation
    assert partial.data == []
    assert [item.item_seq for item in partial.candidates] == [
        item_seq for item_seq in PRODUCT_IDS if item_seq != failed_id
    ]
    assert partial.candidates[0].efficacy == "synthetic effect"
    assert partial.candidates[0].image_url == "https://example.org/synthetic.png"
    assert case.redis.calls["setex"] == 0
    assert case.redis.values == {}

    case.failed_ids.clear()
    recovered = await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert recovered.requires_confirmation and recovered.data == []
    assert {item.item_seq for item in recovered.candidates} == set(PRODUCT_IDS)
    calls_after_recovery = case.generator.summarize_advanced_item.await_count
    assert calls_after_recovery == (4 if case.source == "public" else 3)
    assert case.redis.calls["setex"] == (1 if case.source == "public" else 0)

    cached = await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert cached.requires_confirmation and cached.data == []
    assert {item.item_seq for item in cached.candidates} == set(PRODUCT_IDS)
    assert case.generator.summarize_advanced_item.await_count == calls_after_recovery
    if case.source == "local":
        case.basic_api.searchMedication.assert_not_awaited()
        case.advanced_api.searchMedication.assert_not_awaited()


# 함수이름: test_all_candidate_summary_failures_remain_errors_and_retry
# 함수역할:
# - 모든 후보 요약 실패는 오류로 전파되고 캐시하지 않으며 후속 요청에서 복구 가능한지 확인한다.
# 매개변수:
# - lookup_case: SimpleNamespace; 실제 조회 컨트롤과 대체 캐시·요약기·자료.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_all_candidate_summary_failures_remain_errors_and_retry(lookup_case):
    case = lookup_case
    case.failed_ids.update(PRODUCT_IDS)

    with pytest.raises(RuntimeError, match="synthetic summary failure"):
        await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert case.generator.summarize_advanced_item.await_count == 2
    assert case.redis.calls["setex"] == 0
    assert case.redis.values == {}

    case.failed_ids.clear()
    recovered = await case.control.requestMedicationDetail(PRODUCT_NAME)
    assert recovered.requires_confirmation
    assert {item.item_seq for item in recovered.candidates} == set(PRODUCT_IDS)
    assert case.generator.summarize_advanced_item.await_count == 4


# 함수이름: test_complete_single_product_still_auto_matches_and_reuses_summary
# 함수역할:
# - 완전한 단일 일치 제품은 자동 확정하면서 반복 요청의 요약을 재사용하는지 확인한다.
# 매개변수:
# - lookup_case: SimpleNamespace; 실제 조회 컨트롤과 대체 캐시·요약기·자료.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_complete_single_product_still_auto_matches_and_reuses_summary(lookup_case):
    case = lookup_case
    if case.source == "local":
        with Session(case.engine) as writer:
            writer.query(_DrugApprovalInfo).filter_by(item_seq="222").delete()
            writer.commit()
    else:
        case.advanced_api.searchMedication.return_value = case.rows[:1]

    for _ in range(2):
        response = await case.control.requestMedicationDetail(PRODUCT_NAME)
        assert response.success and not response.requires_confirmation
        assert [item.item_seq for item in response.data] == ["111"]
    case.generator.summarize_advanced_item.assert_awaited_once()


# 함수이름: test_partial_results_cannot_be_written_to_full_result_cache
# 함수역할:
# - 불완전한 조회 결과는 전체 결과 캐시에 저장하지 않는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_partial_results_cannot_be_written_to_full_result_cache():
    redis = FakeRedis()
    cache = MedicationDetailCache(redis_client=redis)

    await cache.set(PRODUCT_NAME, MedicationLookupResult([_detail()], is_complete=False))

    assert redis.values == {}
    assert redis.calls["setex"] == 0
    assert await cache.get(PRODUCT_NAME) is None


# 구버전 캐시에는 누락 여부가 없어 정상처럼 보여도 새 조회에서 사용하지 않는다.
# 함수이름: test_legacy_cache_cannot_hide_a_product
# 함수역할:
# - 이전 캐시 키의 불완전 제품 목록은 새 조회를 가리지 않고 모든 제품 후보가 반환되는지 확인한다.
# 매개변수:
# - lookup_case: SimpleNamespace; 실제 조회 컨트롤과 대체 캐시·요약기·자료.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_legacy_cache_cannot_hide_a_product(lookup_case):
    case = lookup_case
    old_key = f"drug_info:{PRODUCT_NAME}"
    case.redis.values[old_key] = json.dumps([_detail().getMedicationDetail()])

    response = await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert response.requires_confirmation and response.data == []
    assert {item.item_seq for item in response.candidates} == set(PRODUCT_IDS)
    assert case.generator.summarize_advanced_item.await_count == 2
    assert old_key in case.redis.values
    if case.source == "public":
        assert case.redis.ttl_seconds[f"drug_info:v2:{PRODUCT_NAME}"] == 604800


# 함수이름: test_malformed_cached_candidate_is_not_silently_dropped
# 함수역할:
# - 캐시 후보 하나가 잘못되면 조용히 제외하지 않고 캐시 전체를 누락으로 취급하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_malformed_cached_candidate_is_not_silently_dropped():
    redis = FakeRedis()
    cache = MedicationDetailCache(redis_client=redis)
    redis.values[f"drug_info:v2:{PRODUCT_NAME}"] = json.dumps([
        _detail().getMedicationDetail(), None,
    ])

    assert await cache.get(PRODUCT_NAME) is None


# 재정렬·필터링 후 다음 공급자로 넘어가더라도 앞에서 실패한 후보가 사라진 사실을 유지한다.
# 함수이름: test_local_partial_result_stays_partial_through_fallback
# 함수역할:
# - 로컬 결과가 불완전하면 후속 캐시·공공 결과가 있어도 확인 요구를 유지하고 완전 결과로 캐시하지 않는지 확인한다.
# 매개변수:
# - lookup_case: SimpleNamespace; 실제 조회 컨트롤과 대체 캐시·요약기·자료.
# - fallback_source: str; 후속 결과를 공급할 cache 또는 public 경로.
# 반환값:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize("fallback_source", ["public", "cache"])
async def test_local_partial_result_stays_partial_through_fallback(lookup_case, fallback_source):
    case = lookup_case
    case.control.local_medication_catalog = SimpleNamespace(
        fetch_drug_info=AsyncMock(return_value=MedicationLookupResult(
            [_detail(name="테스트정500mg")], is_complete=False,
        )),
    )
    if fallback_source == "cache":
        await case.cache.set(PRODUCT_NAME, MedicationLookupResult([_detail()]))
    else:
        case.control._fetch_public_drug_info = AsyncMock(
            return_value=MedicationLookupResult([_detail()]),
        )

    response = await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert response.requires_confirmation and response.data == []
    assert [item.item_seq for item in response.candidates] == ["111"]
    if fallback_source == "public":
        assert case.redis.calls["setex"] == 0


# Function Name: test_later_search_keyword_does_not_erase_earlier_summary_failure
# Description:
# - Requires a complete later keyword result to retain the earlier incomplete lookup warning and manual confirmation.
# Parameters:
# - lookup_case: SimpleNamespace; isolated lookup control and provider/cache doubles.
# Returns:
# - None.
@pytest.mark.anyio
async def test_later_search_keyword_does_not_erase_earlier_summary_failure(lookup_case):
    case = lookup_case
    case.control.text_normalizer = SimpleNamespace(
        normalize_raw_text=lambda value: value,
        build_search_keywords=lambda value, **_: [value, "테스트정"],
    )
    case.control._fetch_drug_info = AsyncMock(side_effect=[
        MedicationLookupResult([_detail(name="테스트정500mg")], is_complete=False),
        MedicationLookupResult([_detail()]),
    ])

    response = await case.control.requestMedicationDetail(PRODUCT_NAME)

    assert response.requires_confirmation and response.data == []
    assert [item.item_seq for item in response.candidates] == ["111"]
    assert case.control._fetch_drug_info.await_count == 2
