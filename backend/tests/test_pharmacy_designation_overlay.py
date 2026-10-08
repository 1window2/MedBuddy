# File Name: test_pharmacy_designation_overlay.py
# Role: Regression coverage for the checked-in Seoul late-night pharmacy designations and
#   conservative catalog matching.
"""Tests for source-bound official public late-night designation overlays."""

import os
import sys
from datetime import datetime
from pathlib import Path

from sqlalchemy import event, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.setdefault("GEMINI_API_KEY", "test-gemini-key")
os.environ.setdefault("PUBLIC_DATA_API_KEY", "test-public-data-key")

from entities.pharmacy_catalog_entity import (  # noqa: E402
    PharmacyCatalogEntry,
    PharmacyCatalogRecord,
)
from repositories.pharmacy_catalog_repository import (  # noqa: E402
    PharmacyCatalogRepository,
)
from scripts.sync_pharmacy_catalog import (  # noqa: E402
    _apply_designations,
    _load_public_late_night_designations,
)


# Function Name: _entry
# Description:
# - Builds a catalog pharmacy with a selected name and telephone for designation matching.
# Parameters:
# - name (str): Pharmacy name matched against the designation source.
# - telephone (str): Pharmacy phone number used for official-designation matching.
# Returns:
# - PharmacyCatalogEntry: Synthetic authoritative catalog record with the requested identity and
#   matching fields.
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


# Function Name: test_current_seoul_source_contains_forty_designations
# Description:
# - Requires the checked-in Seoul source to contain forty designations, all attributed to the
#   expected official source URL.
# Parameters:
# - None.
# Returns:
# - None.
def test_current_seoul_source_contains_forty_designations() -> None:
    designations = _load_public_late_night_designations()

    assert len(designations) == 40
    assert all(
        item["source_url"]
        == "https://news.seoul.go.kr/welfare/archives/567003"
        for item in designations.values()
    )


# Function Name: test_overlay_requires_both_phone_and_normalized_name_match
# Description:
# - Attaches an official designation only when both telephone and normalized pharmacy name
#   match.
# Parameters:
# - None.
# Returns:
# - None.
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


_CATALOG_DOWNLOADED_AT = datetime(2026, 9, 1, 3, 0, 0)


# Function Name: _designation
# Description:
# - Builds one official designation in the shape the sync script loads from the source file.
# Parameters:
# - name (str): Designated pharmacy name.
# - operating_days (list[int]): ISO weekdays of the designated shifts.
# Returns:
# - dict[str, object]: Designation metadata stored under "public_late_night".
def _designation(name: str, operating_days: list[int]) -> dict[str, object]:
    return {
        "source_name": "Seoul Metropolitan Government",
        "source_url": "https://news.seoul.go.kr/welfare/archives/567003",
        "verified_at": "2026-08-19",
        "start_time": "2200",
        "end_time": "0100",
        "name": name,
        "operating_days": operating_days,
    }


# Function Name: _seed_catalog
# Description:
# - Stores six catalogue pharmacies that share one download timestamp: three that the test
#   designations name, one whose telephone matches a designation with another name, and two
#   ordinary ones.
# Parameters:
# - db (Session): Session on the test database.
# Returns:
# - None.
def _seed_catalog(db: Session) -> None:
    rows = [
        ("P1", "세종약국", "02-3210-2292"),
        ("P2", "대풍약국", "02-2252-3944"),
        ("P3", "유쾌한약국", "02-2234-0827"),
        ("P4", "다른이름약국", "02-3210-2292"),
        ("P5", "동네약국", "031-000-0001"),
        ("P6", "새벽약국", "031-000-0002"),
    ]
    db.bulk_insert_mappings(
        PharmacyCatalogRecord,
        [
            {
                "pharmacy_id": pharmacy_id,
                "name": name,
                "address": "Seoul",
                "telephone": telephone,
                "latitude": 37.5665,
                "longitude": 126.9780,
                "weekly_hours": {},
                "official_designations": {},
                "source_updated_at": _CATALOG_DOWNLOADED_AT,
            }
            for pharmacy_id, name, telephone in rows
        ],
    )
    db.commit()


# Class Name: _CatalogWriteCounter
# Role: Counts what one designation refresh writes to pharmacy_catalog_records.
# Responsibilities:
# - Record every UPDATE of the catalogue table with the number of rows it targets.
# - Report the rows SQLite actually changed, as an independent second measure.
# Attributes:
# - updated_row_counts (list[int]): Parameter-set count of each catalogue UPDATE since reset.
class _CatalogWriteCounter:
    # Function Name: __init__
    # Description:
    # - Starts listening to the statements of the test engine.
    # Parameters:
    # - engine (Engine): Engine whose statements are observed.
    # Returns:
    # - None.
    def __init__(self, engine: Engine) -> None:
        self.updated_row_counts: list[int] = []
        self._changes_at_reset = 0
        event.listen(engine, "before_cursor_execute", self._record)

    # Function Name: _record
    # Description:
    # - Notes a catalogue UPDATE and how many rows its parameters address.
    # Parameters:
    # - statement (str): SQL text about to run.
    # - parameters (object): One parameter set, or a list of them for executemany.
    # - executemany (bool): Whether several parameter sets are sent.
    # - conn, cursor, context (object): Remaining event arguments; unused.
    # Returns:
    # - None.
    def _record(self, conn, cursor, statement, parameters, context, executemany) -> None:
        if statement.lstrip().upper().startswith("UPDATE PHARMACY_CATALOG_RECORDS"):
            self.updated_row_counts.append(len(parameters) if executemany else 1)

    # Function Name: reset
    # Description:
    # - Forgets earlier statements and remembers SQLite's change counter as the new baseline.
    # Parameters:
    # - db (Session): Session on the observed engine.
    # Returns:
    # - None.
    def reset(self, db: Session) -> None:
        self._changes_at_reset = db.execute(text("SELECT total_changes()")).scalar_one()
        self.updated_row_counts.clear()

    # Function Name: rows_changed
    # Description:
    # - Reads how many rows SQLite inserted, updated or deleted since the last reset.
    # Parameters:
    # - db (Session): Session on the observed engine.
    # Returns:
    # - int: Changed row count.
    def rows_changed(self, db: Session) -> int:
        current = db.execute(text("SELECT total_changes()")).scalar_one()
        return current - self._changes_at_reset


# Function Name: _stored_designations
# Description:
# - Reads the stored overlay of every pharmacy through a fresh query.
# Parameters:
# - db (Session): Session on the test database.
# Returns:
# - dict[str, dict]: official_designations by pharmacy ID.
def _stored_designations(db: Session) -> dict[str, dict]:
    db.expire_all()
    return {
        row.pharmacy_id: row.official_designations
        for row in db.query(PharmacyCatalogRecord).all()
    }


# Function Name: test_designation_refresh_writes_only_rows_whose_overlay_changed
# Description:
# - The refresh that runs on every deploy writes the matches once, writes nothing when the
#   designation list is unchanged, and afterwards writes exactly the rows whose overlay differs:
#   one changed designation, one removed designation, one new designation.
# - The catalogue download timestamp is never touched, so a designation refresh cannot make an
#   old catalogue look fresh.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing in-memory engine with the ORM schema.
# - fk_db (Session): Session on fk_engine.
# Returns:
# - None.
def test_designation_refresh_writes_only_rows_whose_overlay_changed(
    fk_engine: Engine,
    fk_db: Session,
) -> None:
    _seed_catalog(fk_db)
    repository = PharmacyCatalogRepository(fk_db)
    writes = _CatalogWriteCounter(fk_engine)
    designations = {
        "0232102292": _designation("세종약국", [1, 2, 3, 4, 5, 6, 7]),
        "0222523944": _designation("대풍약국", [1, 6, 7]),
        "0299999999": _designation("목록에만 있는 약국", [1]),
    }

    # First deploy: both matching pharmacies get their overlay; the same telephone under
    # another name (P4) does not.
    writes.reset(fk_db)
    assert repository.apply_official_designations_by_phone(designations) == 2
    assert writes.updated_row_counts == [2] and writes.rows_changed(fk_db) == 2
    assert _stored_designations(fk_db) == {
        "P1": {"public_late_night": designations["0232102292"]},
        "P2": {"public_late_night": designations["0222523944"]},
        "P3": {}, "P4": {}, "P5": {}, "P6": {},
    }

    # Every later deploy with the same list: no UPDATE at all.
    for _ in range(2):
        writes.reset(fk_db)
        assert repository.apply_official_designations_by_phone(designations) == 2
        assert writes.updated_row_counts == [] and writes.rows_changed(fk_db) == 0

    # A new list: P1 unchanged, P2 with other days, P3 added; then P2 leaves the list.
    changed = {
        "0232102292": designations["0232102292"],
        "0222523944": _designation("대풍약국", [5, 6]),
        "0222340827": _designation("유쾌한약국", [2, 3, 4, 5]),
    }
    writes.reset(fk_db)
    assert repository.apply_official_designations_by_phone(changed) == 3
    assert writes.updated_row_counts == [2] and writes.rows_changed(fk_db) == 2
    del changed["0222523944"]
    writes.reset(fk_db)
    assert repository.apply_official_designations_by_phone(changed) == 2
    assert writes.updated_row_counts == [1] and writes.rows_changed(fk_db) == 1
    assert _stored_designations(fk_db) == {
        "P1": {"public_late_night": changed["0232102292"]},
        "P2": {},
        "P3": {"public_late_night": changed["0222340827"]},
        "P4": {}, "P5": {}, "P6": {},
    }

    assert {
        row.source_updated_at for row in fk_db.query(PharmacyCatalogRecord).all()
    } == {_CATALOG_DOWNLOADED_AT}
    assert repository.latest_updated_at() == _CATALOG_DOWNLOADED_AT


# Function Name: test_checked_in_designation_list_is_stable_after_one_refresh
# Description:
# - The checked-in Seoul list survives the JSON round trip unchanged: after it was applied once,
#   applying it again finds every stored overlay equal and writes no row.
# Parameters:
# - fk_engine (Engine): Foreign-key-enforcing in-memory engine with the ORM schema.
# - fk_db (Session): Session on fk_engine.
# Returns:
# - None.
def test_checked_in_designation_list_is_stable_after_one_refresh(
    fk_engine: Engine,
    fk_db: Session,
) -> None:
    designations = _load_public_late_night_designations()
    fk_db.bulk_insert_mappings(
        PharmacyCatalogRecord,
        [
            {
                "pharmacy_id": f"S{index:04d}",
                "name": str(designation["name"]),
                "address": "Seoul",
                "telephone": telephone,
                "latitude": 37.5665,
                "longitude": 126.9780,
                "weekly_hours": {},
                "official_designations": {},
                "source_updated_at": _CATALOG_DOWNLOADED_AT,
            }
            for index, (telephone, designation) in enumerate(designations.items())
        ],
    )
    fk_db.commit()
    repository = PharmacyCatalogRepository(fk_db)
    writes = _CatalogWriteCounter(fk_engine)

    writes.reset(fk_db)
    assert repository.apply_official_designations_by_phone(designations) == 40
    assert writes.rows_changed(fk_db) == 40

    writes.reset(fk_db)
    assert repository.apply_official_designations_by_phone(designations) == 40
    assert writes.updated_row_counts == [] and writes.rows_changed(fk_db) == 0
