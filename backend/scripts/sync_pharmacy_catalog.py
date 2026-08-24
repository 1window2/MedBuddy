# File Name: sync_pharmacy_catalog.py
# Role: Synchronizes nationwide pharmacy schedules into the shared database.

import argparse
import asyncio
import logging
import math
from pathlib import Path
import sys

from sqlalchemy.orm import Session


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from boundaries.pharmacy_api_boundary import (  # noqa: E402
    NationalEmergencyMedicalCenterPharmacyAPI,
)
from core.database import SessionLocal  # noqa: E402
from entities.pharmacy_catalog_entity import PharmacyCatalogEntry  # noqa: E402
from repositories.pharmacy_catalog_repository import (  # noqa: E402
    PharmacyCatalogRepository,
)


logger = logging.getLogger(__name__)
_MINIMUM_COMPLETE_ROWS = 10_000
_MINIMUM_RETENTION_RATIO = 0.80


async def synchronize(
    db: Session,
    *,
    page_size: int,
    max_retries: int,
    only_if_empty: bool,
) -> int:
    repository = PharmacyCatalogRepository(db)
    if only_if_empty and repository.count() > 0:
        logger.info("Pharmacy catalogue already contains rows; bootstrap skipped.")
        return 0

    boundary = NationalEmergencyMedicalCenterPharmacyAPI(timeout_seconds=30)
    entries_by_id: dict[str, PharmacyCatalogEntry] = {}
    page_no = 1
    total_pages: int | None = None
    try:
        while total_pages is None or page_no <= total_pages:
            for attempt in range(max_retries + 1):
                try:
                    entries, total_count = await boundary.fetchCatalogPage(
                        page_no=page_no,
                        page_size=page_size,
                    )
                    break
                except Exception:
                    if attempt >= max_retries:
                        raise
                    logger.warning(
                        "Pharmacy page %s failed; retrying %s/%s.",
                        page_no,
                        attempt + 1,
                        max_retries,
                    )
                    await asyncio.sleep(min(2**attempt, 8))
            if total_pages is None:
                total_pages = max(1, math.ceil(total_count / page_size))
                logger.info(
                    "Pharmacy catalogue reports %s rows across %s pages.",
                    total_count,
                    total_pages,
                )
            if not entries and page_no <= total_pages:
                raise RuntimeError(
                    f"Pharmacy catalogue ended before reported page {page_no}."
                )
            for entry in entries:
                entries_by_id[entry.pharmacy_id] = entry
            logger.info(
                "Pharmacy page %s/%s processed: %s usable rows.",
                page_no,
                total_pages,
                len(entries),
            )
            page_no += 1

        refreshed_count = len(entries_by_id)
        if refreshed_count < _MINIMUM_COMPLETE_ROWS:
            raise RuntimeError(
                f"Pharmacy refresh returned only {refreshed_count} usable rows."
            )
        previous_count = repository.count()
        if (
            previous_count >= _MINIMUM_COMPLETE_ROWS
            and refreshed_count < math.ceil(previous_count * _MINIMUM_RETENTION_RATIO)
        ):
            raise RuntimeError(
                "Pharmacy refresh volume dropped below the safe retention threshold."
            )
        repository.replace_all(list(entries_by_id.values()))
        logger.info("Published %s pharmacy catalogue rows.", refreshed_count)
        return refreshed_count
    finally:
        await boundary.close()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Synchronize the nationwide public pharmacy catalogue."
    )
    parser.add_argument("--page-size", type=int, default=1_000)
    parser.add_argument("--max-retries", type=int, default=5)
    parser.add_argument("--only-if-empty", action="store_true")
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    logging.getLogger("httpx").setLevel(logging.WARNING)
    args = parse_args()
    db = SessionLocal()
    try:
        asyncio.run(
            synchronize(
                db,
                page_size=args.page_size,
                max_retries=args.max_retries,
                only_if_empty=args.only_if_empty,
            )
        )
    finally:
        db.close()


if __name__ == "__main__":
    main()
