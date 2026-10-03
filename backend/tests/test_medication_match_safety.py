import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from controls.check_medication_detail_control import (
    CheckMedicationDetail, _MedicationNameMatcher, _MedicationTextNormalizer,
)
from entities.medication_detail_entity import MedicationDetail
from services.medication_match_safety import can_auto_match, match_conflict
from services.prescription_medication_name_verifier import (
    _CatalogMedicationName, _MedicationNameFallbackRequest,
    MedicationNameVerification, PrescriptionMedicationNameVerifier,
)


@pytest.mark.parametrize('original,candidate', [
    ('아스피린정 100mg', '아스피린정100밀리그람'),
    ('테스트정 0.1g', '테스트정100mg'),
    ('테스트정 .5mg', '테스트정500마이크로그램'),
    ('테스트정 1,000mg', '테스트정1그램'),
    ('테스트액 100mg/5ml', '테스트액20mg/ml'),
    ('테스트정 １０ｍｇ', '테스트정10mg'),
])
def test_equivalent_strengths(original, candidate):
    assert match_conflict(original, candidate) is None
    assert can_auto_match(original, candidate)


@pytest.mark.parametrize('original,candidate', [
    ('아스피린정 100mg', '바이엘아스피린정500밀리그람'),
    ('테스트정 100mg', '테스트정1000mg'),
    ('테스트정 100mg', '테스트정'),
    ('테스트정 100mg', '테스트정100mcg'),
    ('테스트정 100mg', '테스트정100ml'),
    ('테스트정 100mg', '테스트캡슐100mg'),
    ('테스트서방정 100mg', '테스트정100mg'),
    ('테스트정 100mg', '테스트장용정100mg'),
    ('테스트SR정100mg', '테스트정100mg'),
    ('테스트정 100mg/5mg', '테스트정100mg/10mg'),
    ('테스트액 100mg/5ml', '테스트액100mg/ml'),
    ('테스트액 100mg/0ml', '테스트액100mg/0ml'),
])
def test_unsafe_strength_or_form_is_excluded(original, candidate):
    assert match_conflict(original, candidate)
    assert not can_auto_match(original, candidate)
    assert _MedicationNameMatcher().calculate_score(original, candidate) == 0


def test_missing_strength_and_typo_require_confirmation():
    assert not can_auto_match('아스피린정', '바이엘아스피린정500밀리그람')
    assert not can_auto_match('에니코프캡슐300mg', '애니코프캡슐300mg')


def detail(name, item_seq='1'):
    return MedicationDetail(item_seq=item_seq, item_name=name,
                            efficacy='', usage_method='', warning='')


def control_with_results(results):
    control = object.__new__(CheckMedicationDetail)
    control.text_normalizer = _MedicationTextNormalizer()
    control.name_matcher = _MedicationNameMatcher()
    control._fetch_drug_info = AsyncMock(return_value=results)
    return control


def test_original_query_and_strength_survive_search_broadening():
    control = control_with_results([detail('바이엘아스피린정500밀리그람')])
    result = asyncio.run(control.requestMedicationDetail('아스피린정100mg'))
    assert not result.success
    assert result.data == result.candidates == []
    calls = control._fetch_drug_info.call_args_list
    assert calls[0].args == ('아스피린정100mg',)
    assert len(calls) <= 8
    assert all(call.kwargs['reference'] == '아스피린정100mg' for call in calls)


def test_ai_corrected_name_cannot_override_original_strength():
    control = control_with_results([detail('바이엘아스피린정500밀리그람')])
    result = asyncio.run(control.requestMedicationDetail(
        '바이엘아스피린정500밀리그람', original_text='아스피린정100mg',
    ))
    assert not result.success
    assert not result.data


def test_exact_product_is_automatic_but_fuzzy_result_is_review_only():
    name = '바이엘아스피린정500밀리그람'
    control = control_with_results([detail(name)])
    exact = asyncio.run(control.requestMedicationDetail(name))
    assert len(exact.data) == 1
    assert not exact.requires_confirmation
    ambiguous = asyncio.run(control.requestMedicationDetail('아스피린정'))
    assert ambiguous.success and ambiguous.requires_confirmation
    assert not ambiguous.data  # 구버전 앱도 첫 후보를 자동 저장하지 않는다.
    assert ambiguous.candidates[0].item_name == name


def test_same_name_different_product_ids_require_confirmation():
    control = control_with_results([detail('테스트정', '1'), detail('테스트정', '2')])
    result = asyncio.run(control.requestMedicationDetail('테스트정'))
    assert result.requires_confirmation
    assert len(result.candidates) == 2


@pytest.mark.parametrize('source', ['local', 'cache'])
def test_local_and_cached_wrong_strength_cannot_skip_public_lookup(source):
    control = object.__new__(CheckMedicationDetail)
    wrong = [detail('테스트정500mg')]
    control.name_matcher = _MedicationNameMatcher()
    control.local_medication_catalog = SimpleNamespace(
        fetch_drug_info=AsyncMock(return_value=wrong if source == 'local' else []))
    control.medication_cache = SimpleNamespace(
        get=AsyncMock(return_value=wrong if source == 'cache' else None),
        set=AsyncMock())
    control._fetch_public_drug_info = AsyncMock(return_value=[])
    control._enrich_missing_image_urls = AsyncMock(side_effect=lambda items: items)
    result = asyncio.run(control._fetch_drug_info('테스트정', reference='테스트정100mg'))
    assert result == []
    control._fetch_public_drug_info.assert_awaited_once()
    assert control.medication_cache.set.call_args.args[0] == '테스트정100mg|테스트정'


def test_ai_choice_cannot_override_strength_even_at_full_confidence():
    verifier = PrescriptionMedicationNameVerifier()
    candidate = _CatalogMedicationName('테스트정500mg', '테스트정500mg')
    result = verifier._select_ai_verified_corrections(
        {'corrections': [{'index': 0, 'corrected_name': candidate.item_name, 'confidence': 1}]},
        [_MedicationNameFallbackRequest(0, '테스트정100mg', [candidate])],
    )
    assert result == {}


def test_old_ai_cached_correction_is_rechecked():
    verifier = PrescriptionMedicationNameVerifier()
    candidate = _CatalogMedicationName('테스트정500mg', '테스트정500mg')
    original = MedicationNameVerification('테스트정100mg', '테스트정100mg', 0, 'unverified')
    request = _MedicationNameFallbackRequest(0, original.raw_name, [candidate])
    verifier._requires_current_thread_session = lambda: True
    verifier._prepare_verifications = lambda _: ([original], [request])
    verifier._resolve_cached_fallbacks = lambda *_: ({0: (candidate, 1.0)}, [])
    result = asyncio.run(verifier.verify_many([original.raw_name], object(), 'test'))
    assert result == [original]


def test_local_prefix_match_cannot_turn_100_into_1000():
    verifier = PrescriptionMedicationNameVerifier(db=object())
    verifier._find_catalog_match = lambda _: (object(), '테스트정1000mg')
    result = verifier.verify('테스트정100mg')
    assert result.canonical_name == '테스트정100mg'
    assert result.source == 'unverified'


def test_identical_names_without_ids_keep_different_manufacturers():
    control = control_with_results([
        detail('테스트정', '').model_copy(update={'manufacturer': 'A'}),
        detail('테스트정', '').model_copy(update={'manufacturer': 'B'}),
    ])
    result = asyncio.run(control.requestMedicationDetail('테스트정'))
    assert result.requires_confirmation
    assert len(result.candidates) == 2
