# 파일명: test_medication_search_modes.py
# 역할: 검색 모드별 조회 예산과 원본 증거 기반 후보 확인, 실패 전파 및 HTTP 계약을 검증한다.

"""검색 모드의 범위·시간 예산과 원본 증거 기반 확인 규칙을 외부 전송 없이 검증한다."""

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from pydantic import ValidationError

from api.dependencies import get_check_medication_detail, get_medication_search_cache
from api.router import identify_medication
from boundaries.public_drug_api_boundary import PublicDrugLargeAPI, PublicDrugSmallAPI
from controls.check_medication_detail_control import CheckMedicationDetail
from core.config import settings
from entities.medication_detail_entity import MedicationDetail
from entities.medication_lookup_result import MedicationLookupResult
from schemas.medication import MedicationRequest, MedicationResponse
from services.medication_name_matching import MedicationNameMatcher, MedicationTextNormalizer


MODES = ['fast', 'balanced', 'thorough']
PRODUCT = '펠로엔정(펠로디핀)'
VARIANT_PRODUCT = '대웅에니코프캡슐300mg(메타레핀)'


# 함수이름: detail
# 함수역할:
# - 제품명과 식별자를 갖고 설명 필드는 비어 있는 합성 약품 상세를 생성한다.
# 매개변수:
# - name: str; 제품명.
# - item_seq: str; 공공 제품 식별자.
# 반환값:
# - MedicationDetail; 검색 결과로 사용할 상세.
def detail(name=PRODUCT, item_seq='1'):
    return MedicationDetail(
        item_name=name, item_seq=item_seq, efficacy='', usage_method='', warning='',
    )


# Class Name: RecordingSearchCache
# Role: Records products offered to the chat attachment cache or simulates a cache failure.
# Responsibilities:
# - Collects supplied details without persistence or external requests.
# Attributes:
# - fail (bool): injected failure; remembered (list): recorded details.
class RecordingSearchCache:
    # Function Name: __init__
    # Description:
    # - Initializes an empty record of remembered products and the failure switch.
    # Parameters:
    # - fail: bool; whether remember raises RuntimeError.
    # Returns:
    # - None.
    def __init__(self, fail=False):
        self.fail = fail
        self.remembered = []

    # Function Name: remember
    # Description:
    # - Stores all supplied details unless the configured cache failure is raised.
    # Parameters:
    # - details: Iterable[MedicationDetail]; products and candidates returned by search.
    # Returns:
    # - None.
    async def remember(self, details):
        if self.fail:
            raise RuntimeError('private cache failure')
        self.remembered.extend(details)


# 함수이름: control_with_results
# 함수역할:
# - 이름 정규화·매칭은 실제 구현을 사용하고 약품 조회만 순차 응답으로 교체한다.
# 매개변수:
# - results: tuple[MedicationLookupResult | Exception, ...]; 조회별 응답 또는 오류.
# 반환값:
# - CheckMedicationDetail; 외부 조회가 대체된 컨트롤.
def control_with_results(*results):
    control = object.__new__(CheckMedicationDetail)
    control.text_normalizer = MedicationTextNormalizer()
    control.name_matcher = MedicationNameMatcher()
    control._fetch_drug_info = AsyncMock(side_effect=list(results))
    return control


# 함수이름: control_with_empty_sources
# 함수역할:
# - 실제 공공 API 경계에 빈 응답 전송기를 연결하고 캐시·로컬 조회·이미지·요약을 대체한다.
# 매개변수:
# - 없음.
# 반환값:
# - tuple; 컨트롤과 호출 횟수를 기록하는 전송기.
def control_with_empty_sources():
    transport = SimpleNamespace(request_items=AsyncMock(return_value=([], 0)))
    return CheckMedicationDetail(
        medication_cache=SimpleNamespace(get=AsyncMock(return_value=None), set=AsyncMock()),
        local_medication_catalog=SimpleNamespace(
            fetch_drug_info=AsyncMock(return_value=MedicationLookupResult()),
        ),
        public_drug_small_api=PublicDrugSmallAPI(transport=transport),
        public_drug_large_api=PublicDrugLargeAPI(transport=transport),
        pill_image_api=SimpleNamespace(searchMedicationImage=AsyncMock(return_value='')),
        summary_generator=SimpleNamespace(summarize_advanced_item=AsyncMock()),
    ), transport


# 함수이름: test_schema_defaults_to_balanced_and_accepts_only_named_modes
# 함수역할:
# - 요청의 기본 검색 모드는 balanced이며 명시된 세 모드 외 값은 검증 오류로 거부되는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_schema_defaults_to_balanced_and_accepts_only_named_modes():
    assert MedicationRequest(extracted_text=PRODUCT).search_mode == 'balanced'
    for mode in MODES:
        assert MedicationRequest(search_mode=mode).search_mode == mode
    for invalid in ['slow', 'FAST', '', None, 1]:
        with pytest.raises(ValidationError):
            MedicationRequest(search_mode=invalid)


# 함수이름: test_direct_product_and_ingredient_queries_precede_all_variants
# 함수역할:
# - 원본 제품·성분 검색이 오타 변형보다 우선하고 검색어 중복과 최대 개수가 제한되는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_direct_product_and_ingredient_queries_precede_all_variants():
    normalizer = MedicationTextNormalizer()
    assert normalizer.build_search_keywords(PRODUCT) == [
        PRODUCT, '펠로엔정', '펠로디핀', '펠로엔',
    ]
    keywords = normalizer.build_search_keywords(VARIANT_PRODUCT)
    assert keywords[:3] == [
        VARIANT_PRODUCT, '대웅에니코프캡슐300mg', '메타레핀',
    ]
    assert keywords.index('에니코프') < keywords.index('매타레핀')
    assert len(keywords) == len(set(keywords)) <= 24


# 함수이름: test_fast_does_not_search_ingredients_or_ocr_variants
# 함수역할:
# - fast 모드는 제품명만 조회하고 성분 확장·OCR 변형은 만들지 않는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_fast_does_not_search_ingredients_or_ocr_variants():
    normalizer = MedicationTextNormalizer()
    assert normalizer.build_search_keywords(PRODUCT, search_mode='fast') == [
        PRODUCT, '펠로엔정',
    ]
    assert normalizer.build_search_keywords('에니코프', search_mode='fast') == ['에니코프']
    assert normalizer.build_search_keywords('(펠로디핀)', search_mode='fast') == ['(펠로디핀)']


# 함수이름: test_truncated_parentheses_keep_original_and_query_product_first
# 함수역할:
# - 잘린 괄호가 있어도 원문과 추출 제품명을 먼저 조회하고 모드별 검색어 상한을 지키는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# - text: str; 괄호가 잘린 원본 인식 문자열.
# - product: str; 괄호 설명을 분리한 예상 제품 검색어.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.parametrize('text,product', [
    ('펠로엔정(필루비프로펜(미분..', '펠로엔정'),
    ('뮤코라민정 (레 바미파피드)_(..', '뮤코라민정'),
    ('소론도정(프레드니솔론)_(.', '소론도정'),
    ('엘타인캡슐(에르도스테인)-', '엘타인캡슐'),
    ('시험정5mg(성분(미분...', '시험정5mg'),
    ('시험정(성분) 5mg (설명...', '시험정 5mg'),
])
def test_truncated_parentheses_keep_original_and_query_product_first(mode, text, product):
    keywords = MedicationTextNormalizer().build_search_keywords(text, search_mode=mode)
    assert keywords[:2] == [text, product]
    assert len(keywords) <= MedicationTextNormalizer.SEARCH_KEYWORD_LIMITS[mode]


# 함수이름: test_truncated_feloen_name_returns_a_candidate_without_auto_confirmation
# 함수역할:
# - 잘린 제품명에서 찾은 후보는 원본을 비교 기준으로 유지하며 자동 확정 없이 확인 대상으로 반환하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_truncated_feloen_name_returns_a_candidate_without_auto_confirmation(mode):
    original = '펠로엔정(필루비프로펜(미분..'
    product = detail('펠로엔정(펠루비프로펜(미분화))', '202104060')
    control = control_with_results()
    control._fetch_drug_info.side_effect = (
        lambda keyword, **kwargs: MedicationLookupResult([product])
        if keyword == '펠로엔정' else MedicationLookupResult()
    )
    response = await control.requestMedicationDetail(original, search_mode=mode)
    calls = control._fetch_drug_info.call_args_list
    assert [call.args[0] for call in calls[:2]] == [original, '펠로엔정']
    assert all(call.kwargs['reference'] == original for call in calls)
    assert response.requires_confirmation
    assert response.data == []
    assert response.candidates == [product]


# 함수이름: test_truncated_parenthesis_search_still_rejects_wrong_strength
# 함수역할:
# - 괄호가 잘린 검색어라도 다른 함량 후보는 strength_or_form으로 제외하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_truncated_parenthesis_search_still_rejects_wrong_strength(mode):
    original = '시험정5mg(성분(미분..'
    control = control_with_results()
    control._fetch_drug_info.side_effect = None
    control._fetch_drug_info.return_value = MedicationLookupResult([detail('시험정10mg')])
    response = await control.requestMedicationDetail(original, search_mode=mode)
    assert response.data == response.candidates == []
    assert response.review_reason == 'strength_or_form'


# 함수이름: test_thorough_extends_balanced_with_ocr_and_inside_variants
# 함수역할:
# - thorough는 balanced 순서를 유지한 뒤 성분 내부 형태와 OCR 변형을 추가하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_thorough_extends_balanced_with_ocr_and_inside_variants():
    normalizer = MedicationTextNormalizer()
    text = '에니코프캡슐(메타레핀정)'
    balanced = normalizer.build_search_keywords(text, search_mode='balanced')
    thorough = normalizer.build_search_keywords(text, search_mode='thorough')
    assert thorough[:4] == balanced
    assert '메타레핀정' in balanced
    assert '메타레핀' in thorough
    assert '애니코프캡슐(메타레핀정)' in thorough
    assert len(thorough) > len(balanced)


# 함수이름: test_mode_attempt_budgets_are_sequential_and_keep_full_evidence
# 함수역할:
# - 검색 시도를 동시에 실행하지 않고 모드별 2·4·8회 예산과 모든 호출의 원본 비교 기준을 유지하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# - budget: int; 해당 모드의 최대 검색 시도 수.
# 반환값:
# - None.
@pytest.mark.parametrize('mode,budget', [('fast', 2), ('balanced', 4), ('thorough', 8)])
@pytest.mark.anyio
async def test_mode_attempt_budgets_are_sequential_and_keep_full_evidence(mode, budget):
    control = control_with_results()
    calls = []
    active = 0

    # 함수이름: fetch
    # 함수역할:
    # - 동시 조회가 없음을 확인하고 검색어·원본을 기록한 뒤 빈 결과를 반환한다.
    # 매개변수:
    # - keyword: str; 현재 검색어.
    # - reference: str; 원본 비교 기준.
    # 반환값:
    # - MedicationLookupResult; 완전한 빈 조회 결과.
    async def fetch(keyword, *, reference):
        nonlocal active
        active += 1
        assert active == 1
        calls.append((keyword, reference))
        await asyncio.sleep(0)
        active -= 1
        return MedicationLookupResult()

    control._fetch_drug_info.side_effect = fetch
    response = await control.requestMedicationDetail(VARIANT_PRODUCT, search_mode=mode)
    assert not response.success
    assert response.review_reason == 'not_found'
    assert len(calls) == budget
    assert all(reference == VARIANT_PRODUCT for _, reference in calls)
    assert calls[:2] == [
        (VARIANT_PRODUCT, VARIANT_PRODUCT), ('대웅에니코프캡슐300mg', VARIANT_PRODUCT),
    ]


# 함수이름: test_real_lookup_pipeline_bounds_both_public_sources_without_retries
# 함수역할:
# - 실제 조회 파이프라인이 시도마다 두 공공 API만 호출하고 빈 결과에는 이미지·요약 작업을 하지 않는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# - budget: int; 해당 모드의 최대 검색 시도 수.
# 반환값:
# - None.
@pytest.mark.parametrize('mode,budget', [('fast', 2), ('balanced', 4), ('thorough', 8)])
@pytest.mark.anyio
async def test_real_lookup_pipeline_bounds_both_public_sources_without_retries(mode, budget):
    control, transport = control_with_empty_sources()
    response = await control.requestMedicationDetail(VARIANT_PRODUCT, search_mode=mode)
    assert response.review_reason == 'not_found'
    assert control.local_medication_catalog.fetch_drug_info.await_count == budget
    assert transport.request_items.await_count == 2 * budget
    control.pill_image_api.searchMedicationImage.assert_not_awaited()
    control.summary_generator.summarize_advanced_item.assert_not_awaited()


# Function Name: test_real_public_boundary_errors_cannot_become_not_found
# Description:
# - Requires either public source failure to propagate when fallback yields no product, without caching a false not-found result.
# Parameters:
# - source: str; failing basic or advanced provider.
# - mode: str; search mode under test.
# - error: Exception; injected transport failure.
# Returns:
# - None.
@pytest.mark.parametrize('source', ['basic', 'advanced'])
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.parametrize('error', [
    ConnectionError('synthetic connection failure'),
    RuntimeError('synthetic API failure'), httpx.ReadTimeout('synthetic HTTP timeout'),
])
@pytest.mark.anyio
async def test_real_public_boundary_errors_cannot_become_not_found(source, mode, error):
    control, transport = control_with_empty_sources()
    # 기본 API 오류 뒤에도 허가 API를 확인하며, 그마저 비면 기본 API 오류를 그대로 알린다.
    transport.request_items.side_effect = [error, ([], 0)] if source == 'basic' else [([], 0), error]
    with pytest.raises(type(error)) as raised:
        await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert raised.value is error
    assert transport.request_items.await_count == 2
    control.medication_cache.set.assert_not_awaited()


# Function Name: test_basic_public_api_failure_still_falls_back_to_advanced_api
# Description:
# - Requires a basic API failure to fall back to the advanced source and return its exact summarized product.
# Parameters:
# - mode: str; search mode under test.
# Returns:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_basic_public_api_failure_still_falls_back_to_advanced_api(mode):
    control, transport = control_with_empty_sources()
    transport.request_items.side_effect = [
        RuntimeError('synthetic basic API failure'),
        ([{'ITEM_SEQ': '1', 'ITEM_NAME': PRODUCT}], 1),
    ]
    control.summary_generator.summarize_advanced_item.return_value = detail()
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert response.success and not response.requires_confirmation
    assert response.data == [detail()]
    assert [call.args[0] for call in transport.request_items.await_args_list] == [
        settings.BASIC_DRUG_API_BASE_URL, settings.ADVANCED_DRUG_API_BASE_URL,
    ]


# Function Name: test_thorough_summarises_each_advanced_product_once_per_request
# Description:
# - Requires repeated advanced-source hits to share one summary within a request, but not across requests.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_thorough_summarises_each_advanced_product_once_per_request():
    control, transport = control_with_empty_sources()
    candidate = {'ITEM_SEQ': '9', 'ITEM_NAME': '펠로엔정'}

    # Function Name: request_items
    # Description:
    # - Returns one synthetic candidate only for the advanced API, allowing repeated summary reuse to be measured.
    # Parameters:
    # - url: str; requested public API URL.
    # - params: dict; query parameters, unused.
    # - _: dict; additional transport options, unused.
    # Returns:
    # - tuple[list[dict], int]; advanced candidate and count, otherwise empty.
    async def request_items(url, params, **_):
        return ([candidate], 1) if url == settings.ADVANCED_DRUG_API_BASE_URL else ([], 0)

    transport.request_items.side_effect = request_items
    control.summary_generator.summarize_advanced_item.return_value = detail('펠로엔정', '9')
    response = await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert response.requires_confirmation
    assert response.candidates == [detail('펠로엔정', '9')]
    assert control.local_medication_catalog.fetch_drug_info.await_count > 1
    control.summary_generator.summarize_advanced_item.assert_awaited_once()
    await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert control.summary_generator.summarize_advanced_item.await_count == 2


# 함수이름: test_felodipine_product_query_is_reached_before_typos
# 함수역할:
# - 제품명 검색에서 완전 일치 결과를 찾으면 오타 변형까지 진행하지 않고 확정하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_felodipine_product_query_is_reached_before_typos(mode):
    control = control_with_results(
        MedicationLookupResult(), MedicationLookupResult([detail()]),
    )
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert [call.args[0] for call in control._fetch_drug_info.call_args_list] == [
        PRODUCT, '펠로엔정',
    ]
    assert response.success and not response.requires_confirmation
    assert response.data[0].item_name == PRODUCT


# 함수이름: test_single_complete_exact_product_exits_immediately
# 함수역할:
# - 완전한 단일 제품 일치를 찾으면 추가 조회 없이 즉시 반환하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_single_complete_exact_product_exits_immediately(mode):
    control = control_with_results(MedicationLookupResult([detail()]))
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert response.data == [detail()]
    control._fetch_drug_info.assert_awaited_once()


# 함수이름: test_only_thorough_continues_after_ambiguous_product
# 함수역할:
# - 모호한 첫 후보 뒤 추가 조회는 thorough만 수행하며 다른 모드는 확인 후보로 반환하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_only_thorough_continues_after_ambiguous_product(mode):
    candidate = detail('펠로엔정', 'candidate')
    control = control_with_results(
        MedicationLookupResult([candidate]), MedicationLookupResult([detail()]),
    )
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    if mode == 'thorough':
        assert response.data == [detail()]
        assert control._fetch_drug_info.await_count == 2
    else:
        assert response.data == []
        assert response.candidates == [candidate]
        assert response.requires_confirmation
        control._fetch_drug_info.assert_awaited_once()


# 함수이름: test_thorough_upgrades_same_product_to_original_exact_match
# 함수역할:
# - 동일 제품의 후속 원본 완전 일치가 초기 불완전 후보를 대체하면 추가 조회 없이 확정하는지 확인한다.
# 매개변수:
# - original: str; 비교 기준으로 보존할 원본 제품명.
# - candidate_name: str; 동일 제품 ID의 초기 불완전 이름.
# 반환값:
# - None.
@pytest.mark.parametrize('original,candidate_name', [
    (PRODUCT, '펠로엔정'),
    ('펠로엔정5mg(펠로디핀)', PRODUCT),
])
@pytest.mark.anyio
async def test_thorough_upgrades_same_product_to_original_exact_match(original, candidate_name):
    candidate = detail(candidate_name, 'same-product')
    exact = detail(original, 'same-product')
    control = control_with_results(
        MedicationLookupResult([candidate]), MedicationLookupResult([exact]),
        AssertionError('An exact complete product must stop further lookups.'),
    )
    response = await control.requestMedicationDetail(
        PRODUCT, original_text=original, search_mode='thorough',
    )
    assert response.data == [exact] and not response.requires_confirmation
    assert response.candidates == []
    assert control._fetch_drug_info.await_count == 2
    assert all(call.kwargs['reference'] == original
               for call in control._fetch_drug_info.call_args_list)


# 함수이름: test_same_product_never_upgrades_from_corrected_text_against_original
# 함수역할:
# - 동일 제품 ID라도 보정 이름의 함량·제형이 원본과 충돌하면 기존 후보를 자동 확정으로 승격하지 않는지 확인한다.
# 매개변수:
# - unsafe_name: str; 원본과 함량·제형이 충돌하는 이름.
# 반환값:
# - None.
@pytest.mark.parametrize('unsafe_name', [
    '펠로엔정10mg(펠로디핀)',
    '펠로엔캡슐5mg(펠로디핀)',
    '펠로엔서방정5mg(펠로디핀)',
])
@pytest.mark.anyio
async def test_same_product_never_upgrades_from_corrected_text_against_original(unsafe_name):
    original = '펠로엔정5mg(펠로디핀)'
    candidate = detail('펠로엔정', 'same-product')
    control = control_with_results(
        MedicationLookupResult([candidate]),
        MedicationLookupResult([detail(unsafe_name, 'same-product')]),
        *[MedicationLookupResult()] * 8,
    )
    response = await control.requestMedicationDetail(
        unsafe_name, original_text=original, search_mode='thorough',
    )
    assert response.requires_confirmation and response.data == []
    assert response.candidates == [candidate]
    assert control._fetch_drug_info.await_count >= 2
    assert all(call.kwargs['reference'] == original
               for call in control._fetch_drug_info.call_args_list)


# 함수이름: test_same_product_exact_upgrade_keeps_incomplete_lookup_confirmation
# 함수역할:
# - 후속 완전 일치가 있어도 앞선 불완전 조회 이력이 있으면 확인 요구를 유지하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_same_product_exact_upgrade_keeps_incomplete_lookup_confirmation():
    exact = detail(item_seq='same-product')
    control = control_with_results(
        MedicationLookupResult([detail('펠로엔정', 'same-product')], is_complete=False),
        MedicationLookupResult([exact]), MedicationLookupResult(), MedicationLookupResult(),
    )
    response = await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert response.requires_confirmation and response.data == []
    assert response.candidates == [exact]
    assert control._fetch_drug_info.await_count == 4


# 함수이름: test_same_product_upgrade_preserves_distinct_exact_products_without_downgrade
# 함수역할:
# - 동일 제품의 정확한 이름을 보존하면서 서로 다른 완전 일치 제품도 유지하여 자동 확정을 막는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_same_product_upgrade_preserves_distinct_exact_products_without_downgrade():
    candidate = detail('펠로엔정', 'same-product')
    exact = detail(item_seq='same-product')
    other_exact = detail(item_seq='other-product')
    control = control_with_results(
        MedicationLookupResult([candidate]),
        MedicationLookupResult([exact, other_exact]),
        MedicationLookupResult([candidate]), MedicationLookupResult(),
    )
    response = await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert response.requires_confirmation and response.data == []
    assert response.candidates == [exact, other_exact]
    assert control._fetch_drug_info.await_count == 4


# 함수이름: test_ingredient_only_result_never_auto_matches
# 함수역할:
# - 성분명만 일치하는 후보는 모든 검색 모드에서 자동 확정하지 않는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_ingredient_only_result_never_auto_matches(mode):
    candidate = detail('펠로디핀', 'ingredient')
    control = control_with_results(*[MedicationLookupResult([candidate])] * 8)
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert response.success and response.requires_confirmation
    assert response.data == []
    assert response.candidates == [candidate]


# 함수이름: test_thorough_accumulates_deduplicates_and_limits_confirmation_candidates
# 함수역할:
# - thorough의 여러 조회 후보를 ID로 중복 제거하고 표시 후보를 다섯 개로 제한하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_thorough_accumulates_deduplicates_and_limits_confirmation_candidates():
    candidates = [detail('펠로엔정', str(index)) for index in range(8)]
    control = control_with_results(*[
        MedicationLookupResult(candidates[offset:offset + 3]) for offset in range(4)
    ])
    response = await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert response.requires_confirmation and response.data == []
    assert [item.item_seq for item in response.candidates] == ['0', '1', '2', '3', '4']
    assert control._fetch_drug_info.await_count == 4


# 함수이름: test_thorough_does_not_erase_multiple_exact_products_or_partial_failure
# 함수역할:
# - 후속 단일 결과가 앞선 복수 제품 일치나 부분 실패를 지우지 못하고 확인을 계속 요구하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_thorough_does_not_erase_multiple_exact_products_or_partial_failure():
    for first in [
        MedicationLookupResult([detail(item_seq='1'), detail(item_seq='2')]),
        MedicationLookupResult([detail()], is_complete=False),
        MedicationLookupResult([], is_complete=False),
    ]:
        control = control_with_results(first, *[MedicationLookupResult([detail()])] * 3)
        response = await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
        assert response.requires_confirmation and response.data == []
        assert control._fetch_drug_info.await_count == 4
        assert len(response.candidates) == (2 if len(first.details) == 2 else 1)


# 함수이름: test_strength_and_form_checks_use_original_not_corrected_or_broadened_name
# 함수역할:
# - 보정·확장 이름 대신 원본 함량과 제형으로 검증하여 충돌 후보를 모든 모드에서 제외하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# - unsafe_name: str; 원본과 함량·제형이 충돌하는 이름.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.parametrize('unsafe_name', [
    '펠로엔정10mg(펠로디핀)',
    '펠로엔캡슐5mg(펠로디핀)', '펠로엔서방정5mg(펠로디핀)',
])
@pytest.mark.anyio
async def test_strength_and_form_checks_use_original_not_corrected_or_broadened_name(
    mode, unsafe_name,
):
    original = '펠로엔정5mg(펠로디핀)'
    control = control_with_results()
    control._fetch_drug_info.side_effect = None
    control._fetch_drug_info.return_value = MedicationLookupResult([detail(unsafe_name)])
    response = await control.requestMedicationDetail(
        unsafe_name, original_text=original, search_mode=mode,
    )
    assert not response.success
    assert response.data == response.candidates == []
    assert response.review_reason == 'strength_or_form'
    assert all(
        call.kwargs['reference'] == original for call in control._fetch_drug_info.call_args_list
    )


# 함수이름: test_missing_strength_in_candidate_preserves_original_for_manual_confirmation
# 함수역할:
# - 후보에 함량이 없으면 원본 증거를 유지한 채 수동 확인 대상으로 반환하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_missing_strength_in_candidate_preserves_original_for_manual_confirmation(mode):
    original = '테스트정100mg'
    candidate = detail('테스트정')
    control = control_with_results()
    control._fetch_drug_info.side_effect = None
    control._fetch_drug_info.return_value = MedicationLookupResult([candidate])
    response = await control.requestMedicationDetail(
        candidate.item_name, original_text=original, search_mode=mode,
    )
    assert response.success and response.requires_confirmation
    assert response.data == []
    assert response.candidates == [candidate]
    assert all(
        call.kwargs['reference'] == original for call in control._fetch_drug_info.call_args_list
    )


# 함수이름: test_syrup_package_volume_reaches_manual_selection_from_every_source
# 함수역할:
# - 모든 데이터 경로에서 포장 용량이 붙은 시럽을 수동 선택 후보로 남기고 필요한 경우에만 요약하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# - source: str; 후보를 주입할 local·cache·basic·advanced 경로.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.parametrize('source', ['local', 'cache', 'basic', 'advanced'])
@pytest.mark.anyio
async def test_syrup_package_volume_reaches_manual_selection_from_every_source(mode, source):
    original, product = '시네츄라시럽_(15mL)', '시네츄라시럽'
    candidate = detail(product, 'synthetic-syrup')
    control, _ = control_with_empty_sources()
    # 조회·필터·응답 조립은 실제 코드를 사용하고 외부 데이터와 AI 요약만 대체한다.
    if source == 'local':
        control.local_medication_catalog.fetch_drug_info.side_effect = lambda query: (
            MedicationLookupResult([candidate] if query == product else [])
        )
    elif source == 'cache':
        control.medication_cache.get.side_effect = lambda key: (
            [candidate] if key == f'{original}|{product}' else None
        )
    elif source == 'basic':
        control.public_drug_small_api = SimpleNamespace(searchMedication=AsyncMock(
            side_effect=lambda query: [
                {'itemName': product, 'itemSeq': candidate.item_seq},
            ] if query == product else [],
        ))
    else:
        control.public_drug_large_api = SimpleNamespace(searchMedication=AsyncMock(
            side_effect=lambda query: [
                {'ITEM_NAME': product, 'ITEM_SEQ': candidate.item_seq},
            ] if query == product else [],
        ))
        control.summary_generator.summarize_advanced_item.return_value = candidate

    response = await control.requestMedicationDetail(original, search_mode=mode)
    assert response.success and response.requires_confirmation
    assert response.review_reason == 'ambiguous_product'
    assert response.data == []
    assert [(item.item_name, item.item_seq) for item in response.candidates] == [
        (product, candidate.item_seq),
    ]
    if source == 'advanced':
        control.summary_generator.summarize_advanced_item.assert_awaited_once()
    else:
        control.summary_generator.summarize_advanced_item.assert_not_awaited()


# 함수이름: test_lookup_errors_propagate_without_not_found_or_retries
# 함수역할:
# - 조회 오류를 재시도하거나 결과 없음으로 바꾸지 않고 같은 예외로 전파하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# - error: Exception; 조회 중 발생시킬 오류.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.parametrize('error', [
    ConnectionError('synthetic connection failure'), RuntimeError('synthetic provider failure'),
    httpx.ReadTimeout('synthetic HTTP timeout'), TimeoutError('synthetic deadline'),
])
@pytest.mark.anyio
async def test_lookup_errors_propagate_without_not_found_or_retries(mode, error):
    control = control_with_results(error)
    with pytest.raises(type(error)) as raised:
        await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert raised.value is error
    control._fetch_drug_info.assert_awaited_once()


# 함수이름: test_thorough_does_not_hide_error_after_a_candidate
# 함수역할:
# - thorough가 후보를 찾았더라도 후속 연결 오류를 성공 응답으로 숨기지 않는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_thorough_does_not_hide_error_after_a_candidate():
    control = control_with_results(
        MedicationLookupResult([detail('펠로엔정')]), ConnectionError('synthetic failure'),
    )
    with pytest.raises(ConnectionError):
        await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert control._fetch_drug_info.await_count == 2


# 함수이름: test_request_deadline_cancels_pending_lookup_and_is_not_not_found
# 함수역할:
# - 요청 제한 시간이 지나면 대기 조회를 취소하고 결과 없음 대신 TimeoutError를 전달하는지 확인한다.
# 매개변수:
# - mode: str; fast·balanced·thorough 중 검사할 검색 모드.
# 반환값:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_request_deadline_cancels_pending_lookup_and_is_not_not_found(mode):
    control = control_with_results()
    assert 0 < control.LOOKUP_TIMEOUT_SECONDS < 60
    control.LOOKUP_TIMEOUT_SECONDS = 0.01
    cancelled = False

    # 함수이름: stalled
    # 함수역할:
    # - 조회 완료를 지연하고 취소 여부를 finally에서 기록한다.
    # 매개변수:
    # - args: tuple; 사용하지 않는 조회 위치 인수.
    # - kwargs: dict; 사용하지 않는 조회 옵션.
    # 반환값:
    # - 정상 반환 없음; 호출자가 취소할 때까지 대기.
    async def stalled(*args, **kwargs):
        nonlocal cancelled
        try:
            await asyncio.Event().wait()
        finally:
            cancelled = True

    control._fetch_drug_info.side_effect = stalled
    with pytest.raises(TimeoutError):
        await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert cancelled
    control._fetch_drug_info.assert_awaited_once()


# 함수이름: test_deadline_is_shared_across_attempts_not_restarted
# 함수역할:
# - 여덟 번의 시도 전체가 하나의 50초 제한 시간을 공유하는지 확인한다.
# 매개변수:
# - monkeypatch: pytest.MonkeyPatch; 테스트 뒤 의존성 교체를 복원한다.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_deadline_is_shared_across_attempts_not_restarted(monkeypatch):
    control = control_with_results(*[MedicationLookupResult()] * 8)
    original_timeout = asyncio.timeout
    deadlines = []

    # 함수이름: track_timeout
    # 함수역할:
    # - 설정된 제한 시간을 기록한 뒤 원래 asyncio 시간 제한 문맥을 생성한다.
    # 매개변수:
    # - seconds: float; 요청 전체 제한 시간.
    # 반환값:
    # - asyncio.Timeout; 원래 함수가 생성한 시간 제한 문맥.
    def track_timeout(seconds):
        deadlines.append(seconds)
        return original_timeout(seconds)

    monkeypatch.setattr(asyncio, 'timeout', track_timeout)
    await control.requestMedicationDetail(VARIANT_PRODUCT, search_mode='thorough')
    assert deadlines == [50.0]
    assert control._fetch_drug_info.await_count == 8


# Function Name: test_default_control_passes_balanced_mode_to_the_normalizer
# Description:
# - Requires an omitted search mode to reach the normalizer explicitly as balanced.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_default_control_passes_balanced_mode_to_the_normalizer():
    control = control_with_results(MedicationLookupResult([detail()]))
    modes = []
    control.text_normalizer = SimpleNamespace(
        normalize_raw_text=lambda value: value,
        build_search_keywords=lambda value, *, search_mode: modes.append(search_mode) or [value],
    )
    response = await control.requestMedicationDetail(PRODUCT)
    assert response.data == [detail()]
    assert modes == ['balanced']


# 함수이름: test_invalid_control_mode_fails_before_any_lookup
# 함수역할:
# - 지원하지 않는 모드는 어떤 조회도 수행하기 전에 ValueError로 거부되는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
@pytest.mark.anyio
async def test_invalid_control_mode_fails_before_any_lookup():
    control = control_with_results()
    with pytest.raises(ValueError, match='search mode'):
        await control.requestMedicationDetail(PRODUCT, search_mode='unknown')
    control._fetch_drug_info.assert_not_awaited()


# Function Name: test_route_passes_the_default_mode_explicitly
# Description:
# - Requires both omitted and explicit balanced mode to reach the control through the route.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_route_passes_the_default_mode_explicitly():
    # Function Name: lookup
    # Description:
    # - Asserts the default raw text and balanced mode and returns one synthetic search result.
    # Parameters:
    # - raw_text: str; expected product search text.
    # - search_mode: str; expected balanced mode.
    # Returns:
    # - MedicationResponse; successful product result.
    async def lookup(raw_text, *, search_mode):
        assert raw_text == PRODUCT and search_mode == 'balanced'
        return MedicationResponse(success=True, message='synthetic', data=[detail()])

    control = SimpleNamespace(requestMedicationDetail=lookup)
    for fields in [{}, {'search_mode': 'balanced'}]:
        response = await identify_medication(
            MedicationRequest(extracted_text=PRODUCT, **fields), control, RecordingSearchCache(),
        )
        assert response.data == [detail()]


# Function Name: test_identify_http_contract_for_modes_and_original_evidence
# Description:
# - Checks that HTTP forwards the selected mode and original evidence, while an unknown mode returns 422 before control invocation.
# Parameters:
# - mode: str; search mode under test.
# Returns:
# - None.
@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_identify_http_contract_for_modes_and_original_evidence(mode):
    control = SimpleNamespace(requestMedicationDetail=AsyncMock(return_value=MedicationResponse(
        success=True, message='synthetic', data=[],
    )))
    app = FastAPI()
    app.post('/identify')(identify_medication)
    app.dependency_overrides[get_check_medication_detail] = lambda: control
    app.dependency_overrides[get_medication_search_cache] = RecordingSearchCache
    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url='http://test',
    ) as client:
        response = await client.post('/identify', json={
            'extracted_text': PRODUCT, 'original_text': '원본정5mg', 'search_mode': mode,
        })
        assert response.status_code == 200
        expected = {'original_text': '원본정5mg', 'search_mode': mode}
        control.requestMedicationDetail.assert_awaited_once_with(PRODUCT, **expected)
        invalid = await client.post('/identify', json={
            'extracted_text': PRODUCT, 'search_mode': 'unknown',
        })
        assert invalid.status_code == 422
        assert control.requestMedicationDetail.await_count == 1


# Function Name: test_route_remembers_returned_products_for_chat_attachments
# Description:
# - Requires returned products and candidates to be remembered for chat; cache failures must leave the search response unchanged.
# Parameters:
# - fail: bool; whether remembering the products raises an error.
# Returns:
# - None.
@pytest.mark.parametrize('fail', [False, True])
@pytest.mark.anyio
async def test_route_remembers_returned_products_for_chat_attachments(fail):
    # Function Name: lookup
    # Description:
    # - Returns one result and one confirmation candidate for chat-cache recording tests.
    # Parameters:
    # - raw_text: str; search text, unused.
    # - search_mode: str; requested mode, unused.
    # Returns:
    # - MedicationResponse; result and candidate with confirmation required.
    async def lookup(raw_text, *, search_mode):
        return MedicationResponse(
            success=True, message='synthetic', data=[detail()],
            candidates=[detail('후보정', '2')], requires_confirmation=True,
        )

    cache = RecordingSearchCache(fail=fail)
    response = await identify_medication(
        MedicationRequest(extracted_text=PRODUCT), SimpleNamespace(requestMedicationDetail=lookup), cache,
    )
    # 캐시 저장이 실패해도 검색 결과는 그대로 돌려준다.
    assert [item.item_seq for item in response.data + response.candidates] == ['1', '2']
    assert [item.item_seq for item in cache.remembered] == ([] if fail else ['1', '2'])


# 함수이름: test_route_preserves_failures_as_sanitized_http_errors
# 함수역할:
# - 조회 제한 시간은 504, 기타 실패는 500으로 매핑하고 비공개 오류 문구를 응답에서 제거하는지 확인한다.
# 매개변수:
# - error: Exception; 조회 중 발생시킬 오류.
# - status: int; 예상 HTTP 오류 상태.
# 반환값:
# - None.
@pytest.mark.parametrize('error,status', [
    (TimeoutError('private deadline'), 504),
    (ConnectionError('private connection error'), 500),
    (RuntimeError('private provider error'), 500),
])
@pytest.mark.anyio
async def test_route_preserves_failures_as_sanitized_http_errors(error, status):
    control = SimpleNamespace(requestMedicationDetail=AsyncMock(side_effect=error))
    with pytest.raises(HTTPException) as raised:
        await identify_medication(MedicationRequest(extracted_text=PRODUCT), control)
    assert raised.value.status_code == status
    assert 'private' not in raised.value.detail
