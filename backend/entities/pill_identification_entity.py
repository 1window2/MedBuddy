# File Name: pill_identification_entity.py
# Role: Domain entities and local MFDS reference rows for loose-pill identification.

from dataclasses import dataclass, field
from typing import Literal

from sqlalchemy import Column, DateTime, Integer, String, Text, func
from core.database import Base



@dataclass(frozen=True)
class PillVisualFeatures:
    """Visible pill attributes extracted from user-supplied front/back photos."""

    shape: str = "unknown"
    colors: tuple[str, ...] = ()
    front_imprint: str = ""
    back_imprint: str = ""
    front_line: str = "unknown"
    back_line: str = "unknown"
    quality: str = "usable"
    quality_issues: tuple[str, ...] = ()
    same_pill: bool = True
    side_consistency_confidence: float = 1.0


@dataclass(frozen=True)
class PillCatalogEntry:
    """Normalized public MFDS catalog data used for deterministic matching."""

    item_seq: str
    item_name: str
    entp_name: str = ""
    image_url: str = ""
    shape: str = ""
    color_primary: str = ""
    color_secondary: str = ""
    print_front: str = ""
    print_back: str = ""
    line_front: str = ""
    line_back: str = ""


@dataclass(frozen=True)
class PillCatalogDownloadReport:
    """Auditable row accounting for one complete MFDS catalog download."""

    advertised_rows: int
    fetched_rows: int
    valid_rows: int
    accepted_unique_rows: int
    rejected_rows: int
    duplicate_rows: int
    page_count: int
    response_bytes: int


@dataclass(frozen=True)
class PillCatalogSnapshot:
    """One validated MFDS catalog generation and its reconciliation evidence."""

    entries: tuple[PillCatalogEntry, ...]
    report: PillCatalogDownloadReport

    def __post_init__(self) -> None:
        numeric_values = (
            self.report.advertised_rows,
            self.report.fetched_rows,
            self.report.valid_rows,
            self.report.accepted_unique_rows,
            self.report.rejected_rows,
            self.report.duplicate_rows,
            self.report.response_bytes,
        )
        if any(value < 0 for value in numeric_values) or self.report.page_count < 1:
            raise ValueError("Pill catalog snapshot counts must be non-negative.")
        if self.report.fetched_rows != (
            self.report.valid_rows + self.report.rejected_rows
        ):
            raise ValueError("Pill catalog fetched-row accounting is inconsistent.")
        if self.report.valid_rows != (
            self.report.accepted_unique_rows + self.report.duplicate_rows
        ):
            raise ValueError("Pill catalog valid-row accounting is inconsistent.")
        if len(self.entries) != self.report.accepted_unique_rows:
            raise ValueError("Pill catalog snapshot row accounting is inconsistent.")


@dataclass(frozen=True)
class PillCatalogReconciliationReport:
    """Evidence that the downloaded identifier set was published exactly."""

    source: PillCatalogDownloadReport
    kpic_product_floor: int
    persisted_rows: int
    missing_persisted_rows: int
    unexpected_persisted_rows: int

    @property
    def is_publishable(self) -> bool:
        """Returns whether the synchronized generation satisfies every gate."""

        return (
            self.source.fetched_rows == self.source.advertised_rows
            and self.source.accepted_unique_rows >= self.kpic_product_floor
            and self.persisted_rows == self.source.accepted_unique_rows
            and self.missing_persisted_rows == 0
            and self.unexpected_persisted_rows == 0
        )


@dataclass(frozen=True)
class PillIdentificationCandidate:
    """One ranked MFDS product candidate that still requires user confirmation."""

    item_seq: str
    item_name: str
    entp_name: str
    image_url: str
    shape: str
    colors: tuple[str, ...]
    print_front: str
    print_back: str
    match_score: float
    matched_attributes: tuple[str, ...] = ()


@dataclass(frozen=True)
class PillIdentificationResult:
    """Candidate identification result; it is intentionally not a diagnosis."""

    observed_features: PillVisualFeatures
    candidates: tuple[PillIdentificationCandidate, ...] = field(default_factory=tuple)
    is_confident: bool = False
    requires_confirmation: Literal[True] = True

    def __post_init__(self) -> None:
        if self.requires_confirmation is not True:
            raise ValueError("Pill identification always requires confirmation.")
        if self.is_confident and not self.candidates:
            raise ValueError("An empty pill result cannot be confident.")


@dataclass(frozen=True)
class PillBoundingBox:
    """Normalized pill location within the source image."""

    left: float
    top: float
    width: float
    height: float

    def __post_init__(self) -> None:
        values = (self.left, self.top, self.width, self.height)
        if any(not 0.0 <= value <= 1.0 for value in values):
            raise ValueError("Pill bounding-box coordinates must be normalized.")
        if self.width <= 0.0 or self.height <= 0.0:
            raise ValueError("Pill bounding boxes must have positive dimensions.")
        if self.left + self.width > 1.0 or self.top + self.height > 1.0:
            raise ValueError("Pill bounding boxes must stay inside the image.")


@dataclass(frozen=True)
class MultiplePillObservation:
    """One spatially distinct pill and its independently ranked result."""

    index: int
    bounding_box: PillBoundingBox
    identification: PillIdentificationResult

    def __post_init__(self) -> None:
        if self.index < 1:
            raise ValueError("Pill observation indexes are one-based.")


@dataclass(frozen=True)
class MultiplePillIdentificationResult:
    """Safe one-photo result that never bypasses per-pill confirmation."""

    observations: tuple[MultiplePillObservation, ...]
    requires_confirmation: Literal[True] = True

    def __post_init__(self) -> None:
        if self.requires_confirmation is not True:
            raise ValueError("Multiple-pill identification always requires confirmation.")
        if not 1 <= len(self.observations) <= 10:
            raise ValueError("A multiple-pill result must contain 1 to 10 observations.")
        expected = tuple(range(1, len(self.observations) + 1))
        actual = tuple(observation.index for observation in self.observations)
        if actual != expected:
            raise ValueError("Pill observations must use contiguous one-based indexes.")


class PillIdentificationReference(Base):
    """Shared cached copy of public MFDS pill-identification metadata."""

    __tablename__ = "pill_identification_references"

    id = Column(Integer, primary_key=True)
    item_seq = Column(String, unique=True, index=True, nullable=False)
    item_name = Column(String, index=True, nullable=False)
    entp_name = Column(String, nullable=True)
    image_url = Column(Text, nullable=True)
    shape = Column(String, index=True, nullable=True)
    color_primary = Column(String, index=True, nullable=True)
    color_secondary = Column(String, index=True, nullable=True)
    print_front = Column(String, index=True, nullable=True)
    print_back = Column(String, index=True, nullable=True)
    line_front = Column(String, nullable=True)
    line_back = Column(String, nullable=True)
    updated_at = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
