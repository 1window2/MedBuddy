# File Name: pill_identification_entity.py
# Role: Domain entities and local MFDS reference rows for loose-pill identification.

from dataclasses import dataclass, field

from sqlalchemy import Column, DateTime, Integer, String, Text, func
from sqlalchemy.orm import declarative_base

PillCatalogBase = declarative_base()


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
    requires_confirmation: bool = True


class PillIdentificationReference(PillCatalogBase):
    """Locally cached copy of public MFDS pill-identification metadata."""

    __tablename__ = "pill_identification_references"

    id = Column(Integer, primary_key=True, index=True)
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
