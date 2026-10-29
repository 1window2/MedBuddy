"""검색 모드의 범위·시간 예산과 원본 증거 기반 확인 규칙을 외부 전송 없이 검증한다."""

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from pydantic import ValidationError

from api.dependencies import get_check_medication_detail
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


def detail(name=PRODUCT, item_seq='1'):
    return MedicationDetail(
        item_name=name, item_seq=item_seq, efficacy='', usage_method='', warning='',
    )


def control_with_results(*results):
    control = object.__new__(CheckMedicationDetail)
    control.text_normalizer = MedicationTextNormalizer()
    control.name_matcher = MedicationNameMatcher()
    control._fetch_drug_info = AsyncMock(side_effect=list(results))
    return control


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


def test_schema_defaults_to_balanced_and_accepts_only_named_modes():
    assert MedicationRequest(extracted_text=PRODUCT).search_mode == 'balanced'
    for mode in MODES:
        assert MedicationRequest(search_mode=mode).search_mode == mode
    for invalid in ['slow', 'FAST', '', None, 1]:
        with pytest.raises(ValidationError):
            MedicationRequest(search_mode=invalid)


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


def test_fast_does_not_search_ingredients_or_ocr_variants():
    normalizer = MedicationTextNormalizer()
    assert normalizer.build_search_keywords(PRODUCT, search_mode='fast') == [
        PRODUCT, '펠로엔정',
    ]
    assert normalizer.build_search_keywords('에니코프', search_mode='fast') == ['에니코프']
    assert normalizer.build_search_keywords('(펠로디핀)', search_mode='fast') == ['(펠로디핀)']


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


@pytest.mark.parametrize('mode,budget', [('fast', 2), ('balanced', 4), ('thorough', 8)])
@pytest.mark.anyio
async def test_mode_attempt_budgets_are_sequential_and_keep_full_evidence(mode, budget):
    control = control_with_results()
    calls = []
    active = 0

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


@pytest.mark.anyio
async def test_thorough_summarises_each_advanced_product_once_per_request():
    control, transport = control_with_empty_sources()
    candidate = {'ITEM_SEQ': '9', 'ITEM_NAME': '펠로엔정'}

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


@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_single_complete_exact_product_exits_immediately(mode):
    control = control_with_results(MedicationLookupResult([detail()]))
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert response.data == [detail()]
    control._fetch_drug_info.assert_awaited_once()


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


@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_ingredient_only_result_never_auto_matches(mode):
    candidate = detail('펠로디핀', 'ingredient')
    control = control_with_results(*[MedicationLookupResult([candidate])] * 8)
    response = await control.requestMedicationDetail(PRODUCT, search_mode=mode)
    assert response.success and response.requires_confirmation
    assert response.data == []
    assert response.candidates == [candidate]


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


@pytest.mark.anyio
async def test_thorough_does_not_hide_error_after_a_candidate():
    control = control_with_results(
        MedicationLookupResult([detail('펠로엔정')]), ConnectionError('synthetic failure'),
    )
    with pytest.raises(ConnectionError):
        await control.requestMedicationDetail(PRODUCT, search_mode='thorough')
    assert control._fetch_drug_info.await_count == 2


@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_request_deadline_cancels_pending_lookup_and_is_not_not_found(mode):
    control = control_with_results()
    assert 0 < control.LOOKUP_TIMEOUT_SECONDS < 60
    control.LOOKUP_TIMEOUT_SECONDS = 0.01
    cancelled = False

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


@pytest.mark.anyio
async def test_deadline_is_shared_across_attempts_not_restarted(monkeypatch):
    control = control_with_results(*[MedicationLookupResult()] * 8)
    original_timeout = asyncio.timeout
    deadlines = []

    def track_timeout(seconds):
        deadlines.append(seconds)
        return original_timeout(seconds)

    monkeypatch.setattr(asyncio, 'timeout', track_timeout)
    await control.requestMedicationDetail(VARIANT_PRODUCT, search_mode='thorough')
    assert deadlines == [50.0]
    assert control._fetch_drug_info.await_count == 8


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


@pytest.mark.anyio
async def test_invalid_control_mode_fails_before_any_lookup():
    control = control_with_results()
    with pytest.raises(ValueError, match='search mode'):
        await control.requestMedicationDetail(PRODUCT, search_mode='unknown')
    control._fetch_drug_info.assert_not_awaited()


@pytest.mark.anyio
async def test_route_passes_the_default_mode_explicitly():
    async def lookup(raw_text, *, search_mode):
        assert raw_text == PRODUCT and search_mode == 'balanced'
        return MedicationResponse(success=True, message='synthetic', data=[detail()])

    control = SimpleNamespace(requestMedicationDetail=lookup)
    for fields in [{}, {'search_mode': 'balanced'}]:
        response = await identify_medication(
            MedicationRequest(extracted_text=PRODUCT, **fields), control,
        )
        assert response.data == [detail()]


@pytest.mark.parametrize('mode', MODES)
@pytest.mark.anyio
async def test_identify_http_contract_for_modes_and_original_evidence(mode):
    control = SimpleNamespace(requestMedicationDetail=AsyncMock(return_value=MedicationResponse(
        success=True, message='synthetic', data=[],
    )))
    app = FastAPI()
    app.post('/identify')(identify_medication)
    app.dependency_overrides[get_check_medication_detail] = lambda: control
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
