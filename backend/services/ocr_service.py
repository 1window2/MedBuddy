# File Name: ocr_service.py
# Role: Compatibility facade for text parsing and prescription image analysis.

from typing import Any

from schemas.ocr import PrescriptionData
from services.medication_text_service import MedicationTextService
from services.prescription_analysis_service import InputPrescription
from services.prescription_parser import parse_prescription


# Class Name: OCRService
# Role: Facade preserving the previous OCRService API while delegating responsibilities.
# Responsibilities:
#   - Provide raw text normalization for legacy callers.
#   - Parse OCR text through the prescription parser utility.
#   - Delegate image-based prescription analysis to InputPrescription.
# Attributes:
#   - text_service: MedicationTextService for text normalization.
#   - _input_prescription: Lazily-created InputPrescription control object.
class OCRService:
    def __init__(
        self,
        text_service: MedicationTextService | None = None,
        input_prescription: InputPrescription | None = None,
    ) -> None:
        self.text_service = text_service or MedicationTextService()
        self._input_prescription = input_prescription

    # Function Name: process_text
    # Description:
    # - Normalizes raw OCR text for legacy medication lookup callers.
    # Parameters:
    # - raw_text: Raw OCR text.
    # Returns:
    # - Whitespace-normalized text.
    def process_text(self, raw_text: str) -> str:
        return self.text_service.normalize_raw_text(raw_text)

    # Function Name: split_lines
    # Description:
    # - Splits OCR text into non-empty stripped lines.
    # Parameters:
    # - raw_text: Raw OCR text.
    # Returns:
    # - List of non-empty lines.
    def split_lines(self, raw_text: str) -> list[str]:
        if not raw_text:
            return []
        return [line.strip() for line in raw_text.splitlines() if line.strip()]

    # Function Name: parse_prescription_text
    # Description:
    # - Parses OCR text into a structured prescription dictionary.
    # Parameters:
    # - raw_text: Raw OCR text.
    # Returns:
    # - Parsed prescription dictionary.
    def parse_prescription_text(self, raw_text: str) -> dict[str, Any]:
        return parse_prescription(self.split_lines(raw_text))

    # Function Name: extract_prescription_data
    # Description:
    # - Delegates image prescription analysis to InputPrescription.
    # Parameters:
    # - image_bytes: Raw uploaded image bytes.
    # Returns:
    # - Validated PrescriptionData DTO.
    async def extract_prescription_data(self, image_bytes: bytes) -> PrescriptionData:
        if self._input_prescription is None:
            self._input_prescription = InputPrescription()
        return await self._input_prescription.request_prescription_image(image_bytes)
