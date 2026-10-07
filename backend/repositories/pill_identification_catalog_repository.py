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


# Function Name: open_pill_catalog_session
# Description:
# - Open a session against the shared application database for pill catalog work.
# Parameters:
# - None.
# Returns:
# - A new SQLAlchemy Session that the caller must close.
def open_pill_catalog_session() -> Session:
    """Opens the shared application-database session used by the catalog."""

    return SessionLocal()


# Class Name: PillIdentificationCatalogRepository
# Role:
# - Persists replaceable public MFDS pill-reference snapshots.
# Responsibilities:
# - Read lightweight ordered entries, check snapshot age and size, expose reconciliation IDs and bulk-replace data.
# Attributes:
# - db (Session): Caller-managed catalog transaction session.
class PillIdentificationCatalogRepository:
    """Database adapter for the replaceable public pill-reference catalog."""

    # Function Name: __init__
    # Description:
    # - Retain the caller's session for reference-catalog reads and replacements.
    # Parameters:
    # - db (Session): Caller-provided SQLAlchemy session for persisted records.
    # Returns:
    # - None; no connection lifecycle or transaction is changed.
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: list_all
    # Description:
    # - Read only public reference columns in item-sequence order and normalize nullable descriptive fields to empty strings.
    # Parameters:
    # - None.
    # Returns:
    # - Ordered PillCatalogEntry list for the persisted snapshot.
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

    # Function Name: is_fresh
    # Description:
    # - Require enough catalog rows and ensure even the oldest update timestamp lies within the allowed age.
    # Parameters:
    # - minimum_rows (int): Minimum reference count required before a snapshot is usable.
    # - max_age (timedelta): Maximum permitted age of the cached snapshot.
    # Returns:
    # - True for a sufficiently large snapshot whose oldest row is fresh; False when empty or stale.
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

    # Function Name: list_item_sequences
    # Description:
    # - Read the exact stored public item identifiers for upstream snapshot reconciliation.
    # Parameters:
    # - None.
    # Returns:
    # - Set of persisted item-sequence strings.
    def list_item_sequences(self) -> set[str]:
        """Returns the exact persisted public identifiers for reconciliation."""

        rows = self.db.query(PillIdentificationReference.item_seq).all()
        return {str(row.item_seq) for row in rows}

    # Function Name: replace_all
    # Description:
    # - Replace all pill-reference rows using bulk mappings, committing or flushing according to transaction ownership.
    # Parameters:
    # - entries (list[PillCatalogEntry]): Complete normalized MFDS pill-reference snapshot.
    # - commit (bool): Whether to commit and own rollback, or only flush for the caller's transaction.
    # Returns:
    # - None; rolls back on error only when commit is enabled.
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
