# 파일명: test_medication_match_safety.py
# 역할: 약품명 비교의 원본 함량·제형 보존과 자동 확정·수동 확인 경계를 검증한다.

import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from controls.check_medication_detail_control import CheckMedicationDetail
from services.medication_name_matching import (
    MedicationNameMatcher,
    MedicationTextNormalizer,
)
from entities.medication_detail_entity import MedicationDetail
from entities.medication_lookup_result import MedicationLookupResult
from services.medication_match_safety import can_auto_match, match_conflict
from services.prescription_medication_name_verifier import (
    _CatalogMedicationName, _MedicationNameFallbackRequest,
    MedicationNameVerification, PrescriptionMedicationNameVerifier,
)


# 함수이름: test_equivalent_strengths
# 함수역할:
# - 동등한 단위의 함량 표기는 충돌이 없으며 자동 일치를 허용하는지 확인한다.
# 매개변수:
# - original: str; 원본 약품명과 함량·제형 증거.
# - candidate: str; 비교할 후보 약품명.
# 반환값:
# - None.
@pytest.mark.parametrize('original,candidate', [
    ('아스피린정 100mg', '아스피린정100밀리그람'),
    ('테스트정 0.1g', '테스트정100mg'),
    ('테스트정 .5mg', '테스트정500마이크로그램'),
    ('테스트정 1,000mg', '테스트정1그램'),
    ('테스트액 100mg/5ml', '테스트액20mg/ml'),
    ('테스트정 １０ｍｇ', '테스트정10mg'),
    ('아모잘탄정 5/50mg', '아모잘탄정5/50밀리그램'),
    ('세비카에이치씨티정 5/20/12.5mg', '세비카에이치씨티정5/20/12.5밀리그램'),
    ('테스트시럽 5mg/5ml', '테스트시럽1mg/ml'),
])
def test_equivalent_strengths(original, candidate):
    assert match_conflict(original, candidate) is None
    assert can_auto_match(original, candidate)


# Function Name: test_unsafe_strength_or_form_is_excluded
# Description:
# - Requires conflicting strength or dosage form to block auto-matching and receive a zero ranking score.
# Parameters:
# - original: str; original product name, strength and form.
# - candidate: str; conflicting candidate name.
# Returns:
# - None.
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
    ('아모잘탄정5/50mg', '아모잘탄정10/50밀리그램'),
    ('아모잘탄정 5 / 50 mg', '아모잘탄정5/100밀리그램'),
    ('세비카에이치씨티정5/20/12.5mg', '세비카에이치씨티정10/20/12.5밀리그램'),
    ('트윈스타정40/5mg', '트윈스타정80/5밀리그램'),
    ('아모잘탄정50mg', '아모잘탄정5/50밀리그램'),
    ('아모잘탄정5/50mg', '아모잘탄정50밀리그램'),
])
def test_unsafe_strength_or_form_is_excluded(original, candidate):
    assert match_conflict(original, candidate)
    assert not can_auto_match(original, candidate)
    assert MedicationNameMatcher().calculate_score(original, candidate) == 0


# Function Name: test_combination_check_only_adds_conflicts
# Description:
# - Keeps the pairs that conflicted before the combination check in conflict: the same components
#   written with the unit on every number, or in another order, are still not matched.
# Parameters:
# - original (str): Prescription name with a unit only after the last component.
# - candidate (str): Catalogue-style name in another notation.
# Returns:
# - None; fails if reading every component relaxes an existing strength conflict.
@pytest.mark.parametrize('original,candidate', [
    ('아모잘탄정5/50mg', '아모잘탄정5mg/50mg'),
    ('아모잘탄정5mg/50mg', '아모잘탄정5/50밀리그램'),
    ('아모잘탄정5/50mg', '아모잘탄정50/5밀리그램'),
])
def test_combination_check_only_adds_conflicts(original, candidate) -> None:
    assert match_conflict(original, candidate) == 'strength_mismatch'
    assert not can_auto_match(original, candidate)


# 함수이름: test_missing_strength_and_typo_require_confirmation
# 함수역할:
# - 함량이 누락되거나 제품명 오타가 있으면 자동 확정하지 않는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_missing_strength_and_typo_require_confirmation():
    assert not can_auto_match('아스피린정', '바이엘아스피린정500밀리그람')
    assert not can_auto_match('에니코프캡슐300mg', '애니코프캡슐300mg')


# 함수이름: test_missing_strength_is_only_allowed_for_manual_candidates
# 함수역할:
# - 함량 미확인 후보는 명시적으로 수동 후보를 허용할 때만 순위에 포함하고 자동 확정하지 않는지 확인한다.
# 매개변수:
# - original: str; 원본 약품명과 함량·제형 증거.
# - candidate: str; 비교할 후보 약품명.
# 반환값:
# - None.
@pytest.mark.parametrize('original,candidate', [
    ('시네츄라시럽_(15mL)', '시네츄라시럽'),
    ('테스트정100mg', '테스트정'),
])
def test_missing_strength_is_only_allowed_for_manual_candidates(original, candidate):
    matcher = MedicationNameMatcher()
    assert match_conflict(original, candidate) == 'strength_unknown'
    assert not matcher.rank_candidates(original, [candidate], str, 5)
    assert matcher.rank_candidates(
        original, [candidate], str, 5, allow_unknown_strength=True,
    ) == [candidate]
    assert not can_auto_match(original, candidate)


# 함수이름: test_manual_candidates_still_reject_conflicts_and_unrelated_names
# 함수역할:
# - 수동 후보 허용도 함량·제형 충돌과 관련 없는 제품명은 통과시키지 않는지 확인한다.
# 매개변수:
# - original: str; 원본 약품명과 함량·제형 증거.
# - candidate: str; 비교할 후보 약품명.
# 반환값:
# - None.
@pytest.mark.parametrize('original,candidate', [
    ('테스트정100mg', '테스트정500mg'),
    ('테스트정100mg', '테스트캡슐'),
    ('테스트서방정100mg', '테스트정'),
    ('시네츄라시럽_(15mL)', '시네츄라캡슐'),
    ('테스트액100mg/0ml', '테스트액'),
    ('테스트정5/50mg', '테스트정10/50mg'),
    ('시네츄라시럽_(15mL)', '전혀다른약품정'),
])
def test_manual_candidates_still_reject_conflicts_and_unrelated_names(original, candidate):
    assert not MedicationNameMatcher().rank_candidates(
        original, [candidate], str, 5, allow_unknown_strength=True,
    )
    assert not can_auto_match(original, candidate)


# Function Name: test_equal_strength_gets_the_same_bonus_in_any_notation
# Description:
# - Scores a typo candidate the same whether the equal strength is written in the catalogue's
#   unit or in another one; the bonus follows medication_match_safety and there is no penalty.
# Parameters:
# - search_text (str): OCR name whose strength equals 500 mg in some notation.
# Returns:
# - None; fails if an equal strength in another notation lowers the score again.
@pytest.mark.parametrize('search_text', [
    '타이래놀정500mg', '타이래놀정0.5g', '타이래놀정500.0mg', '타이래놀정５００ｍｇ',
])
def test_equal_strength_gets_the_same_bonus_in_any_notation(search_text) -> None:
    matcher = MedicationNameMatcher()
    assert matcher.calculate_score(search_text, '타이레놀정500밀리그램') == pytest.approx(0.95)
    assert matcher._adjust_dosage_score(0.8, search_text, '타이레놀정500밀리그램') == pytest.approx(0.83)


# Function Name: test_missing_strength_gets_no_bonus_and_no_penalty
# Description:
# - Leaves the name score unchanged when the search text states no strength.
# Parameters:
# - None.
# Returns:
# - None.
def test_missing_strength_gets_no_bonus_and_no_penalty() -> None:
    matcher = MedicationNameMatcher()
    assert matcher.calculate_score('타이래놀정', '타이레놀정500밀리그램') == pytest.approx(0.92)
    assert matcher._adjust_dosage_score(0.8, '타이래놀정', '타이레놀정500밀리그램') == 0.8
    assert matcher._adjust_dosage_score(0.8, '타이래놀정', '타이레놀정') == 0.8


# 함수이름: detail
# 함수역할:
# - 이름과 제품 ID만 구분되는 빈 설명의 합성 약품 상세를 생성한다.
# 매개변수:
# - name: str; 합성 약품명.
# - item_seq: str; 합성 제품 ID.
# 반환값:
# - MedicationDetail; 후보 비교용 상세.
def detail(name, item_seq='1'):
    return MedicationDetail(item_seq=item_seq, item_name=name,
                            efficacy='', usage_method='', warning='')


# 함수이름: control_with_results
# 함수역할:
# - 실제 이름 정규화·매칭에 고정 후보를 반환하는 비동기 조회 대역을 연결한다.
# 매개변수:
# - results: list[MedicationDetail]; 대체 조회가 반환할 후보.
# 반환값:
# - CheckMedicationDetail; 외부 조회가 교체된 컨트롤.
def control_with_results(results):
    control = object.__new__(CheckMedicationDetail)
    control.text_normalizer = MedicationTextNormalizer()
    control.name_matcher = MedicationNameMatcher()
    control._fetch_drug_info = AsyncMock(return_value=MedicationLookupResult(results))
    return control


# 함수이름: test_original_query_and_strength_survive_search_broadening
# 함수역할:
# - 검색어를 넓혀도 모든 조회에 원본 함량을 전달하여 잘못된 후보를 제외하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_original_query_and_strength_survive_search_broadening():
    control = control_with_results([detail('바이엘아스피린정500밀리그람')])
    result = asyncio.run(control.requestMedicationDetail('아스피린정100mg'))
    assert not result.success
    assert result.data == result.candidates == []
    calls = control._fetch_drug_info.call_args_list
    assert calls[0].args == ('아스피린정100mg',)
    assert len(calls) <= 8
    assert all(call.kwargs['reference'] == '아스피린정100mg' for call in calls)


# 함수이름: test_ai_corrected_name_cannot_override_original_strength
# 함수역할:
# - AI 보정된 이름이 원본 함량 검증을 덮어쓰지 못하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_ai_corrected_name_cannot_override_original_strength():
    control = control_with_results([detail('바이엘아스피린정500밀리그람')])
    result = asyncio.run(control.requestMedicationDetail(
        '바이엘아스피린정500밀리그람', original_text='아스피린정100mg',
    ))
    assert not result.success
    assert not result.data


# 함수이름: test_exact_product_is_automatic_but_fuzzy_result_is_review_only
# 함수역할:
# - 정확한 제품만 자동 반환하고 모호한 이름은 구버전 자동 저장을 막도록 data 대신 확인 후보에 넣는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
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


# 함수이름: test_same_name_different_product_ids_require_confirmation
# 함수역할:
# - 이름이 같아도 제품 ID가 다르면 둘 다 보존하고 사용자 확인을 요구하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_same_name_different_product_ids_require_confirmation():
    control = control_with_results([detail('테스트정', '1'), detail('테스트정', '2')])
    result = asyncio.run(control.requestMedicationDetail('테스트정'))
    assert result.requires_confirmation
    assert len(result.candidates) == 2


# 함수이름: test_local_and_cached_wrong_strength_cannot_skip_public_lookup
# 함수역할:
# - 로컬·캐시의 잘못된 함량 후보는 공공 조회를 생략하지 못하고 캐시 키도 원본 근거를 포함하는지 확인한다.
# 매개변수:
# - source: str; 잘못된 함량을 주입할 local 또는 cache 경로.
# 반환값:
# - None.
@pytest.mark.parametrize('source', ['local', 'cache'])
def test_local_and_cached_wrong_strength_cannot_skip_public_lookup(source):
    control = object.__new__(CheckMedicationDetail)
    wrong = [detail('테스트정500mg')]
    control.name_matcher = MedicationNameMatcher()
    control.local_medication_catalog = SimpleNamespace(
        fetch_drug_info=AsyncMock(return_value=MedicationLookupResult(
            wrong if source == 'local' else [])))
    control.medication_cache = SimpleNamespace(
        get=AsyncMock(return_value=wrong if source == 'cache' else None),
        set=AsyncMock())
    control._fetch_public_drug_info = AsyncMock(return_value=MedicationLookupResult())
    control._enrich_missing_image_urls = AsyncMock(side_effect=lambda items: items)
    result = asyncio.run(control._fetch_drug_info('테스트정', reference='테스트정100mg'))
    assert result.details == []
    assert result.is_complete
    control._fetch_public_drug_info.assert_awaited_once()
    assert control.medication_cache.set.call_args.args[0] == '테스트정100mg|테스트정'


# Function Name: test_ai_choice_cannot_override_strength_even_at_full_confidence
# Description:
# - Rejects an AI-selected strength conflict even when the model reports full confidence.
# Parameters:
# - None.
# Returns:
# - None.
def test_ai_choice_cannot_override_strength_even_at_full_confidence():
    verifier = PrescriptionMedicationNameVerifier()
    candidate = _CatalogMedicationName('테스트정500mg', '테스트정500mg')
    result = verifier._select_ai_verified_corrections(
        {'corrections': [{'index': 0, 'corrected_name': candidate.item_name, 'confidence': 1}]},
        [_MedicationNameFallbackRequest(0, '테스트정100mg', [candidate])],
    )
    assert result == {}


# Function Name: test_ai_correction_is_rechecked_before_it_is_applied
# Description:
# - Rechecks AI correction safety before applying it and preserves the original verification on strength conflict.
# Parameters:
# - None.
# Returns:
# - None.
def test_ai_correction_is_rechecked_before_it_is_applied():
    verifier = PrescriptionMedicationNameVerifier()
    candidate = _CatalogMedicationName('테스트정500mg', '테스트정500mg')
    original = MedicationNameVerification('테스트정100mg', '테스트정100mg', 0, 'unverified')
    request = _MedicationNameFallbackRequest(0, original.raw_name, [candidate])
    verifier._requires_current_thread_session = lambda: True
    verifier._prepare_verifications = lambda _: ([original], [request])
    verifier._request_ai_catalog_choices = AsyncMock(return_value={0: (candidate, 1.0)})
    result = asyncio.run(verifier.verify_many([original.raw_name], object(), 'test'))
    assert result == [original]
    verifier._request_ai_catalog_choices.assert_awaited_once()


# Function Name: test_local_prefix_match_cannot_turn_100_into_1000
# Description:
# - Rejects a fabricated prefix match with incompatible strength while composing with a valid session binding.
# Parameters:
# - None.
# Returns:
# - None; only match discovery is stubbed, never the production session ownership contract.
def test_local_prefix_match_cannot_turn_100_into_1000() -> None:
    engine = create_engine('sqlite:///:memory:')
    try:
        with Session(engine) as db:
            verifier = PrescriptionMedicationNameVerifier(db=db)
            verifier._find_catalog_match = lambda _: (object(), '테스트정1000mg')
            result = verifier.verify('테스트정100mg')
            assert result.canonical_name == '테스트정100mg'
            assert result.source == 'unverified'
    finally:
        engine.dispose()


# 함수이름: test_identical_names_without_ids_keep_different_manufacturers
# 함수역할:
# - 제품 ID가 없어도 제조사가 다른 동일 이름 제품을 합치지 않고 확인 후보 둘로 보존하는지 확인한다.
# 매개변수:
# - 없음.
# 반환값:
# - None.
def test_identical_names_without_ids_keep_different_manufacturers():
    control = control_with_results([
        detail('테스트정', '').model_copy(update={'manufacturer': 'A'}),
        detail('테스트정', '').model_copy(update={'manufacturer': 'B'}),
    ])
    result = asyncio.run(control.requestMedicationDetail('테스트정'))
    assert result.requires_confirmation
    assert len(result.candidates) == 2
