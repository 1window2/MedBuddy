"""External boundaries for Korean public medication data services."""

import asyncio
import logging
import time
from typing import Any
from urllib.parse import urlsplit

import httpx

from core.config import settings

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


def read_public_item_name(item: dict[str, Any]) -> str:
    return _read_public_item_text(item, _PUBLIC_ITEM_NAME_FIELDS)


def read_public_item_sequence(item: dict[str, Any]) -> str:
    return _read_public_item_text(item, _PUBLIC_ITEM_SEQUENCE_FIELDS)


def read_public_image_url(item: dict[str, Any]) -> str:
    image_url = _read_public_item_text(item, _PUBLIC_IMAGE_URL_FIELDS)
    if image_url.startswith("//"):
        image_url = f"https:{image_url}"
    if not image_url or len(image_url) > 3000:
        return ""

    try:
        parsed_url = urlsplit(image_url)
    except ValueError:
        return ""
    if parsed_url.scheme.lower() not in {"http", "https"} or not parsed_url.netloc:
        return ""
    return image_url


class _PublicDrugTransport:
    """Shared HTTP and response-normalization implementation."""

    def __init__(self, timeout_seconds: float = 15.0) -> None:
        self.timeout_seconds = timeout_seconds

    async def request_items(
        self,
        url: str,
        params: dict[str, object],
    ) -> tuple[list[dict[str, Any]], int]:
        async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
            response = await client.get(url, params=params)

        if response.status_code != 200:
            raise RuntimeError("The public medication API did not respond successfully.")

        data = response.json()
        if not isinstance(data, dict):
            raise RuntimeError("The public medication API returned an invalid payload.")
        self._validate_response_header(data)
        body = self._extract_body(data)
        return self._normalize_items(body.get("items")), self._safe_int(
            body.get("totalCount")
        )

    @staticmethod
    def _extract_body(data: dict[str, Any]) -> dict[str, Any]:
        body = data.get("body")
        if isinstance(body, dict):
            return body

        response = data.get("response")
        if isinstance(response, dict) and isinstance(response.get("body"), dict):
            return response["body"]
        return {}

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

    @staticmethod
    def _safe_int(value: Any) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0


class PublicDrugSmallAPI:
    """UML external boundary for the patient-facing eDrug catalog."""

    def __init__(
        self,
        timeout_seconds: float = 15.0,
        transport: _PublicDrugTransport | None = None,
    ) -> None:
        self._transport = transport or _PublicDrugTransport(timeout_seconds)

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
        )


class PublicDrugLargeAPI:
    """UML external boundary for the complete approval catalog."""

    def __init__(
        self,
        timeout_seconds: float = 15.0,
        transport: _PublicDrugTransport | None = None,
    ) -> None:
        self._transport = transport or _PublicDrugTransport(timeout_seconds)

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
        )


class PillImageAPI:
    """v0.0.9 extension for exact-match MFDS pill image lookup."""

    _CACHE_LIMIT = 512
    _FAILURE_COOLDOWN_SECONDS = 60.0

    def __init__(
        self,
        timeout_seconds: float = 15.0,
        transport: _PublicDrugTransport | None = None,
    ) -> None:
        self._transport = transport or _PublicDrugTransport(timeout_seconds)
        self._image_url_cache: dict[str, str] = {}
        self._retry_after = 0.0

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

    @staticmethod
    def _normalize_match_text(value: str) -> str:
        return "".join(value.split()).lower()

    def _cache_image_url(self, cache_key: str, image_url: str) -> None:
        if len(self._image_url_cache) >= self._CACHE_LIMIT:
            oldest_key = next(iter(self._image_url_cache))
            self._image_url_cache.pop(oldest_key)
        self._image_url_cache[cache_key] = image_url
