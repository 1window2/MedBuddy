# File Name: request_voice_guide_control.py
# Role: Control class for medication voice guide text generation.

from fastapi import HTTPException

from entities.medication_detail_entity import MedicationDetail


# Class Name: RequestVoiceGuide
# Role: Requests voice guide generation.
class RequestVoiceGuide:
    # Function Name: requestVoiceGuide
    # Description:
    # - Class diagram compatible wrapper for medication voice guide text generation.
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
        return self.request_voice_guide(medication_detail, language)

    # Function Name: request_voice_guide
    # Description:
    # - Builds a patient-facing voice guide string from medication detail data.
    # Parameters:
    # - medication_detail: Medication detail entity used as guide source data.
    # - language: User setting language code.
    # Returns:
    # - API-compatible voice guide dictionary.
    def request_voice_guide(
        self,
        medication_detail: MedicationDetail,
        language: str = "ko",
    ) -> dict[str, object]:
        voice_guide_text = self.getVoiceGuideText(medication_detail, language)
        return {
            "success": True,
            "message": "Voice guide text was generated.",
            "data": {
                "voice_guide_text": voice_guide_text,
                "language": self._normalize_language(language),
            },
        }

    # Function Name: getVoiceGuideText
    # Description:
    # - Class diagram compatible operation for retrieving voice guide text.
    # Parameters:
    # - medication_detail: Medication detail entity used as guide source data.
    # - language: User setting language code.
    # Returns:
    # - Voice guide text.
    def getVoiceGuideText(
        self,
        medication_detail: MedicationDetail,
        language: str = "ko",
    ) -> str:
        normalized_language = self._normalize_language(language)
        if normalized_language == "en":
            return self._build_english_guide(medication_detail)
        return self._build_korean_guide(medication_detail)

    def _build_korean_guide(self, medication_detail: MedicationDetail) -> str:
        lines = [
            self._line("약 이름", medication_detail.item_name),
            self._line("복용 방법", medication_detail.usage_method),
            self._line("1회 복용량", medication_detail.dosage_per_time),
            self._line("하루 복용 횟수", medication_detail.daily_frequency),
            self._line("총 복용일", medication_detail.total_days),
            self._line("주의사항", medication_detail.warning),
            self._line("효능", medication_detail.efficacy),
            self._line("추가 안내", medication_detail.ai_guide or ""),
        ]
        return self._join_lines(lines)

    def _build_english_guide(self, medication_detail: MedicationDetail) -> str:
        lines = [
            self._line("Medication", medication_detail.item_name),
            self._line("How to take", medication_detail.usage_method),
            self._line("Dose per time", medication_detail.dosage_per_time),
            self._line("Daily frequency", medication_detail.daily_frequency),
            self._line("Total days", medication_detail.total_days),
            self._line("Warning", medication_detail.warning),
            self._line("Effect", medication_detail.efficacy),
            self._line("Additional guide", medication_detail.ai_guide or ""),
        ]
        return self._join_lines(lines)

    def _line(self, label: str, value: str) -> str:
        normalized_value = (value or "").strip()
        if not normalized_value:
            return ""
        return f"{label}: {normalized_value}"

    def _join_lines(self, lines: list[str]) -> str:
        voice_guide_text = "\n".join(line for line in lines if line.strip())
        if not voice_guide_text:
            raise HTTPException(
                status_code=400,
                detail="Voice guide source data is empty.",
            )
        return voice_guide_text

    def _normalize_language(self, language: str) -> str:
        normalized_language = (language or "").strip().lower()
        if normalized_language not in {"ko", "en"}:
            raise HTTPException(status_code=400, detail="Language is not supported.")
        return normalized_language
