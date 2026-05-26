# File Name: medication_text_service.py
# Role: Normalizes OCR or AI-extracted medication text for downstream lookup.

import re


# Class Name: MedicationTextService
# Role: Converts raw medication text into stable public API search keywords.
# Responsibilities:
#   - Normalize whitespace in raw text.
#   - Remove dosage fragments that make public API lookup fail.
#   - Preserve current behavior while moving text logic out of the router.
class MedicationTextService:
    _DOSAGE_PATTERN = re.compile(
        r"\d{1,10}(?:\.\d{1,5})?\s{0,5}(?:mg|g|ml)",
        flags=re.IGNORECASE,
    )

    # Function Name: normalize_raw_text
    # Description:
    # - Collapses raw OCR text into a single searchable line.
    # Parameters:
    # - raw_text: Raw text extracted from prescription or medication candidates.
    # Returns:
    # - Whitespace-normalized text.
    def normalize_raw_text(self, raw_text: str) -> str:
        return " ".join(raw_text.replace("\n", " ").split()).strip()

    # Function Name: build_search_keyword
    # Description:
    # - Builds the drug search keyword currently expected by DrugService.
    # - Keeps the existing suffix stripping behavior from api/router.py.
    # Parameters:
    # - raw_text: Raw medication text from frontend.
    # Returns:
    # - Search keyword for public drug APIs.
    def build_search_keyword(self, raw_text: str) -> str:
        normalized_text = self.normalize_raw_text(raw_text)
        parts = self._DOSAGE_PATTERN.split(normalized_text)
        keyword = parts[0] if parts else normalized_text
        return keyword.replace("정", "").replace("캡슐", "").strip()
