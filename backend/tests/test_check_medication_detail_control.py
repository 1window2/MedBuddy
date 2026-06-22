import sys
from pathlib import Path

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.check_medication_detail_control import (
    _MedicationDetailCache,
    _MedicationTextNormalizer,
    _read_text,
)

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

    async def get(self, key: str) -> str:
        self.get_calls += 1
        raise ConnectionError("redis unavailable")

    async def setex(self, key: str, ttl: int, value: str) -> None:
        raise ConnectionError("redis unavailable")


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


@pytest.mark.anyio
async def test_medication_cache_disables_after_lookup_failure() -> None:
    redis_client = _FailingRedisClient()
    cache = _MedicationDetailCache(redis_client=redis_client)

    assert await cache.get("엘타인캡슐") is None
    assert await cache.get("엘타인캡슐") is None
    assert redis_client.get_calls == 1
