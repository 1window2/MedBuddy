"""Tests for source-bound official public late-night designation overlays."""

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from entities.pharmacy_catalog_entity import PharmacyCatalogEntry  # noqa: E402
from scripts.sync_pharmacy_catalog import (  # noqa: E402
    _apply_designations,
    _load_public_late_night_designations,
)


def _entry(*, name: str, telephone: str) -> PharmacyCatalogEntry:
    return PharmacyCatalogEntry(
        pharmacy_id="C1234",
        name=name,
        address="Seoul",
        telephone=telephone,
        latitude=37.5665,
        longitude=126.9780,
        weekly_hours={},
    )


def test_current_seoul_source_contains_forty_designations() -> None:
    designations = _load_public_late_night_designations()

    assert len(designations) == 40
    assert all(
        item["source_url"]
        == "https://news.seoul.go.kr/welfare/archives/567003"
        for item in designations.values()
    )


def test_overlay_requires_both_phone_and_normalized_name_match() -> None:
    designations = _load_public_late_night_designations()
    matching, matching_count = _apply_designations(
        [_entry(name="세종약국", telephone="02-3210-2292")],
        designations,
    )
    mismatched, mismatched_count = _apply_designations(
        [_entry(name="Unrelated Pharmacy", telephone="02-3210-2292")],
        designations,
    )

    assert matching_count == 1
    assert "public_late_night" in matching[0].official_designations
    assert mismatched_count == 0
    assert mismatched[0].official_designations == {}
