# File Name: pill_identification_entity.py
# Role: Defines visual pill evidence, catalog reconciliation and confirmation-required single/multiple-pill results.

from dataclasses import dataclass, field
from typing import Literal

from sqlalchemy import Column, DateTime, Integer, String, Text, func
from core.database import Base



# Class Name: PillVisualFeatures
# Role:
# - Visible pill attributes extracted from user-supplied front/back photos.
# Responsibilities:
# - Preserve side-specific visual evidence, quality issues and confidence that both photos show the same pill.
# Attributes:
# - shape (str): Observed or registered pill shape.
# - colors (tuple[str, ...]): Observed or registered pill colors.
# - front_imprint (str): Imprint observed on the photographed front side.
# - back_imprint (str): Imprint observed on the photographed back side.
# - front_line (str): Division line observed on the photographed front side.
# - back_line (str): Division line observed on the photographed back side.
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


# Class Name: PillCatalogEntry
# Role:
# - Normalized public MFDS catalog data used for deterministic matching.
# Responsibilities:
# - Keep product identity, appearance, imprints and image provenance together for deterministic ranking.
# Attributes:
# - item_seq (str): Canonical MFDS product identifier.
# - item_name (str): Public medication product name.
# - shape (str): Observed or registered pill shape.
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


# Class Name: PillCatalogDownloadReport
# Role:
# - Auditable row accounting for one complete MFDS catalog download.
# Responsibilities:
# - Account for advertised, fetched, valid, rejected and duplicate rows plus download cost.
# Attributes:
# - advertised_rows (int): Total row count announced by the public API.
# - fetched_rows (int): Rows received across all response pages before validation.
# - valid_rows (int): Rows passing validation, including duplicate identifiers.
# - accepted_unique_rows (int): Validated products retained after identifier deduplication.
# - rejected_rows (int): Fetched rows excluded by validation.
# - duplicate_rows (int): Additional validated rows sharing an accepted product identifier.
# - page_count (int): Number of downloaded response pages.
# - response_bytes (int): Total downloaded response body size in bytes.
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


# Class Name: PillCatalogSnapshot
# Role:
# - One validated MFDS catalog generation and its reconciliation evidence.
# Responsibilities:
# - Verify that report totals reconcile with one immutable accepted-entry generation.
# Attributes:
# - entries (tuple[PillCatalogEntry, ...]): Immutable accepted MFDS pill-reference generation.
# - report (PillCatalogDownloadReport): Download accounting attached to the accepted catalog generation.
@dataclass(frozen=True)
class PillCatalogSnapshot:
    """One validated MFDS catalog generation and its reconciliation evidence."""

    entries: tuple[PillCatalogEntry, ...]
    report: PillCatalogDownloadReport

    # Function Name: __post_init__
    # Description:
    # - Requires nonnegative reconciliation counts and verifies fetched, valid, duplicate and accepted row totals against the actual entries.
    # Parameters:
    # - None.
    # Returns:
    # - None.
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


# Class Name: PillCatalogReconciliationReport
# Role:
# - Evidence that the downloaded identifier set was published exactly.
# Responsibilities:
# - Gate publication on download coverage, the expected product floor and exact persisted product-ID sets.
# Attributes:
# - source (PillCatalogDownloadReport): Download accounting used as publication evidence.
# - kpic_product_floor (int): Minimum accepted product count required for publication.
# - persisted_rows (int): Number of product identifiers stored after replacement.
# - missing_persisted_rows (int): Accepted product identifiers absent from storage.
# - unexpected_persisted_rows (int): Stored product identifiers absent from the accepted generation.
@dataclass(frozen=True)
class PillCatalogReconciliationReport:
    """Evidence that the downloaded identifier set was published exactly."""

    source: PillCatalogDownloadReport
    kpic_product_floor: int
    persisted_rows: int
    missing_persisted_rows: int
    unexpected_persisted_rows: int

    # Function Name: is_publishable
    # Description:
    # - Checks advertised download coverage, the product-count floor and exact persisted identifier reconciliation.
    # Parameters:
    # - None.
    # Returns:
    # - True when fetched rows match the advertised count, accepted rows meet the floor and no persisted IDs are missing or unexpected.
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


# Class Name: PillIdentificationCandidate
# Role:
# - One ranked MFDS product candidate that still requires user confirmation.
# Responsibilities:
# - Preserve matched visual attributes and score beside the public product identity.
# Attributes:
# - item_seq (str): Canonical MFDS product identifier.
# - item_name (str): Public medication product name.
# - shape (str): Observed or registered pill shape.
# - colors (tuple[str, ...]): Observed or registered pill colors.
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


# Class Name: PillIdentificationResult
# Role:
# - Candidate identification result; it is intentionally not a diagnosis.
# Responsibilities:
# - Reject confidence without candidates and disallow disabling mandatory user confirmation.
# Attributes:
# - observed_features (PillVisualFeatures): Visual evidence extracted from the supplied pill photographs.
# - candidates (tuple[PillIdentificationCandidate, ...]): Ranked product matches that still require user confirmation.
# - is_confident (bool): Whether candidate and image evidence meets the confidence policy.
# - requires_confirmation (Literal[True]): Mandatory user confirmation before using an identification candidate.
@dataclass(frozen=True)
class PillIdentificationResult:
    """Candidate identification result; it is intentionally not a diagnosis."""

    observed_features: PillVisualFeatures
    candidates: tuple[PillIdentificationCandidate, ...] = field(default_factory=tuple)
    is_confident: bool = False
    requires_confirmation: Literal[True] = True

    # Function Name: __post_init__
    # Description:
    # - Keeps user confirmation mandatory and rejects a confident result without candidates.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __post_init__(self) -> None:
        if self.requires_confirmation is not True:
            raise ValueError("Pill identification always requires confirmation.")
        if self.is_confident and not self.candidates:
            raise ValueError("An empty pill result cannot be confident.")


# Class Name: PillBoundingBox
# Role:
# - Normalized pill location within the source image.
# Responsibilities:
# - Enforce positive normalized dimensions that stay inside the source image.
# Attributes:
# - left (float): Left edge as a fraction of image width.
# - top (float): Top edge as a fraction of image height.
# - width (float): Positive box width relative to the source image.
# - height (float): Positive box height relative to the source image.
@dataclass(frozen=True)
class PillBoundingBox:
    """Normalized pill location within the source image."""

    left: float
    top: float
    width: float
    height: float

    # Function Name: __post_init__
    # Description:
    # - Requires positive normalized dimensions and a bounding box entirely inside the source image.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __post_init__(self) -> None:
        values = (self.left, self.top, self.width, self.height)
        if any(not 0.0 <= value <= 1.0 for value in values):
            raise ValueError("Pill bounding-box coordinates must be normalized.")
        if self.width <= 0.0 or self.height <= 0.0:
            raise ValueError("Pill bounding boxes must have positive dimensions.")
        if self.left + self.width > 1.0 or self.top + self.height > 1.0:
            raise ValueError("Pill bounding boxes must stay inside the image.")


# Class Name: MultiplePillObservation
# Role:
# - One spatially distinct pill and its independently ranked result.
# Responsibilities:
# - Bind a positive one-based observation number to its location and independent result.
# Attributes:
# - bounding_box (PillBoundingBox): Normalized image region containing the observed pill.
@dataclass(frozen=True)
class MultiplePillObservation:
    """One spatially distinct pill and its independently ranked result."""

    index: int
    bounding_box: PillBoundingBox
    identification: PillIdentificationResult

    # Function Name: __post_init__
    # Description:
    # - Requires each detected pill to have a positive one-based observation index.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __post_init__(self) -> None:
        if self.index < 1:
            raise ValueError("Pill observation indexes are one-based.")


# Class Name: MultiplePillIdentificationResult
# Role:
# - Safe one-photo result that never bypasses per-pill confirmation.
# Responsibilities:
# - Enforce one to ten consecutively numbered observations and mandatory confirmation.
# Attributes:
# - observations (tuple[MultiplePillObservation, ...]): Spatially separate pills with independent identification results.
# - requires_confirmation (Literal[True]): Mandatory user confirmation before using an identification candidate.
@dataclass(frozen=True)
class MultiplePillIdentificationResult:
    """Safe one-photo result that never bypasses per-pill confirmation."""

    observations: tuple[MultiplePillObservation, ...]
    requires_confirmation: Literal[True] = True

    # Function Name: __post_init__
    # Description:
    # - Requires user confirmation, one to ten observations and contiguous one-based numbering.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def __post_init__(self) -> None:
        if self.requires_confirmation is not True:
            raise ValueError("Multiple-pill identification always requires confirmation.")
        if not 1 <= len(self.observations) <= 10:
            raise ValueError("A multiple-pill result must contain 1 to 10 observations.")
        expected = tuple(range(1, len(self.observations) + 1))
        actual = tuple(observation.index for observation in self.observations)
        if actual != expected:
            raise ValueError("Pill observations must use contiguous one-based indexes.")


# Class Name: PillIdentificationReference
# Role:
# - Shared cached copy of public MFDS pill-identification metadata.
# Responsibilities:
# - Persist the shared product catalog with unique product IDs and appearance lookup indexes.
# Attributes:
# - item_seq (String): Canonical MFDS product identifier.
# - item_name (String): Public medication product name.
# - shape (String): Observed or registered pill shape.
# - updated_at (DateTime): Timestamp of the most recent local reference-row update.
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
