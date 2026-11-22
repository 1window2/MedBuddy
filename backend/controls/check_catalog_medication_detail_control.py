# File Name: check_catalog_medication_detail_control.py
# Role: Reads one exact local catalog product without search, network access or writes.

import json
import re
from typing import Any

from sqlalchemy.orm import Session

from boundaries.medication_summary_boundary import MISSING_DETAIL_TEXT, read_medication_detail_text
from boundaries.public_drug_api_boundary import (
    _read_public_item_text,
    read_public_image_url,
    read_public_item_sequence,
)
from entities.medication_detail_entity import (
    MedicationDetail,
    _DrugApprovalInfo,
    _DrugBasicInfo,
)
from services.local_medication_catalog import LocalMedicationCatalog
from services.catalog_document_text import read_catalog_document
from schemas.medication import _MAX_DETAIL_TEXT_LENGTH

CATALOG_ITEM_SEQ_MAX_LENGTH = 32
CATALOG_ITEM_SEQ_PATTERN = r"^[0-9]{1,32}$"


class CheckCatalogMedicationDetail:
    """Read-only exact identity lookup; never constructs search or AI collaborators."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def get_detail(self, item_seq: str) -> MedicationDetail | None:
        if re.fullmatch(CATALOG_ITEM_SEQ_PATTERN, item_seq) is None:
            raise ValueError("Catalog item_seq must contain 1 to 32 ASCII digits.")

        # Even a caller's pending changes must not be flushed by this read path.
        with self.db.no_autoflush:
            basic = self.db.query(_DrugBasicInfo).filter(
                _DrugBasicInfo.item_seq == item_seq,
            ).first()
            if basic is not None:
                return self._save_compatible(self._basic_detail(basic))
            approval = self.db.query(_DrugApprovalInfo).filter(
                _DrugApprovalInfo.item_seq == item_seq,
            ).first()
            return self._save_compatible(self._approval_detail(approval)) if approval is not None else None

    @staticmethod
    def _save_compatible(detail: MedicationDetail) -> MedicationDetail:
        updates = {}
        for field in (
            "efficacy", "usage_method", "warning", "precaution", "interaction",
            "side_effect", "storage_method", "ai_guide",
        ):
            value = getattr(detail, field)
            if value and len(value) > _MAX_DETAIL_TEXT_LENGTH:
                # A partial warning can change its meaning. Leave the field missing so
                # post-save enrichment can supply a bounded summary instead.
                updates[field] = (
                    MISSING_DETAIL_TEXT if field in {"efficacy", "usage_method", "warning"}
                    else None if field == "ai_guide" else ""
                )
        return detail.model_copy(update=updates)

    @staticmethod
    def _trusted_payload(item: _DrugBasicInfo | _DrugApprovalInfo) -> dict[str, Any]:
        try:
            payload = json.loads(item.raw_json)
        except (TypeError, ValueError):
            return {}
        if not isinstance(payload, dict):
            return {}
        raw_sequence = read_public_item_sequence(payload)
        if raw_sequence and raw_sequence != item.item_seq:
            return {}
        return payload

    @staticmethod
    def _safety_fields(payload: dict[str, Any]) -> dict[str, str]:
        return {
            "precaution": _read_public_item_text(payload, ("atpnQesitm",)),
            "interaction": _read_public_item_text(payload, ("intrcQesitm",)),
            "side_effect": _read_public_item_text(payload, ("seQesitm",)),
            "storage_method": _read_public_item_text(
                payload, ("depositMethodQesitm", "STORAGE_METHOD"),
            ),
            "image_url": read_public_image_url(payload),
        }

    def _basic_detail(self, item: _DrugBasicInfo) -> MedicationDetail:
        payload = self._trusted_payload(item)
        fields = self._safety_fields(payload)
        for field, column in (
            ("interaction", item.interaction),
            ("side_effect", item.side_effect),
            ("storage_method", item.deposit_method),
        ):
            fields[field] = read_medication_detail_text(column, fields[field])
        return MedicationDetail(
            item_seq=item.item_seq,
            item_name=item.item_name,
            manufacturer=item.entp_name or _read_public_item_text(
                payload, ("ENTP_NAME", "entpName", "entp_name"),
            ),
            efficacy=read_medication_detail_text(
                read_medication_detail_text(item.efficacy, "")
                or _read_public_item_text(payload, ("efcyQesitm",)),
            ),
            usage_method=read_medication_detail_text(
                read_medication_detail_text(item.use_method, "")
                or _read_public_item_text(payload, ("useMethodQesitm",)),
            ),
            warning=read_medication_detail_text(
                read_medication_detail_text(item.warning_message, "")
                or _read_public_item_text(payload, ("atpnWarnQesitm",)),
            ),
            source="Local DB (basic catalog)",
            ai_guide=item.ai_guide,
            **fields,
        )

    def _approval_detail(self, item: _DrugApprovalInfo) -> MedicationDetail:
        payload = self._trusted_payload(item)
        fields = self._safety_fields(payload)
        has_summary = False
        for field, summary, document, aliases in (
            ("efficacy", item.summary_efficacy, item.efficacy_doc, ("EE_DOC_DATA", "efcyQesitm")),
            ("usage_method", item.summary_use_method, item.use_method_doc, ("UD_DOC_DATA", "useMethodQesitm")),
            ("warning", item.summary_warning_message, item.warning_doc, ("NB_DOC_DATA", "atpnWarnQesitm")),
        ):
            if (
                LocalMedicationCatalog._is_usable_summary_text(summary)
                and not LocalMedicationCatalog._is_missing_text(summary)
            ):
                summary_text = read_catalog_document(summary)
                if summary_text:
                    fields[field] = summary_text
                    has_summary = True
                    continue
            fields[field] = read_medication_detail_text(read_catalog_document(
                read_medication_detail_text(document, "")
                or _read_public_item_text(payload, aliases),
            ))
        return MedicationDetail(
            item_seq=item.item_seq,
            item_name=item.item_name,
            manufacturer=item.entp_name or _read_public_item_text(
                payload, ("ENTP_NAME", "entpName", "entp_name"),
            ),
            source=(
                "Local DB (approval catalog; stored summary)"
                if has_summary else "Local DB (approval catalog)"
            ),
            ai_guide=item.ai_guide,
            **fields,
        )
