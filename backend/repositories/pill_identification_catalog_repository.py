# File Name: pill_identification_catalog_repository.py
# Role: Persists public MFDS pill-identification metadata in an isolated cache DB.

from datetime import UTC, datetime, timedelta
from pathlib import Path

from sqlalchemy import create_engine, func
from sqlalchemy.orm import Session, sessionmaker

from entities.pill_identification_entity import (
    PillCatalogEntry,
    PillIdentificationReference,
)

PILL_CATALOG_DATABASE_PATH = (
    Path(__file__).resolve().parents[1] / "pill_identification_catalog.db"
)
PILL_CATALOG_DATABASE_URL = (
    f"sqlite:///{PILL_CATALOG_DATABASE_PATH.as_posix()}"
)
pill_catalog_engine = create_engine(
    PILL_CATALOG_DATABASE_URL,
    connect_args={"check_same_thread": False},
)
_PillCatalogSessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=pill_catalog_engine,
)


def _initialize_pill_identification_catalog() -> None:
    """Creates the isolated public-reference cache table when absent."""

    PillIdentificationReference.__table__.create(
        bind=pill_catalog_engine,
        checkfirst=True,
    )


def open_pill_catalog_session() -> Session:
    """Opens a catalog session after lazily ensuring its isolated schema."""

    _initialize_pill_identification_catalog()
    return _PillCatalogSessionLocal()


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

        latest_update = self.db.query(
            func.max(PillIdentificationReference.updated_at)
        ).scalar()
        if latest_update is None:
            return False

        cutoff = datetime.now(UTC).replace(tzinfo=None) - max_age
        return latest_update >= cutoff

    def replace_all(self, entries: list[PillCatalogEntry]) -> None:
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
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
