# File Name: pill_identification_catalog_repository.py
# Role: Persists public MFDS pill-identification metadata in the shared DB.

from datetime import UTC, datetime, timedelta
from sqlalchemy import func
from sqlalchemy.orm import Session

from core.database import SessionLocal

from entities.pill_identification_entity import (
    PillCatalogEntry,
    PillIdentificationReference,
)


def open_pill_catalog_session() -> Session:
    """Opens the shared application-database session used by the catalog."""

    return SessionLocal()


class PillIdentificationCatalogRepository:
    """Database adapter for the replaceable public pill-reference catalog."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def list_all(self) -> list[PillCatalogEntry]:
        rows = (
            self.db.query(
                PillIdentificationReference.item_seq,
                PillIdentificationReference.item_name,
                PillIdentificationReference.entp_name,
                PillIdentificationReference.image_url,
                PillIdentificationReference.shape,
                PillIdentificationReference.color_primary,
                PillIdentificationReference.color_secondary,
                PillIdentificationReference.print_front,
                PillIdentificationReference.print_back,
                PillIdentificationReference.line_front,
                PillIdentificationReference.line_back,
            )
            .order_by(PillIdentificationReference.item_seq.asc())
            .all()
        )
        return [
            PillCatalogEntry(
                item_seq=row.item_seq,
                item_name=row.item_name,
                entp_name=row.entp_name or "",
                image_url=row.image_url or "",
                shape=row.shape or "",
                color_primary=row.color_primary or "",
                color_secondary=row.color_secondary or "",
                print_front=row.print_front or "",
                print_back=row.print_back or "",
                line_front=row.line_front or "",
                line_back=row.line_back or "",
            )
            for row in rows
        ]

    def is_fresh(self, *, minimum_rows: int, max_age: timedelta) -> bool:
        row_count = self.db.query(PillIdentificationReference).count()
        if row_count < minimum_rows:
            return False

        oldest_update = self.db.query(
            func.min(PillIdentificationReference.updated_at)
        ).scalar()
        if oldest_update is None:
            return False

        cutoff = datetime.now(UTC).replace(tzinfo=None) - max_age
        return oldest_update >= cutoff

    def replace_all(
        self,
        entries: list[PillCatalogEntry],
        *,
        commit: bool = True,
    ) -> None:
        mappings = [
            {
                "item_seq": entry.item_seq,
                "item_name": entry.item_name,
                "entp_name": entry.entp_name,
                "image_url": entry.image_url,
                "shape": entry.shape,
                "color_primary": entry.color_primary,
                "color_secondary": entry.color_secondary,
                "print_front": entry.print_front,
                "print_back": entry.print_back,
                "line_front": entry.line_front,
                "line_back": entry.line_back,
            }
            for entry in entries
        ]

        try:
            self.db.query(PillIdentificationReference).delete(
                synchronize_session=False
            )
            self.db.bulk_insert_mappings(PillIdentificationReference, mappings)
            if commit:
                self.db.commit()
            else:
                self.db.flush()
        except Exception:
            if commit:
                self.db.rollback()
            raise
