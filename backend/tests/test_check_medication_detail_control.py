# File Name: test_check_medication_detail_control.py
# Role: Regression coverage for medication-name matching, image lookup, summary timeouts, and
#   cache failures.
import asyncio
import os
import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from api import dependencies as api_dependencies
from boundaries.public_drug_api_boundary import (
    PillImageAPI,
    _PublicDrugTransport,
    read_public_image_url,
)
from core.config import settings
from controls.check_medication_detail_control import (
    CheckMedicationDetail,
    _MedicationDetailCache,
    _MedicationNameMatcher,
    _MedicationSummaryGenerator,
    _MedicationTextNormalizer,
    _read_text,
)
from entities.medication_detail_entity import MedicationDetail


# Class Name: _FailingRedisClient
# Role: Redis failure double that counts reads, rejects cache operations, and records closure.
# Responsibilities:
# - Counts Redis reads and raises connection errors for both get and setex.
# - Records client closure so cleanup remains verifiable after cache failure.
# Attributes:
# - get_calls (int): Number of attempted Redis reads.
# - closed (bool): Whether the simulated client has been closed.
class _FailingRedisClient:
    # Function Name: __init__
    # Description:
    # - Starts the Redis read count at zero and marks the client as open.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.get_calls = 0
        self.closed = False

    # 함수이름: get
    # 함수역할:
    # - 조회 횟수를 늘린 뒤 연결 오류를 발생시켜 반복 Redis 접근 차단을 검증하게 한다.
    # 매개변수:
    # - key (str): Redis 약 상세 캐시의 조회 또는 저장 키.
    # 반환값:
    # - 정상 반환 없음. 위에 명시한 실패를 예외로 전달함.
    async def get(self, key: str) -> str:
        self.get_calls += 1
        raise ConnectionError("redis unavailable")

    # 함수이름: setex
    # 함수역할:
    # - 캐시 저장 시 연결 오류를 발생시켜 Redis 쓰기 장애를 재현한다.
    # 매개변수:
    # - key (str): Redis 약 상세 캐시의 조회 또는 저장 키.
    # - ttl (int): 초 단위 캐시 만료 간격.
    # - value (str): Redis 쓰기 인터페이스에 전달할 캐시 값.
    # 반환값:
    # - 정상 반환 없음. 위에 명시한 실패를 예외로 전달함.
    async def setex(self, key: str, ttl: int, value: str) -> None:
        raise ConnectionError("redis unavailable")

    # Function Name: aclose
    # Description:
    # - Marks the Redis client as closed without contacting a server.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def aclose(self) -> None:
        self.closed = True


# Class Name: _CloseFailingMedicationCache
# Role: Medication cache double whose cleanup fails to exercise process-state reset and logging.
# Responsibilities:
# - Raises a Redis connection error during cache closure.
class _CloseFailingMedicationCache:
    # Function Name: close
    # Description:
    # - Raises a Redis connection error during cache closure.
    # Parameters:
    # - None.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def close(self) -> None:
        raise ConnectionError("redis close failed")


# 함수이름: anyio_backend
# 함수역할:
# - 비동기 테스트가 asyncio 실행기를 사용하도록 고정한다.
# 매개변수:
# - 없음.
# 반환값:
# - str: 테스트 이벤트 루프 실행기로 선택한 'asyncio'.
@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


# 함수이름: test_build_search_keywords_splits_product_and_ingredient_names
# 함수역할:
# - 제품명·괄호 포함 원문·성분명이 기대 순서의 검색어로 분리되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_build_search_keywords_splits_product_and_ingredient_names() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("켈로인(펠루비프로펜)")

    assert search_keywords == [
        "켈로인",
        "켈로인(펠루비프로펜)",
        "펠루비프로펜",
    ]


# Function Name: test_split_parenthesized_text_uses_linear_scan
# Description:
# - Separates text outside parentheses from the enclosed candidate while retaining surrounding
#   words.
# Parameters:
# - None.
# Returns:
# - None.
def test_split_parenthesized_text_uses_linear_scan() -> None:
    normalizer = _MedicationTextNormalizer()

    outside_text, parenthesized_candidates = normalizer._split_parenthesized_text(
        "Alpha(Beta) Gamma"
    )

    assert outside_text == "Alpha Gamma"
    assert parenthesized_candidates == ["Beta"]


# Function Name: test_split_parenthesized_text_ignores_oversized_parentheses
# Description:
# - Requires oversized parenthesized content to be discarded while preserving surrounding
#   product text.
# Parameters:
# - None.
# Returns:
# - None.
def test_split_parenthesized_text_ignores_oversized_parentheses() -> None:
    normalizer = _MedicationTextNormalizer()

    outside_text, parenthesized_candidates = normalizer._split_parenthesized_text(
        "Alpha(" + ("B" * 10000) + ") Gamma"
    )

    assert outside_text == "Alpha Gamma"
    assert parenthesized_candidates == []


# Function Name: test_split_parenthesized_text_preserves_nested_groups
# Description:
# - Requires nested parentheses to remain part of the extracted ingredient candidate.
# Parameters:
# - None.
# Returns:
# - None.
def test_split_parenthesized_text_preserves_nested_groups() -> None:
    normalizer = _MedicationTextNormalizer()

    outside_text, parenthesized_candidates = normalizer._split_parenthesized_text(
        "Drug((ingredient)) 20mg"
    )

    assert outside_text == "Drug 20mg"
    assert parenthesized_candidates == ["(ingredient)"]


# 함수이름: test_build_search_keywords_strips_korean_dosage_unit
# 함수역할:
# - 한국어 용량 표기를 제거한 제품명과 제형을 줄인 이름이 원문보다 먼저 검색되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_build_search_keywords_strips_korean_dosage_unit() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("에니코프캡슐300밀리그램")

    assert search_keywords[:3] == [
        "에니코프캡슐",
        "에니코프",
        "에니코프캡슐300밀리그램",
    ]


# 함수이름: test_build_search_keywords_adds_hangul_ocr_vowel_variants
# 함수역할:
# - 한글 OCR 모음 혼동을 보정한 애니코프 후보가 검색어에 포함되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_build_search_keywords_adds_hangul_ocr_vowel_variants() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("에니코프캡슐300밀리그램")

    assert "애니코프" in search_keywords


# 함수이름: test_build_search_keywords_removes_known_manufacturer_prefix
# 함수역할:
# - 알려진 제조사 접두어가 있는 원문과 접두어를 제거한 성분명 모두 검색어에 포함되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_build_search_keywords_removes_known_manufacturer_prefix() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords(
        "대웅바이오클래리트로마이신정250mg"
    )

    assert "대웅바이오클래리트로마이신" in search_keywords
    assert "클래리트로마이신" in search_keywords


# Function Name: test_build_search_keywords_caps_parenthesized_request_amplification
# Description:
# - Caps generated search keywords at 24 to prevent parenthesized input from amplifying external
#   requests.
# Parameters:
# - None.
# Returns:
# - None.
def test_build_search_keywords_caps_parenthesized_request_amplification() -> None:
    normalizer = _MedicationTextNormalizer()
    crafted_name = "drug" + "".join(
        f"({chr(codepoint)})" for codepoint in range(ord("a"), ord("z") + 1)
    )

    search_keywords = normalizer.build_search_keywords(crafted_name)

    assert len(search_keywords) <= 24


# 함수이름: test_name_matcher_accepts_parenthesized_ingredient_and_dosage
# 함수역할:
# - 괄호 성분명과 용량이 추가된 동일 약품을 0.9 이상 점수의 확실한 일치로 판정하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_name_matcher_accepts_parenthesized_ingredient_and_dosage() -> None:
    matcher = _MedicationNameMatcher()

    score = matcher.calculate_score(
        "켈로인정(펠루비프로펜)",
        "켈로인정30밀리그램(펠루비프로펜)",
    )

    assert score >= 0.90
    assert matcher.is_confident_match(
        "켈로인정(펠루비프로펜)",
        "켈로인정30밀리그램(펠루비프로펜)",
    )


# 함수이름: test_name_matcher_accepts_one_character_error_in_long_name
# 함수역할:
# - 긴 약품명의 한 글자 OCR 오류를 동일 약품의 확실한 일치로 허용하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_name_matcher_accepts_one_character_error_in_long_name() -> None:
    matcher = _MedicationNameMatcher()

    assert matcher.is_confident_match(
        "클래리트로마이산",
        "클래리트로마이신정250밀리그램",
    )


# 함수이름: test_name_matcher_rejects_unrelated_medication_name
# 함수역할:
# - 아스피린과 타이레놀처럼 무관한 약품명을 확실한 일치로 판정하지 않는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_name_matcher_rejects_unrelated_medication_name() -> None:
    matcher = _MedicationNameMatcher()

    assert not matcher.is_confident_match("아스피린정", "타이레놀정")


# 함수이름: test_name_matcher_ranks_best_candidate_first
# 함수역할:
# - 가장 유사한 약품을 첫 후보로 정렬하고 무관한 성분의 후보를 제외하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_name_matcher_ranks_best_candidate_first() -> None:
    matcher = _MedicationNameMatcher()
    candidates = [
        {"itemName": "클래리트로마이신정500밀리그램"},
        {"itemName": "아목시실린캡슐500밀리그램"},
        {"itemName": "클래리트로마이산정250밀리그램"},
    ]

    ranked_candidates = matcher.rank_candidates(
        "클래리트로마이신정250밀리그램",
        candidates,
        lambda item: item["itemName"],
        limit=3,
    )

    assert ranked_candidates[0]["itemName"] == "클래리트로마이산정250밀리그램"
    assert all("아목시실린" not in item["itemName"] for item in ranked_candidates)


# 함수이름: test_read_text_replaces_missing_public_api_fields
# 함수역할:
# - 누락·빈 공공 API 문자열에는 기본 안내를 적용하고 명시한 빈 대체값은 유지하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_read_text_replaces_missing_public_api_fields() -> None:
    assert _read_text(None) == "정보 없음"
    assert _read_text("") == "정보 없음"
    assert _read_text(None, "") == ""


# Function Name: test_public_medication_image_url_accepts_documented_aliases
# Description:
# - Accepts documented image-field aliases and normalizes protocol-relative MFDS image URLs to
#   HTTPS.
# Parameters:
# - None.
# Returns:
# - None.
def test_public_medication_image_url_accepts_documented_aliases() -> None:
    assert (
        read_public_image_url(
            {"itemImage": "https://nedrug.mfds.go.kr/pill.png"}
        )
        == "https://nedrug.mfds.go.kr/pill.png"
    )
    assert (
        read_public_image_url({"ITEM_IMAGE": "//nedrug.mfds.go.kr/pill.png"})
        == "https://nedrug.mfds.go.kr/pill.png"
    )


# Function Name: test_public_medication_image_url_rejects_non_network_schemes
# Description:
# - Rejects inline, executable, malformed, insecure, foreign-host, and credential-bearing
#   medication image URLs.
# Parameters:
# - None.
# Returns:
# - None.
def test_public_medication_image_url_rejects_non_network_schemes() -> None:
    assert read_public_image_url({"itemImage": "data:image/png;base64,abc"}) == ""
    assert read_public_image_url({"imageUrl": "javascript:alert(1)"}) == ""
    assert read_public_image_url({"imageUrl": "https://[invalid"}) == ""
    assert read_public_image_url({"imageUrl": "http://nedrug.mfds.go.kr/a"}) == ""
    assert read_public_image_url({"imageUrl": "https://example.com/a"}) == ""
    assert (
        read_public_image_url(
            {"imageUrl": "https://user:pass@nedrug.mfds.go.kr/a"}
        )
        == ""
    )


# Function Name: test_pill_image_lookup_requires_an_exact_medication_match
# Description:
# - Selects the exact product-name image instead of a longer-name match and caches the lookup
#   across repeated requests.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_pill_image_lookup_requires_an_exact_medication_match(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)
    request_count = 0

    # Function Name: fake_request_items
    # Description:
    # - Checks the identification endpoint and requested name, then returns exact and
    #   misleading image candidates while counting calls.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # Returns:
    # - tuple[list[dict[str, object]], int]: Configured drug rows and the advertised total
    #   count.
    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        nonlocal request_count
        request_count += 1
        assert url.endswith("getMdcinGrnIdntfcInfoList03")
        assert params["item_name"] == "테스트정"
        return (
            [
                {
                    "ITEM_SEQ": "1",
                    "ITEM_NAME": "테스트정서방형",
                    "ITEM_IMAGE": "https://nedrug.mfds.go.kr/wrong.png",
                },
                {
                    "ITEM_SEQ": "2",
                    "ITEM_NAME": "테스트정",
                    "ITEM_IMAGE": "https://nedrug.mfds.go.kr/right.png",
                },
            ],
            2,
        )

    monkeypatch.setattr(portal._transport, "request_items", fake_request_items)

    assert (
        await portal.searchMedicationImage("테스트정")
        == "https://nedrug.mfds.go.kr/right.png"
    )
    assert (
        await portal.searchMedicationImage("테스트정")
        == "https://nedrug.mfds.go.kr/right.png"
    )
    assert request_count == 1


# Function Name: test_pill_image_lookup_is_optional_when_api_is_unavailable
# Description:
# - Treats image API failure as an empty optional image and suppresses repeated failing lookups.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_pill_image_lookup_is_optional_when_api_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)
    request_count = 0

    # Function Name: failing_request_items
    # Description:
    # - Counts the image lookup and raises an authorization failure to exercise
    #   optional-image fallback.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # Returns:
    # - No normal result; raises the configured failure described above.
    async def failing_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        nonlocal request_count
        request_count += 1
        raise RuntimeError("not authorized")

    monkeypatch.setattr(portal._transport, "request_items", failing_request_items)

    assert await portal.searchMedicationImage("테스트정") == ""
    assert await portal.searchMedicationImage("테스트정") == ""
    assert request_count == 1


# Function Name: test_pill_image_lookup_rejects_ambiguous_name_matches
# Description:
# - Requires multiple exact-name images without a unique product match to yield no image.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_pill_image_lookup_rejects_ambiguous_name_matches(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)

    # Function Name: fake_request_items
    # Description:
    # - Returns two different images for the same product name to simulate an ambiguous
    #   catalog response.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # Returns:
    # - tuple[list[dict[str, object]], int]: Configured drug rows and the advertised total
    #   count.
    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        return (
            [
                {
                    "ITEM_NAME": "동일정",
                    "ITEM_IMAGE": "https://nedrug.mfds.go.kr/first.png",
                },
                {
                    "ITEM_NAME": "동일정",
                    "ITEM_IMAGE": "https://nedrug.mfds.go.kr/second.png",
                },
            ],
            2,
        )

    monkeypatch.setattr(portal._transport, "request_items", fake_request_items)

    assert await portal.searchMedicationImage("동일정") == ""


# Function Name: test_pill_image_lookup_uses_product_code_when_available
# Description:
# - Requires a supplied product code to drive a one-row lookup and return that product's image.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
@pytest.mark.anyio
async def test_pill_image_lookup_uses_product_code_when_available(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)

    # Function Name: fake_request_items
    # Description:
    # - Checks the product-code filter and one-row limit before returning the corresponding
    #   catalog image.
    # Parameters:
    # - url (str): Public API endpoint requested by the boundary.
    # - params (dict[str, object]): Public API query parameters checked by the transport
    #   double.
    # Returns:
    # - tuple[list[dict[str, object]], int]: Configured drug rows and the advertised total
    #   count.
    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        assert params["item_seq"] == "200000001"
        assert params["numOfRows"] == 1
        return (
            [
                {
                    "ITEM_SEQ": "200000001",
                    "ITEM_NAME": "테스트정",
                    "ITEM_IMAGE": "https://nedrug.mfds.go.kr/by-code.png",
                }
            ],
            1,
        )

    monkeypatch.setattr(portal._transport, "request_items", fake_request_items)

    assert (
        await portal.searchMedicationImage("테스트정", "200000001")
        == "https://nedrug.mfds.go.kr/by-code.png"
    )


# Function Name: test_public_data_response_header_rejects_service_errors
# Description:
# - Requires an unsuccessful public-data response header to raise an explicit service-rejection
#   error.
# Parameters:
# - None.
# Returns:
# - None.
def test_public_data_response_header_rejects_service_errors() -> None:
    transport = _PublicDrugTransport()

    with pytest.raises(RuntimeError, match="rejected"):
        transport._validate_response_header(
            {"response": {"header": {"resultCode": "30"}}}
        )


# Function Name: test_image_enrichment_uses_canonical_product_code
# Description:
# - Requires image enrichment to pass the canonical product name and code and retain both the
#   code and resolved image.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_image_enrichment_uses_canonical_product_code() -> None:
    requested_values: list[tuple[str, str]] = []

    # Class Name: _FakePillImagePortal
    # Role: Image portal double that records canonical name/code pairs and supplies a fixed
    #   MFDS image.
    # Responsibilities:
    # - Records the requested product identity and returns the canonical-code image URL.
    class _FakePillImagePortal:
        # Function Name: searchMedicationImage
        # Description:
        # - Records the requested product identity and returns the canonical-code image
        #   URL.
        # Parameters:
        # - item_name (str): Product name in the authoritative or saved medication
        #   record.
        # - item_seq (str): Authoritative product code identifying the medication.
        # Returns:
        # - str: Fixed HTTPS image URL for the canonical product code.
        async def searchMedicationImage(
            self,
            item_name: str,
            item_seq: str = "",
        ) -> str:
            requested_values.append((item_name, item_seq))
            return "https://nedrug.mfds.go.kr/by-code.png"

    control = object.__new__(CheckMedicationDetail)
    control.pill_image_api = _FakePillImagePortal()
    details = await control._enrich_missing_image_urls(
        [
            MedicationDetail(
                item_seq="200000001",
                item_name="test-tablet",
                efficacy="effect",
                usage_method="usage",
                warning="warning",
            )
        ]
    )

    assert requested_values == [("test-tablet", "200000001")]
    assert details[0].item_seq == "200000001"
    assert details[0].image_url == "https://nedrug.mfds.go.kr/by-code.png"


# 함수이름: test_public_basic_detail_preserves_product_code
# 함수역할:
# - 공공 기본 상세 변환이 품목 코드, 상호작용, 부작용 및 보관법을 보존하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_public_basic_detail_preserves_product_code() -> None:
    control = object.__new__(CheckMedicationDetail)

    details = await control._build_basic_drug_infos(
        [
            {
                "itemSeq": "200000001",
                "itemName": "test-tablet",
                "efcyQesitm": "effect",
                "useMethodQesitm": "usage",
                "atpnWarnQesitm": "warning",
                "intrcQesitm": "interaction",
                "seQesitm": "side effect",
                "depositMethodQesitm": "storage method",
            }
        ]
    )

    assert details[0].item_seq == "200000001"
    assert details[0].interaction == "interaction"
    assert details[0].side_effect == "side effect"
    assert details[0].storage_method == "storage method"


# Function Name: test_advanced_detail_preserves_product_code
# Description:
# - Requires advanced AI-enriched medication details to retain the original product code.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_advanced_detail_preserves_product_code() -> None:
    # Class Name: _FakeModels
    # Role: Gemini models double that supplies deterministic medication-summary JSON.
    # Responsibilities:
    # - Returns fixed efficacy, usage, and warning JSON without invoking Gemini.
    class _FakeModels:
        # Function Name: generate_content
        # Description:
        # - Returns fixed efficacy, usage, and warning JSON without invoking Gemini.
        # Parameters:
        # - **kwargs (object): Keyword arguments accepted by the substituted service
        #   interface.
        # Returns:
        # - object: Gemini-compatible response carrying the configured analysis JSON.
        async def generate_content(self, **kwargs: object) -> object:
            return type(
                "Response",
                (),
                {
                    "text": (
                        '{"efficacy":"effect","use_method":"usage",'
                        '"warning_message":"warning"}'
                    )
                },
            )()

    fake_client = type(
        "Client",
        (),
        {"aio": type("Aio", (), {"models": _FakeModels()})()},
    )()
    generator = _MedicationSummaryGenerator(ai_client=fake_client)

    detail = await generator.summarize_advanced_item(
        "test-tablet",
        {
            "ITEM_SEQ": "200000001",
            "ITEM_NAME": "test-tablet",
            "EE_DOC_DATA": "effect document",
            "UD_DOC_DATA": "usage document",
            "NB_DOC_DATA": "warning document",
        },
    )

    assert detail.item_seq == "200000001"


# Function Name: test_medication_summary_timeout_uses_configured_default
# Description:
# - Requires the summary generator to inherit the configured quarter-second default timeout.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# Returns:
# - None.
def test_medication_summary_timeout_uses_configured_default(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(settings, "MEDICATION_SUMMARY_TIMEOUT_SECONDS", 0.25)

    generator = _MedicationSummaryGenerator(ai_client=object())

    assert generator.timeout_seconds == 0.25


# Function Name: test_medication_summary_rejects_unbounded_timeout
# Description:
# - Rejects non-finite or non-positive summary timeouts with a validation error.
# Parameters:
# - timeout_seconds (float): Candidate deadline in seconds, including invalid boundary values.
# Returns:
# - None.
@pytest.mark.parametrize(
    "timeout_seconds",
    [0.0, -1.0, float("nan"), float("inf")],
)
def test_medication_summary_rejects_unbounded_timeout(
    timeout_seconds: float,
) -> None:
    with pytest.raises(ValueError, match="finite and positive"):
        _MedicationSummaryGenerator(
            ai_client=object(),
            timeout_seconds=timeout_seconds,
        )


# Function Name: test_medication_summary_timeout_is_stable_and_cancels_request
# Description:
# - Requires a stalled summary request to be cancelled and wrapped in the stable timeout error
#   with TimeoutError as its cause.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_summary_timeout_is_stable_and_cancels_request() -> None:
    # Class Name: _BlockingModels
    # Role: Blocking Gemini models double that records cancellation of an unfinished summary
    #   request.
    # Responsibilities:
    # - Waits indefinitely until cancelled, records cancellation, and propagates
    #   CancelledError.
    # Attributes:
    # - cancelled (bool): Whether cancellation reached the blocked request.
    class _BlockingModels:
        # Function Name: __init__
        # Description:
        # - Marks the blocking request as not yet cancelled.
        # Parameters:
        # - None.
        # Returns:
        # - None.
        def __init__(self) -> None:
            self.cancelled = False

        # Function Name: generate_content
        # Description:
        # - Waits indefinitely until cancelled, records cancellation, and propagates
        #   CancelledError.
        # Parameters:
        # - **kwargs (object): Keyword arguments accepted by the substituted service
        #   interface.
        # Returns:
        # - No normal result; propagates cancellation of the indefinitely blocked
        #   request.
        async def generate_content(self, **kwargs: object) -> object:
            try:
                await asyncio.Event().wait()
            except asyncio.CancelledError:
                self.cancelled = True
                raise

    models = _BlockingModels()
    fake_client = type(
        "Client",
        (),
        {"aio": type("Aio", (), {"models": models})()},
    )()
    generator = _MedicationSummaryGenerator(
        ai_client=fake_client,
        timeout_seconds=0.01,
    )

    with pytest.raises(RuntimeError) as exc_info:
        await generator.summarize_advanced_item(
            "test-tablet",
            {
                "ITEM_NAME": "test-tablet",
                "EE_DOC_DATA": "effect document",
                "UD_DOC_DATA": "usage document",
                "NB_DOC_DATA": "warning document",
            },
        )

    assert str(exc_info.value) == "Medication summary generation timed out."
    assert isinstance(exc_info.value.__cause__, TimeoutError)
    assert models.cancelled is True


# 함수이름: test_medication_cache_disables_after_lookup_failure
# 함수역할:
# - 첫 Redis 조회 실패 뒤 캐시가 비활성화되어 반복 조회는 서버에 재접근하지 않고 None을 반환하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
@pytest.mark.anyio
async def test_medication_cache_disables_after_lookup_failure() -> None:
    redis_client = _FailingRedisClient()
    cache = _MedicationDetailCache(redis_client=redis_client)

    assert await cache.get("엘타인캡슐") is None
    assert await cache.get("엘타인캡슐") is None
    assert redis_client.get_calls == 1


# Function Name: test_medication_cache_closes_its_redis_client
# Description:
# - Requires medication cache cleanup to close its owned Redis client.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_cache_closes_its_redis_client() -> None:
    redis_client = _FailingRedisClient()
    cache = _MedicationDetailCache(redis_client=redis_client)

    await cache.close()

    assert redis_client.closed is True


# Function Name: test_process_cache_cleanup_resets_state_after_close_failure
# Description:
# - Requires process cache cleanup to clear shared state and log the connection-error type even
#   when closure fails.
# Parameters:
# - monkeypatch (pytest.MonkeyPatch): Pytest replacement fixture restoring patched collaborators
#   afterward.
# - caplog (pytest.LogCaptureFixture): Pytest log capture used to check sensitive-data exposure.
# Returns:
# - None.
@pytest.mark.anyio
async def test_process_cache_cleanup_resets_state_after_close_failure(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
) -> None:
    monkeypatch.setattr(
        api_dependencies,
        "_medication_detail_cache",
        _CloseFailingMedicationCache(),
    )

    with caplog.at_level("WARNING"):
        await api_dependencies.close_medication_detail_cache()

    assert api_dependencies._medication_detail_cache is None
    assert "ConnectionError" in caplog.text
