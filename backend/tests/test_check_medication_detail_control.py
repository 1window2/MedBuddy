# File Name: test_check_medication_detail_control.py
# Role: Regression coverage for medication-name matching, image lookup, summary timeouts and
#   failed summaries, and the Redis detail cache including its recovery after an outage.
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
from boundaries.medication_detail_cache_boundary import MedicationDetailCache
from boundaries.medication_summary_boundary import (
    FAILED_SUMMARY_TEXT,
    MedicationSummaryGenerator,
    read_medication_detail_text,
)
from controls.check_medication_detail_control import CheckMedicationDetail
from services.medication_name_matching import (
    MedicationNameMatcher,
    MedicationTextNormalizer,
)
from entities.medication_detail_entity import MedicationDetail
from support.fakes import FakeGeminiClient, FakeRedis


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
    normalizer = MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("켈로인(펠루비프로펜)")

    assert search_keywords == [
        "켈로인(펠루비프로펜)",
        "켈로인",
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
    normalizer = MedicationTextNormalizer()

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
    normalizer = MedicationTextNormalizer()

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
    normalizer = MedicationTextNormalizer()

    outside_text, parenthesized_candidates = normalizer._split_parenthesized_text(
        "Drug((ingredient)) 20mg"
    )

    assert outside_text == "Drug 20mg"
    assert parenthesized_candidates == ["(ingredient)"]


# 함수이름: test_build_search_keywords_strips_korean_dosage_unit
# 함수역할:
# - 함량을 포함한 원문을 먼저 조회하고 이후에만 검색어를 넓히는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_build_search_keywords_strips_korean_dosage_unit() -> None:
    normalizer = MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("에니코프캡슐300밀리그램")

    assert search_keywords[:3] == [
        "에니코프캡슐300밀리그램",
        "에니코프캡슐",
        "에니코프",
    ]


# 함수이름: test_build_search_keywords_adds_hangul_ocr_vowel_variants
# 함수역할:
# - 한글 OCR 모음 혼동을 보정한 애니코프 후보가 검색어에 포함되는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_build_search_keywords_adds_hangul_ocr_vowel_variants() -> None:
    normalizer = MedicationTextNormalizer()

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
    normalizer = MedicationTextNormalizer()

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
    normalizer = MedicationTextNormalizer()
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
    matcher = MedicationNameMatcher()

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
    matcher = MedicationNameMatcher()

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
    matcher = MedicationNameMatcher()

    assert not matcher.is_confident_match("아스피린정", "타이레놀정")


# 함수이름: test_name_matcher_ranks_best_candidate_first
# 함수역할:
# - 가장 유사한 약품을 첫 후보로 정렬하고 무관한 성분의 후보를 제외하는지 검증한다.
# 매개변수:
# - 없음.
# 반환값:
# - 없음 (None).
def test_name_matcher_ranks_best_candidate_first() -> None:
    matcher = MedicationNameMatcher()
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
    assert read_medication_detail_text(None) == "정보 없음"
    assert read_medication_detail_text("") == "정보 없음"
    assert read_medication_detail_text(None, "") == ""


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
    generator = MedicationSummaryGenerator(ai_client=fake_client)

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

    generator = MedicationSummaryGenerator(ai_client=object())

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
        MedicationSummaryGenerator(
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
    generator = MedicationSummaryGenerator(
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


# Function Name: _advanced_item
# Description:
# - Builds one advanced approval row with a product code, a name and the three source documents.
# Parameters:
# - **overrides (object): Row fields that replace or extend the defaults.
# Returns:
# - dict[str, object]: Raw approval item accepted by the summary generator.
def _advanced_item(**overrides: object) -> dict[str, object]:
    return {
        "ITEM_SEQ": "200000001",
        "ITEM_NAME": "가나다정",
        "ENTP_NAME": "테스트제약",
        "EE_DOC_DATA": "effect document",
        "UD_DOC_DATA": "usage document",
        "NB_DOC_DATA": "warning document",
        **overrides,
    }


# Function Name: test_medication_summary_rejects_answer_without_summary_fields
# Description:
# - Requires an AI answer with no usable summary (empty object, blank fields, a JSON list or a
#   bare string) to raise the stable summary error instead of returning placeholder guidance.
# Parameters:
# - answer (object): Scripted Gemini answer without any usable summary field.
# Returns:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize(
    "answer",
    [
        {},
        [],
        '"plain text"',
        {"efficacy": "  ", "use_method": "", "warning_message": None},
    ],
)
async def test_medication_summary_rejects_answer_without_summary_fields(
    answer: object,
) -> None:
    generator = MedicationSummaryGenerator(ai_client=FakeGeminiClient(answer))

    with pytest.raises(RuntimeError) as exc_info:
        await generator.summarize_advanced_item("가나다정", _advanced_item())

    assert str(exc_info.value) == "AI 요약 처리 중 오류가 발생했습니다."


# Function Name: test_medication_summary_marks_only_the_missing_fields
# Description:
# - Requires a partial AI answer to keep the returned summary and to show the neutral
#   "정보 없음" text, never the failure text, for the fields the answer left out.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_summary_marks_only_the_missing_fields() -> None:
    generator = MedicationSummaryGenerator(
        ai_client=FakeGeminiClient({"efficacy": "열을 내립니다.", "use_method": " "}),
    )

    detail = await generator.summarize_advanced_item("가나다정", _advanced_item())

    assert detail.efficacy == "열을 내립니다."
    assert detail.usage_method == "정보 없음"
    assert detail.warning == "정보 없음"
    assert FAILED_SUMMARY_TEXT not in (detail.efficacy, detail.usage_method, detail.warning)


# Function Name: test_medication_summary_names_the_product_from_the_public_item
# Description:
# - Requires the summarized detail to carry the public item's own name under any documented
#   alias, and the search keyword only when the item has no name.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_summary_names_the_product_from_the_public_item() -> None:
    generator = MedicationSummaryGenerator(
        ai_client=FakeGeminiClient(
            {"efficacy": "effect", "use_method": "usage", "warning_message": "warning"},
        ),
    )
    aliased_item = _advanced_item(itemName="가나다정500밀리그램")
    del aliased_item["ITEM_NAME"]
    unnamed_item = _advanced_item(ITEM_NAME="  ")

    aliased = await generator.summarize_advanced_item("가나다", aliased_item)
    unnamed = await generator.summarize_advanced_item("가나다", unnamed_item)

    assert aliased.item_name == "가나다정500밀리그램"
    assert unnamed.item_name == "가나다"


# Class Name: _ManualClock
# Role: Monotonic clock double that a test advances by hand to cross the cache cool-down.
# Attributes:
# - now (float): Current clock value in seconds.
class _ManualClock:
    # Function Name: __init__
    # Description:
    # - Starts the clock at an arbitrary positive value.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __init__(self) -> None:
        self.now = 1000.0

    # Function Name: __call__
    # Description:
    # - Reads the clock like time.monotonic.
    # Parameters:
    # - None.
    # Returns:
    # - float: Current clock value.
    def __call__(self) -> float:
        return self.now


# Function Name: _detail
# Description:
# - Builds one complete medication detail for cache round trips.
# Parameters:
# - **overrides (object): MedicationDetail fields that replace the defaults.
# Returns:
# - MedicationDetail: Detail with every required guidance field populated.
def _detail(**overrides: object) -> MedicationDetail:
    values: dict[str, object] = {
        "item_seq": "200000001",
        "item_name": "가나다정",
        "efficacy": "effect",
        "usage_method": "usage",
        "warning": "warning",
        "source": "Basic (e약은요)",
        **overrides,
    }
    return MedicationDetail(**values)


# Function Name: test_medication_cache_round_trip_through_redis
# Description:
# - Requires a saved detail list to come back from the real cache class with the seven-day
#   expiry, the drug_info key namespace and the cache marker on its source.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_cache_round_trip_through_redis() -> None:
    redis_client = FakeRedis()
    cache = MedicationDetailCache(redis_client=redis_client)

    await cache.set("가나다정", [_detail()])
    cached = await cache.get("가나다정")

    assert redis_client.ttl_seconds == {"drug_info:가나다정": 604800}
    assert cached is not None and len(cached) == 1
    assert cached[0].item_seq == "200000001"
    assert cached[0].usage_method == "usage"
    assert cached[0].source == "[Cache] Basic (e약은요)"
    assert await cache.get("없는약") is None


# Function Name: test_medication_cache_retries_redis_after_cooldown
# Description:
# - Requires a Redis failure to switch the cache off without raising, to keep Redis untouched
#   during the cool-down, and to use Redis again by itself once the cool-down has passed.
# - A second outage after the recovery starts a new cool-down.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_cache_retries_redis_after_cooldown() -> None:
    redis_client = FakeRedis(fail_with=ConnectionError("redis unavailable"))
    clock = _ManualClock()
    cache = MedicationDetailCache(redis_client=redis_client, clock=clock)

    assert await cache.get("엘타인캡슐") is None
    assert await cache.get("엘타인캡슐") is None
    await cache.set("엘타인캡슐", [_detail()])
    assert redis_client.calls["get"] == 1
    assert redis_client.calls["setex"] == 0

    # Redis is healthy again, but the cache must wait for the cool-down before it looks.
    redis_client.fail_with = None
    clock.now += MedicationDetailCache.RETRY_COOLDOWN_SECONDS - 1
    assert await cache.get("엘타인캡슐") is None
    assert redis_client.calls["get"] == 1

    clock.now += 1
    await cache.set("엘타인캡슐", [_detail()])
    cached = await cache.get("엘타인캡슐")
    assert cached is not None and cached[0].item_name == "가나다정"
    assert redis_client.calls["setex"] == 1

    redis_client.fail_with = TimeoutError("redis timed out")
    assert await cache.get("엘타인캡슐") is None
    assert await cache.get("엘타인캡슐") is None
    assert redis_client.calls["get"] == 3


# Function Name: test_medication_cache_save_failure_starts_cooldown_without_raising
# Description:
# - Requires a failed save to be swallowed and to pause both reads and writes for the cool-down,
#   after which a save succeeds again.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_cache_save_failure_starts_cooldown_without_raising() -> None:
    redis_client = FakeRedis()
    clock = _ManualClock()
    cache = MedicationDetailCache(redis_client=redis_client, clock=clock)

    redis_client.fail_with = OSError("connection reset")
    await cache.set("가나다정", [_detail()])
    redis_client.fail_with = None
    assert await cache.get("가나다정") is None
    assert redis_client.calls["setex"] == 1
    assert redis_client.calls["get"] == 0

    clock.now += MedicationDetailCache.RETRY_COOLDOWN_SECONDS
    await cache.set("가나다정", [_detail()])
    assert await cache.get("가나다정") is not None


# Function Name: test_medication_cache_treats_unreadable_entry_as_miss_for_that_key
# Description:
# - Requires an entry that is not JSON, is not a list or lacks required fields to be a miss for
#   its own key only: Redis stays in use and a well-formed key is still served.
# Parameters:
# - stored_value (str): Raw Redis value that cannot be turned into medication details.
# Returns:
# - None.
@pytest.mark.anyio
@pytest.mark.parametrize(
    "stored_value",
    [
        "not json",
        '{"item_name": "가나다정"}',
        '[{"item_name": "가나다정"}]',
    ],
)
async def test_medication_cache_treats_unreadable_entry_as_miss_for_that_key(
    stored_value: str,
) -> None:
    redis_client = FakeRedis()
    cache = MedicationDetailCache(redis_client=redis_client)
    await cache.set("good", [_detail()])
    redis_client.values["drug_info:bad"] = stored_value

    assert await cache.get("bad") is None
    assert await cache.get("good") is not None
    assert redis_client.calls["get"] == 2

    # The lookup that follows a miss overwrites the unreadable entry.
    await cache.set("bad", [_detail()])
    assert await cache.get("bad") is not None


# Function Name: test_medication_cache_ignores_stored_failed_summary
# Description:
# - Requires a snapshot saved before failed summaries were rejected to be a miss, so the
#   failure text is not served again from Redis until the entry expires.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_cache_ignores_stored_failed_summary() -> None:
    redis_client = FakeRedis()
    cache = MedicationDetailCache(redis_client=redis_client)
    await cache.set(
        "가나다정",
        [_detail(warning=FAILED_SUMMARY_TEXT, source="Advanced (허가정보) + AI 요약")],
    )

    assert redis_client.calls["setex"] == 1
    assert await cache.get("가나다정") is None


# Function Name: test_medication_cache_default_client_has_socket_timeouts
# Description:
# - Requires the Redis client the cache builds for itself to bound both the connect and the
#   response wait, so an unreachable Redis cannot hold a medication lookup.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_cache_default_client_has_socket_timeouts() -> None:
    cache = MedicationDetailCache()
    try:
        connection_options = cache.redis_client.connection_pool.connection_kwargs
        assert connection_options["socket_connect_timeout"] == 0.3
        assert connection_options["socket_timeout"] == 0.3
    finally:
        await cache.close()


# Class Name: _StubDrugSource
# Role: Stands in for the local catalogue, both public drug APIs and the image API in
#   control-level tests; returns fixed rows and no image.
# Attributes:
# - items (list[dict[str, object]]): Rows returned by every public search.
# - search_calls (list[str]): Keywords the control searched for, in order.
class _StubDrugSource:
    # Function Name: __init__
    # Description:
    # - Stores the rows to return and starts with an empty search ledger.
    # Parameters:
    # - items (list[dict[str, object]] | None): Rows returned by searchMedication.
    # Returns:
    # - None.
    def __init__(self, items: list[dict[str, object]] | None = None) -> None:
        self.items = items or []
        self.search_calls: list[str] = []

    # Function Name: fetch_drug_info
    # Description:
    # - Answers the local catalogue lookup with no local product.
    # Parameters:
    # - drug_name (str): Search keyword.
    # Returns:
    # - list[MedicationDetail]: Always empty.
    async def fetch_drug_info(self, drug_name: str) -> list[MedicationDetail]:
        return []

    # Function Name: searchMedication
    # Description:
    # - Records the keyword and returns copies of the configured public rows.
    # Parameters:
    # - drug_name (str): Search keyword.
    # Returns:
    # - list[dict[str, object]]: Configured rows.
    async def searchMedication(self, drug_name: str) -> list[dict[str, object]]:
        self.search_calls.append(drug_name)
        return [dict(item) for item in self.items]

    # Function Name: searchMedicationImage
    # Description:
    # - Answers the optional image lookup with no image.
    # Parameters:
    # - item_name (str): Product name.
    # - item_seq (str): Product code.
    # Returns:
    # - str: Always empty.
    async def searchMedicationImage(self, item_name: str, item_seq: str = "") -> str:
        return ""


# Function Name: _detail_control
# Description:
# - Wires the real control, cache class and summary generator to in-memory doubles.
# Parameters:
# - redis_client (FakeRedis): Redis double behind the real cache class.
# - gemini_client (FakeGeminiClient): Scripted AI client behind the real summary generator.
# - basic_items (list[dict[str, object]] | None): Rows of the basic public API.
# - advanced_items (list[dict[str, object]] | None): Rows of the advanced approval API.
# Returns:
# - CheckMedicationDetail: Control with no local catalogue hit and no image lookup result.
def _detail_control(
    redis_client: FakeRedis,
    gemini_client: FakeGeminiClient,
    *,
    basic_items: list[dict[str, object]] | None = None,
    advanced_items: list[dict[str, object]] | None = None,
) -> CheckMedicationDetail:
    return CheckMedicationDetail(
        db=None,
        medication_cache=MedicationDetailCache(redis_client=redis_client),
        public_drug_small_api=_StubDrugSource(basic_items),
        public_drug_large_api=_StubDrugSource(advanced_items),
        pill_image_api=_StubDrugSource(),
        summary_generator=MedicationSummaryGenerator(ai_client=gemini_client),
        local_medication_catalog=_StubDrugSource(),
    )


# Function Name: test_failed_summary_is_not_cached_and_the_next_request_retries
# Description:
# - Requires a lookup whose AI summary fails to end in the summary error with nothing written
#   to Redis, and the next identical lookup to ask the AI again and cache the real summary.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_failed_summary_is_not_cached_and_the_next_request_retries() -> None:
    redis_client = FakeRedis()
    gemini_client = FakeGeminiClient(
        {},
        {"efficacy": "effect", "use_method": "usage", "warning_message": "warning"},
    )
    control = _detail_control(
        redis_client, gemini_client, advanced_items=[_advanced_item()],
    )

    with pytest.raises(RuntimeError):
        await control.requestMedicationDetail("가나다정")

    assert redis_client.calls["setex"] == 0
    assert redis_client.values == {}

    response = await control.requestMedicationDetail("가나다정")

    assert gemini_client.call_count == 2
    assert response.success is True
    assert [item.efficacy for item in response.data] == ["effect"]
    assert redis_client.calls["setex"] == 1

    cached_response = await control.requestMedicationDetail("가나다정")

    assert gemini_client.call_count == 2
    assert cached_response.data[0].source.startswith("[Cache] ")


# Function Name: test_medication_lookup_succeeds_while_redis_is_down
# Description:
# - Requires a Redis outage on both the read and the write side to leave the lookup result
#   untouched, and later lookups to skip Redis instead of failing on it again.
# Parameters:
# - None.
# Returns:
# - None.
@pytest.mark.anyio
async def test_medication_lookup_succeeds_while_redis_is_down() -> None:
    redis_client = FakeRedis(fail_with=ConnectionError("redis unavailable"))
    control = _detail_control(
        redis_client,
        FakeGeminiClient(),
        basic_items=[
            {
                "itemSeq": "200000001",
                "itemName": "가나다정",
                "efcyQesitm": "effect",
                "useMethodQesitm": "usage",
                "atpnWarnQesitm": "warning",
            }
        ],
    )

    first = await control.requestMedicationDetail("가나다정")
    second = await control.requestMedicationDetail("가나다정")

    assert first.success is True and second.success is True
    assert second.data[0].item_name == "가나다정"
    assert redis_client.calls["get"] == 1
    assert redis_client.calls["setex"] == 0


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
    cache = MedicationDetailCache(redis_client=redis_client)

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
