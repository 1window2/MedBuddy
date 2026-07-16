# File Name: request_voice_guide_control.py
# Role: Control class for medication voice guide text generation.

from fastapi import HTTPException

from entities.medication_detail_entity import MedicationDetail


# Class Name: RequestVoiceGuide
# Role: Requests voice guide generation.
class RequestVoiceGuide:
    # Function Name: requestVoiceGuide
    # Description:
    # - Builds a patient-facing voice guide string from medication detail data.
    # Parameters:
    # - medication_detail: Medication detail entity used as guide source data.
    # - language: User setting language code.
    # Returns:
    # - API-compatible voice guide dictionary.
    def requestVoiceGuide(
        self,
        medication_detail: MedicationDetail,
        language: str = "ko",
    ) -> dict[str, object]:
        normalized_language = self._normalize_language(language)
        voice_guide_text = medication_detail.getVoiceGuideText(normalized_language)
        if not voice_guide_text:
            raise HTTPException(
                status_code=400,
                detail="Voice guide source data is empty.",
            )
        return {
            "success": True,
            "message": "Voice guide text was generated.",
            "data": {
                "voice_guide_text": voice_guide_text,
                "language": normalized_language,
            },
        }

    def _normalize_language(self, language: str) -> str:
        normalized_language = (language or "").strip().lower()
        if normalized_language not in {"ko", "en"}:
            raise HTTPException(status_code=400, detail="Language is not supported.")
        return normalized_language
