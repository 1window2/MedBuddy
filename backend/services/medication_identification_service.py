# File Name: medication_identification_service.py
# Role: Coordinates medication keyword normalization and drug detail lookup.

from schemas.medication import MedicationResponse
from services.drug_service import DrugService
from services.medication_text_service import MedicationTextService


# Class Name: CheckMedicationDetail
# Role: Control class for requesting medication detail information.
# Responsibilities:
#   - Validate and normalize user-provided medication text.
#   - Delegate drug detail lookup to DrugService.
#   - Build the API response DTO.
# Attributes:
#   - text_service: MedicationTextService used for keyword extraction.
#   - drug_service: DrugService used for public API and AI guide lookup.
class CheckMedicationDetail:
    MAX_KEYWORD_LENGTH = 100

    def __init__(
        self,
        text_service: MedicationTextService,
        drug_service: DrugService,
    ) -> None:
        self.text_service = text_service
        self.drug_service = drug_service

    # Function Name: _validate_lookup_text
    # Description:
    # - Validates normalized medication text before dosage suffix stripping.
    # Parameters:
    # - text: Normalized medication lookup text.
    # Returns:
    # - None.
    def _validate_lookup_text(self, text: str) -> None:
        if not text:
            raise ValueError("추출된 텍스트가 없습니다.")
        if len(text) > self.MAX_KEYWORD_LENGTH:
            raise ValueError("텍스트가 너무 깁니다.")

    # Function Name: request_medication_detail
    # Description:
    # - Normalizes medication text and fetches detailed drug information.
    # Parameters:
    # - raw_text: Raw medication text supplied by the frontend.
    # Returns:
    # - MedicationResponse with success flag and MedicationDetail list.
    async def request_medication_detail(self, raw_text: str) -> MedicationResponse:
        normalized_text = self.text_service.normalize_raw_text(raw_text)
        self._validate_lookup_text(normalized_text)

        search_keyword = self.text_service.build_search_keyword(normalized_text)
        if not search_keyword:
            raise ValueError("추출된 텍스트가 없습니다.")

        drug_data = await self.drug_service.fetch_drug_info(search_keyword)

        if not drug_data:
            return MedicationResponse(
                success=False,
                message=f"'{search_keyword}'에 해당하는 약 정보를 찾을 수 없습니다.",
                data=[],
            )

        return MedicationResponse(
            success=True,
            message="약 정보 조회 성공",
            data=drug_data,
        )
