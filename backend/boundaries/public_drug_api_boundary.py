# File Name: public_drug_api_boundary.py
# Role: Adapts Korean public medication catalogs and exact-match pill images through shared HTTP transport.
"""External boundaries for Korean public medication data services."""

import asyncio
import hashlib
import json
import logging
import time
from typing import Any
import httpx

from core.config import settings
from entities.medication_image_url_entity import safe_medication_image_url

logger = logging.getLogger(__name__)

_PUBLIC_IMAGE_URL_FIELDS = (
    "itemImage",
    "ITEM_IMAGE",
    "item_image",
    "imageUrl",
    "image_url",
)
_PUBLIC_ITEM_NAME_FIELDS = ("ITEM_NAME", "itemName", "item_name")
_PUBLIC_ITEM_SEQUENCE_FIELDS = (
    "ITEM_SEQ",
    "itemSeq",
    "item_seq",
    "PRDLST_STDR_CODE",
    "prdlst_Stdr_code",
)


# Function Name: _read_public_item_text
# Description:
# - Read the first nonblank alias, preferring exact keys and falling back to case-insensitive keys.
# Parameters:
# - item (dict[str, Any]): Public medication response row.
# - fields (tuple[str, ...]): Equivalent field names in lookup priority order.
# Returns:
# - Trimmed field text, or an empty string when no alias is populated.
def _read_public_item_text(
    item: dict[str, Any],
    fields: tuple[str, ...],
) -> str:
    lowered_items = {
        str(existing_key).lower(): existing_value
        for existing_key, existing_value in item.items()
    }
    for field in fields:
        value = item.get(field)
        if value is None:
            value = lowered_items.get(field.lower())
        if value is not None and str(value).strip():
            return str(value).strip()
    return ""


# Function Name: read_public_item_name
# Description:
# - Read a medication product name across the supported public API field aliases.
# Parameters:
# - item (dict[str, Any]): Public medication response row.
# Returns:
# - Trimmed product name, or an empty string when absent.
def read_public_item_name(item: dict[str, Any]) -> str:
    return _read_public_item_text(item, _PUBLIC_ITEM_NAME_FIELDS)


# Function Name: read_public_item_sequence
# Description:
# - Read the public product identifier across item-sequence and standard-code aliases.
# Parameters:
# - item (dict[str, Any]): Public medication response row.
# Returns:
# - Trimmed item identifier, or an empty string when absent.
def read_public_item_sequence(item: dict[str, Any]) -> str:
    return _read_public_item_text(item, _PUBLIC_ITEM_SEQUENCE_FIELDS)


# Function Name: read_public_image_url
# Description:
# - Read an image-field alias and pass it through the shared medication-image URL safety policy.
# Parameters:
# - item (dict[str, Any]): Public medication response row containing optional image fields.
# Returns:
# - Permitted image URL, or an empty string for absent or unsafe input.
def read_public_image_url(item: dict[str, Any]) -> str:
    return safe_medication_image_url(
        _read_public_item_text(item, _PUBLIC_IMAGE_URL_FIELDS)
    )


# Class Name: _PublicDrugTransport
# Role:
# - Shares bounded HTTP access and response normalization across public-drug boundaries.
# Responsibilities:
# - Pool connections, cap concurrent calls, cache failures without credentials and normalize provider response envelopes.
# Attributes:
# - _client (AsyncClient | None): Lazily created HTTP pool.
# - _semaphore (asyncio.Semaphore): Provider concurrency cap.
# - _failed_until (dict[str, float]): Failure-key cooldown expirations.
# - timeout_seconds (float): HTTP request timeout.
class _PublicDrugTransport:
    """Shared HTTP and response-normalization implementation."""

    # 함수이름: __init__
    # 함수역할:
    # - 공공 약품 요청에 사용할 제한 시간, 지연 생성 클라이언트 잠금, 동시 호출 상한과 실패 캐시를 준비한다.
    # 매개변수:
    # - timeout_seconds (float): HTTP 요청 제한 시간(초); 기본값은 15초.
    # 반환값:
    # - 없음; 외부 요청은 실행하지 않는다.
    def __init__(self, timeout_seconds: float = 15.0) -> None:
        self.timeout_seconds = timeout_seconds
        self._client: httpx.AsyncClient | None = None
        self._client_lock = asyncio.Lock()
        self._semaphore = asyncio.Semaphore(settings.PUBLIC_API_MAX_CONCURRENCY)
        self._failed_until: dict[str, float] = {}

    # Function Name: request_items
    # Description:
    # - Apply failure cooldown and concurrency limits, validate HTTP/JSON/provider status and normalize returned medication items.
    # Parameters:
    # - url (str): Configured public medication endpoint.
    # - params (dict[str, object]): Provider query parameters, including the service key.
    # - bypass_failure_cache (bool): Whether to retry even while a previous identical request is in cooldown.
    # Returns:
    # - Normalized item dictionaries and total count; transport and invalid-response failures propagate.
    async def request_items(
        self,
        url: str,
        params: dict[str, object],
        *,
        bypass_failure_cache: bool = False,
    ) -> tuple[list[dict[str, Any]], int]:
        failure_key = self._build_failure_key(url, params)
        if (
            not bypass_failure_cache
            and self._failed_until.get(failure_key, 0.0) > time.monotonic()
        ):
            raise RuntimeError(
                "The public medication API is temporarily unavailable."
            )

        try:
            async with self._semaphore:
                client = await self._get_client()
                response = await client.get(url, params=params)
        except Exception:
            self._remember_failure(failure_key)
            raise

        if response.status_code != 200:
            self._remember_failure(failure_key)
            raise RuntimeError("The public medication API did not respond successfully.")

        try:
            data = response.json()
        except ValueError:
            self._remember_failure(failure_key)
            raise RuntimeError(
                "The public medication API returned an invalid payload."
            ) from None
        if not isinstance(data, dict):
            self._remember_failure(failure_key)
            raise RuntimeError("The public medication API returned an invalid payload.")
        try:
            self._validate_response_header(data)
        except RuntimeError:
            self._remember_failure(failure_key)
            raise
        self._failed_until.pop(failure_key, None)
        body = self._extract_body(data)
        return self._normalize_items(body.get("items")), self._safe_int(
            body.get("totalCount")
        )

    # 함수이름: close
    # 함수역할:
    # - 잠금으로 현재 HTTP 클라이언트를 분리한 뒤 연결 풀을 닫는다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음; 다음 요청에서는 새 클라이언트를 생성할 수 있다.
    async def close(self) -> None:
        async with self._client_lock:
            client = self._client
            self._client = None
        if client is not None:
            await client.aclose()

    # 함수이름: _get_client
    # 함수역할:
    # - 클라이언트를 재사용하거나 잠금으로 한 번만 생성하여 공공 API 연결 풀을 공유한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 제한 시간과 연결 수 상한이 적용된 AsyncClient.
    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is not None:
            return self._client
        async with self._client_lock:
            if self._client is None:
                self._client = httpx.AsyncClient(
                    timeout=self.timeout_seconds,
                    limits=httpx.Limits(
                        max_connections=settings.PUBLIC_API_MAX_CONCURRENCY,
                        max_keepalive_connections=settings.PUBLIC_API_MAX_CONCURRENCY,
                    ),
                )
        return self._client

    # 함수이름: _build_failure_key
    # 함수역할:
    # - 인증키를 제외한 정렬된 요청 URL·매개변수를 SHA-256으로 해시하여 실패 캐시 키를 만든다.
    # 매개변수:
    # - url (str): 실패를 구분할 공공 API 주소.
    # - params (dict[str, object]): 요청 매개변수; serviceKey는 대소문자와 관계없이 해시에서 제외한다.
    # 반환값:
    # - serviceKey를 포함하지 않는 요청 식별 해시.
    @staticmethod
    def _build_failure_key(url: str, params: dict[str, object]) -> str:
        safe_params = {
            key: value
            for key, value in params.items()
            if key.lower() != "servicekey"
        }
        payload = json.dumps(
            [url, safe_params],
            ensure_ascii=True,
            sort_keys=True,
            default=str,
        )
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    # 함수이름: _remember_failure
    # 함수역할:
    # - 실패 요청의 재시도 가능 시각을 기록하고 캐시가 커지면 이미 만료된 키를 제거한다.
    # 매개변수:
    # - failure_key (str): 인증키를 제외하고 계산한 요청 식별 해시.
    # 반환값:
    # - 없음; 실패 재시도 제한 상태를 갱신한다.
    def _remember_failure(self, failure_key: str) -> None:
        if len(self._failed_until) >= 1_024:
            now = time.monotonic()
            self._failed_until = {
                key: expires_at
                for key, expires_at in self._failed_until.items()
                if expires_at > now
            }
        self._failed_until[failure_key] = (
            time.monotonic() + settings.PUBLIC_API_FAILURE_CACHE_SECONDS
        )

    # Function Name: _extract_body
    # Description:
    # - Accept either a top-level body object or a nested response.body envelope.
    # Parameters:
    # - data (dict[str, Any]): Decoded public API JSON object.
    # Returns:
    # - Provider body dictionary, or an empty dictionary for an unsupported envelope.
    @staticmethod
    def _extract_body(data: dict[str, Any]) -> dict[str, Any]:
        body = data.get("body")
        if isinstance(body, dict):
            return body

        response = data.get("response")
        if isinstance(response, dict) and isinstance(response.get("body"), dict):
            return response["body"]
        return {}

    # Function Name: _validate_response_header
    # Description:
    # - Check top-level or nested result headers, allowing absent status and the two recognized success codes.
    # Parameters:
    # - data (dict[str, Any]): Decoded public API JSON object with optional header envelope.
    # Returns:
    # - None for accepted headers; raises RuntimeError for a nonempty failure code.
    @staticmethod
    def _validate_response_header(data: dict[str, Any]) -> None:
        header = data.get("header")
        response = data.get("response")
        if not isinstance(header, dict) and isinstance(response, dict):
            header = response.get("header")
        if not isinstance(header, dict):
            return

        result_code = str(
            header.get("resultCode", header.get("result_code", ""))
        ).strip()
        if result_code and result_code not in {"00", "0000"}:
            raise RuntimeError("The public medication API rejected the request.")

    # Function Name: _normalize_items
    # Description:
    # - Flatten item/items wrapper variants and discard non-object list entries.
    # Parameters:
    # - raw_items (Any): Unvalidated provider items value, possibly nested.
    # Returns:
    # - List of item dictionaries, or an empty list for absent or unsupported input.
    @classmethod
    def _normalize_items(cls, raw_items: Any) -> list[dict[str, Any]]:
        if raw_items is None:
            return []
        if isinstance(raw_items, list):
            return [item for item in raw_items if isinstance(item, dict)]
        if isinstance(raw_items, dict):
            nested_item = raw_items.get("item")
            if nested_item is not None:
                return cls._normalize_items(nested_item)
            nested_items = raw_items.get("items")
            if nested_items is not None:
                return cls._normalize_items(nested_items)
            return [raw_items]
        return []

    # Function Name: _safe_int
    # Description:
    # - Convert the total-count value to an integer without failing on missing or malformed data.
    # Parameters:
    # - value (Any): Raw totalCount field.
    # Returns:
    # - Parsed integer, or 0 for TypeError or ValueError.
    @staticmethod
    def _safe_int(value: Any) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0


# Class Name: PublicDrugSmallAPI
# Role:
# - Queries the patient-facing eDrug medication catalog.
# Responsibilities:
# - Provide a small name-search fallback and uncached-failure paging for catalog synchronization.
# Attributes:
# - _transport (_PublicDrugTransport): Shared or internally constructed HTTP adapter.
class PublicDrugSmallAPI:
    """UML external boundary for the patient-facing eDrug catalog."""

    # Function Name: __init__
    # Description:
    # - Use the injected public-data transport or create one with the requested timeout.
    # Parameters:
    # - timeout_seconds (float): HTTP timeout in seconds when constructing a transport.
    # - transport (_PublicDrugTransport | None): Optional shared public-drug transport.
    # Returns:
    # - None; the eDrug transport is retained.
    def __init__(
        self,
        timeout_seconds: float = 15.0,
        transport: _PublicDrugTransport | None = None,
    ) -> None:
        self._transport = transport or _PublicDrugTransport(timeout_seconds)

    # Function Name: searchMedication
    # Description:
    # - Search up to three consumer medication rows by name and treat provider failures as an empty optional result.
    # Parameters:
    # - medication_name (str): Product name sent as the eDrug itemName query.
    # Returns:
    # - Matching item dictionaries, or an empty list on lookup failure.
    async def searchMedication(self, medication_name: str) -> list[dict[str, Any]]:
        params = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "itemName": medication_name,
            "type": "json",
            "numOfRows": 3,
        }
        try:
            items, _ = await self._transport.request_items(
                settings.BASIC_DRUG_API_BASE_URL,
                params,
            )
            return items
        except Exception as exc:
            logger.warning(
                "Basic public drug API lookup failed: %s",
                type(exc).__name__,
            )
            return []

    # Function Name: fetchPage
    # Description:
    # - Fetch a consumer-catalog page while bypassing negative-cache suppression for synchronization.
    # Parameters:
    # - page_no (int): One-based upstream result page number.
    # - num_of_rows (int): Requested number of rows in the page.
    # Returns:
    # - Item dictionaries and provider total count; retrieval failures propagate.
    async def fetchPage(
        self,
        page_no: int,
        num_of_rows: int,
    ) -> tuple[list[dict[str, Any]], int]:
        return await self._transport.request_items(
            settings.BASIC_DRUG_API_BASE_URL,
            {
                "serviceKey": settings.PUBLIC_DATA_API_KEY,
                "pageNo": page_no,
                "numOfRows": num_of_rows,
                "type": "json",
            },
            bypass_failure_cache=True,
        )


# Class Name: PublicDrugLargeAPI
# Role:
# - Queries the complete medication approval-detail catalog.
# Responsibilities:
# - Provide approval-name search and page-wise synchronization through the shared transport.
# Attributes:
# - _transport (_PublicDrugTransport): Approval-catalog HTTP adapter.
class PublicDrugLargeAPI:
    """UML external boundary for the complete approval catalog."""

    # Function Name: __init__
    # Description:
    # - Bind a shared transport or construct an approval-catalog transport with the requested timeout.
    # Parameters:
    # - timeout_seconds (float): HTTP timeout in seconds when a transport is not injected.
    # - transport (_PublicDrugTransport | None): Optional shared public-drug HTTP adapter.
    # Returns:
    # - None.
    def __init__(
        self,
        timeout_seconds: float = 15.0,
        transport: _PublicDrugTransport | None = None,
    ) -> None:
        self._transport = transport or _PublicDrugTransport(timeout_seconds)

    # 함수이름: searchMedication
    # 함수역할:
    # - 약품명으로 허가 상세 정보를 최대 5건 요청하고 외부 오류는 호출자에게 전달한다.
    # 매개변수:
    # - medication_name (str): 허가 상세 API의 item_name으로 전달할 약품명.
    # 반환값:
    # - 허가 상세 항목 사전 목록.
    async def searchMedication(self, medication_name: str) -> list[dict[str, Any]]:
        items, _ = await self._transport.request_items(
            settings.ADVANCED_DRUG_API_BASE_URL,
            {
                "serviceKey": settings.PUBLIC_DATA_API_KEY,
                "item_name": medication_name,
                "type": "json",
                "numOfRows": 5,
            },
        )
        return items

    # Function Name: fetchPage
    # Description:
    # - Fetch an approval-catalog page with failure-cache bypass for synchronization workloads.
    # Parameters:
    # - page_no (int): One-based upstream result page number.
    # - num_of_rows (int): Requested number of rows in the page.
    # Returns:
    # - Approval item dictionaries and provider total count.
    async def fetchPage(
        self,
        page_no: int,
        num_of_rows: int,
    ) -> tuple[list[dict[str, Any]], int]:
        return await self._transport.request_items(
            settings.ADVANCED_DRUG_API_BASE_URL,
            {
                "serviceKey": settings.PUBLIC_DATA_API_KEY,
                "pageNo": page_no,
                "numOfRows": num_of_rows,
                "type": "json",
            },
            bypass_failure_cache=True,
        )


# Class Name: PillImageAPI
# Role:
# - Provides exact-match MFDS pill-image enrichment.
# Responsibilities:
# - Prefer exact product IDs, require one unambiguous safe image URL and bound optional lookups with cache and outage cooldown.
# Attributes:
# - _image_url_cache (dict[str, str]): Product-key image results, including misses, capped at 512 entries.
# - _retry_after (float): Monotonic expiry of the 60-second provider-failure cooldown.
# - _transport (_PublicDrugTransport): Public-data HTTP adapter.
class PillImageAPI:
    """v0.0.9 extension for exact-match MFDS pill image lookup."""

    _CACHE_LIMIT = 512
    _FAILURE_COOLDOWN_SECONDS = 60.0

    # Function Name: __init__
    # Description:
    # - Initialize pill-image transport, an empty result cache and a cleared provider cooldown.
    # Parameters:
    # - timeout_seconds (float): HTTP timeout used only when constructing a transport.
    # - transport (_PublicDrugTransport | None): Optional shared public-drug HTTP adapter.
    # Returns:
    # - None; no image request is made.
    def __init__(
        self,
        timeout_seconds: float = 15.0,
        transport: _PublicDrugTransport | None = None,
    ) -> None:
        self._transport = transport or _PublicDrugTransport(timeout_seconds)
        self._image_url_cache: dict[str, str] = {}
        self._retry_after = 0.0

    # Function Name: searchMedicationImage
    # Description:
    # - Look up an exact product ID or normalized name within a timeout; accept only a single distinct safe matching image URL.
    # Parameters:
    # - item_name (str): Product name used only when no item sequence is provided.
    # - item_seq (str): Preferred exact public product identifier; optional.
    # Returns:
    # - Cached or fetched image URL; empty for disabled lookup, cooldown, failure, no match or ambiguity.
    async def searchMedicationImage(
        self,
        item_name: str,
        item_seq: str = "",
    ) -> str:
        if not settings.PILL_IMAGE_API_ENABLED:
            return ""
        if time.monotonic() < self._retry_after:
            return ""

        normalized_name = self._normalize_match_text(item_name)
        normalized_sequence = item_seq.strip()
        if not normalized_name and not normalized_sequence:
            return ""

        cache_key = (
            f"seq:{normalized_sequence}"
            if normalized_sequence
            else f"name:{normalized_name}"
        )
        if cache_key in self._image_url_cache:
            return self._image_url_cache[cache_key]

        params: dict[str, object] = {
            "serviceKey": settings.PUBLIC_DATA_API_KEY,
            "type": "json",
            "numOfRows": 1 if normalized_sequence else 10,
        }
        if normalized_sequence:
            params["item_seq"] = normalized_sequence
        else:
            params["item_name"] = item_name.strip()

        try:
            items, _ = await asyncio.wait_for(
                self._transport.request_items(
                    settings.PILL_IMAGE_API_BASE_URL,
                    params,
                ),
                timeout=settings.PILL_IMAGE_API_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            self._retry_after = time.monotonic() + self._FAILURE_COOLDOWN_SECONDS
            logger.warning("Pill image API lookup failed: %s", type(exc).__name__)
            return ""

        self._retry_after = 0.0
        matched_image_urls: list[str] = []
        for item in items:
            candidate_sequence = read_public_item_sequence(item)
            candidate_name = read_public_item_name(item)
            sequence_matches = bool(normalized_sequence) and (
                candidate_sequence == normalized_sequence
            )
            name_matches = bool(normalized_name) and (
                self._normalize_match_text(candidate_name) == normalized_name
            )
            candidate_matches = (
                sequence_matches if normalized_sequence else name_matches
            )
            if candidate_matches:
                image_url = read_public_image_url(item)
                if image_url:
                    matched_image_urls.append(image_url)

        unique_image_urls = list(dict.fromkeys(matched_image_urls))
        image_url = unique_image_urls[0] if len(unique_image_urls) == 1 else ""
        self._cache_image_url(cache_key, image_url)
        return image_url

    # Function Name: _normalize_match_text
    # Description:
    # - Remove all whitespace and lowercase product names for exact normalized-name comparison.
    # Parameters:
    # - value (str): Product name from the request or provider row.
    # Returns:
    # - Whitespace-free lowercase match key.
    @staticmethod
    def _normalize_match_text(value: str) -> str:
        return "".join(value.split()).lower()

    # Function Name: _cache_image_url
    # Description:
    # - Store a positive or empty image result, evicting the oldest inserted key when the cache is full.
    # Parameters:
    # - cache_key (str): Product-sequence or normalized-name cache key.
    # - image_url (str): Resolved safe image URL, or an empty string for a cached miss.
    # Returns:
    # - None; the in-memory result cache is updated.
    def _cache_image_url(self, cache_key: str, image_url: str) -> None:
        if len(self._image_url_cache) >= self._CACHE_LIMIT:
            oldest_key = next(iter(self._image_url_cache))
            self._image_url_cache.pop(oldest_key)
        self._image_url_cache[cache_key] = image_url
