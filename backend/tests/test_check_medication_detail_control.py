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
    _MedicationSummaryGenerator,
    _MedicationTextNormalizer,
    _read_text,
)
from entities.medication_detail_entity import MedicationDetail

# 파일명: test_check_medication_detail_control.py
# 역할: 약품 상세 조회 control의 검색어 정규화와 캐시 실패 처리를 검증한다.

# 클래스명: _FailingRedisClient
# 역할: Redis 장애 상황을 재현하기 위한 테스트용 fake client이다.
# 주요 책임:
#   - get 호출 횟수를 기록한다.
#   - get/setex 호출 시 항상 연결 오류를 발생시킨다.
class _FailingRedisClient:
    def __init__(self) -> None:
        self.get_calls = 0
        self.closed = False

    async def get(self, key: str) -> str:
        self.get_calls += 1
        raise ConnectionError("redis unavailable")

    async def setex(self, key: str, ttl: int, value: str) -> None:
        raise ConnectionError("redis unavailable")

    async def aclose(self) -> None:
        self.closed = True


class _CloseFailingMedicationCache:
    async def close(self) -> None:
        raise ConnectionError("redis close failed")


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"


def test_build_search_keywords_splits_product_and_ingredient_names() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("켈로인(펠루비프로펜)")

    assert search_keywords == [
        "켈로인",
        "켈로인(펠루비프로펜)",
        "펠루비프로펜",
    ]


def test_split_parenthesized_text_uses_linear_scan() -> None:
    normalizer = _MedicationTextNormalizer()

    outside_text, parenthesized_candidates = normalizer._split_parenthesized_text(
        "Alpha(Beta) Gamma"
    )

    assert outside_text == "Alpha Gamma"
    assert parenthesized_candidates == ["Beta"]


def test_split_parenthesized_text_ignores_oversized_parentheses() -> None:
    normalizer = _MedicationTextNormalizer()

    outside_text, parenthesized_candidates = normalizer._split_parenthesized_text(
        "Alpha(" + ("B" * 10000) + ") Gamma"
    )

    assert outside_text == "Alpha Gamma"
    assert parenthesized_candidates == []


def test_build_search_keywords_strips_korean_dosage_unit() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("에니코프캡슐300밀리그램")

    assert search_keywords[:3] == [
        "에니코프캡슐",
        "에니코프",
        "에니코프캡슐300밀리그램",
    ]


def test_build_search_keywords_adds_hangul_ocr_vowel_variants() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords("에니코프캡슐300밀리그램")

    assert "애니코프" in search_keywords


def test_build_search_keywords_removes_known_manufacturer_prefix() -> None:
    normalizer = _MedicationTextNormalizer()

    search_keywords = normalizer.build_search_keywords(
        "대웅바이오클래리트로마이신정250mg"
    )

    assert "대웅바이오클래리트로마이신" in search_keywords
    assert "클래리트로마이신" in search_keywords


def test_read_text_replaces_missing_public_api_fields() -> None:
    assert _read_text(None) == "정보 없음"
    assert _read_text("") == "정보 없음"
    assert _read_text(None, "") == ""


def test_public_medication_image_url_accepts_documented_aliases() -> None:
    assert (
        read_public_image_url({"itemImage": "https://example.com/pill.png"})
        == "https://example.com/pill.png"
    )
    assert (
        read_public_image_url({"ITEM_IMAGE": "//example.com/pill.png"})
        == "https://example.com/pill.png"
    )


def test_public_medication_image_url_rejects_non_network_schemes() -> None:
    assert read_public_image_url({"itemImage": "data:image/png;base64,abc"}) == ""
    assert read_public_image_url({"imageUrl": "javascript:alert(1)"}) == ""
    assert read_public_image_url({"imageUrl": "https://[invalid"}) == ""


@pytest.mark.anyio
async def test_pill_image_lookup_requires_an_exact_medication_match(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)
    request_count = 0

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
                    "ITEM_IMAGE": "https://example.com/wrong.png",
                },
                {
                    "ITEM_SEQ": "2",
                    "ITEM_NAME": "테스트정",
                    "ITEM_IMAGE": "https://example.com/right.png",
                },
            ],
            2,
        )

    monkeypatch.setattr(portal._transport, "request_items", fake_request_items)

    assert (
        await portal.searchMedicationImage("테스트정")
        == "https://example.com/right.png"
    )
    assert (
        await portal.searchMedicationImage("테스트정")
        == "https://example.com/right.png"
    )
    assert request_count == 1


@pytest.mark.anyio
async def test_pill_image_lookup_is_optional_when_api_is_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)
    request_count = 0

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


@pytest.mark.anyio
async def test_pill_image_lookup_rejects_ambiguous_name_matches(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)

    async def fake_request_items(
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, object]], int]:
        return (
            [
                {
                    "ITEM_NAME": "동일정",
                    "ITEM_IMAGE": "https://example.com/first.png",
                },
                {
                    "ITEM_NAME": "동일정",
                    "ITEM_IMAGE": "https://example.com/second.png",
                },
            ],
            2,
        )

    monkeypatch.setattr(portal._transport, "request_items", fake_request_items)

    assert await portal.searchMedicationImage("동일정") == ""


@pytest.mark.anyio
async def test_pill_image_lookup_uses_product_code_when_available(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    portal = PillImageAPI()
    monkeypatch.setattr(settings, "PILL_IMAGE_API_ENABLED", True)

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
                    "ITEM_IMAGE": "https://example.com/by-code.png",
                }
            ],
            1,
        )

    monkeypatch.setattr(portal._transport, "request_items", fake_request_items)

    assert (
        await portal.searchMedicationImage("테스트정", "200000001")
        == "https://example.com/by-code.png"
    )


def test_public_data_response_header_rejects_service_errors() -> None:
    transport = _PublicDrugTransport()

    with pytest.raises(RuntimeError, match="rejected"):
        transport._validate_response_header(
            {"response": {"header": {"resultCode": "30"}}}
        )


@pytest.mark.anyio
async def test_image_enrichment_uses_canonical_product_code() -> None:
    requested_values: list[tuple[str, str]] = []

    class _FakePillImagePortal:
        async def searchMedicationImage(
            self,
            item_name: str,
            item_seq: str = "",
        ) -> str:
            requested_values.append((item_name, item_seq))
            return "https://example.com/by-code.png"

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
    assert details[0].image_url == "https://example.com/by-code.png"


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
            }
        ]
    )

    assert details[0].item_seq == "200000001"


@pytest.mark.anyio
async def test_advanced_detail_preserves_product_code() -> None:
    class _FakeModels:
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


@pytest.mark.anyio
async def test_medication_cache_disables_after_lookup_failure() -> None:
    redis_client = _FailingRedisClient()
    cache = _MedicationDetailCache(redis_client=redis_client)

    assert await cache.get("엘타인캡슐") is None
    assert await cache.get("엘타인캡슐") is None
    assert redis_client.get_calls == 1


@pytest.mark.anyio
async def test_medication_cache_closes_its_redis_client() -> None:
    redis_client = _FailingRedisClient()
    cache = _MedicationDetailCache(redis_client=redis_client)

    await cache.close()

    assert redis_client.closed is True


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
