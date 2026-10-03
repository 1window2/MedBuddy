# File Name: input_prescription_control.py
# Role: Coordinates de-identified prescription text analysis, privacy masking and catalog-backed medication-name verification.

import json
import logging
import secrets
from typing import Any

from google import genai
from sqlalchemy.orm import Session

from boundaries.prescription_ocr_boundary import OCRServiceBoundary
from core.config import settings
from entities.medication_schedule_entity import MedicationSchedule
from entities.prescription_analysis_entity import (
    MedicationCandidateList,
    PrescriptionAnalysisResult,
    PrescriptionText,
)
from services.prescription_medication_name_verifier import (
    MedicationNameVerification,
    PrescriptionMedicationNameVerifier,
)
from services.prescription_parser import (
    INFO_UNAVAILABLE,
    normalize_prescription_candidates,
)

logger = logging.getLogger(__name__)


# Class Name: PrescriptionAnalysisTimeoutError
# Role:
# - Raised when the required external OCR stage exceeds its deadline.
# Responsibilities:
# - Distinguish a required OCR deadline failure from optional name-correction fallback failures.
class PrescriptionAnalysisTimeoutError(RuntimeError):
    """Raised when the required external OCR stage exceeds its deadline."""


# Class Name: InputPrescription
# Role:
# - Coordinates de-identified prescription text structuring and validation.
# Responsibilities:
# - Accept only prescription text already de-identified on the user's device.
# - Request structured prescription extraction from Gemini.
# - Clean, decode, mask, and validate extracted prescription data.
# Attributes:
# - client (genai.Client): Gemini client used for prescription text analysis.
# - model_name (str): Gemini model name.
class InputPrescription:
    _PRESCRIPTION_RESPONSE_SCHEMA = {
        "type": "OBJECT",
        "required": [
            "hospital_name",
            "prescription_date",
            "medications",
        ],
        "properties": {
            "hospital_name": {
                "type": "STRING",
                "description": "Hospital or pharmacy name. Use '정보 없음' when unavailable.",
            },
            "prescription_date": {
                "type": "STRING",
                "description": "약봉투나 처방전에 적힌 조제일자 또는 처방일자를 YYYY-MM-DD 형식으로 추출한다. 없으면 '정보 없음'을 사용한다.",
            },
            "medications": {
                "type": "ARRAY",
                "description": "Extracted medication list.",
                "items": {
                    "type": "OBJECT",
                    "required": [
                        "drug_name",
                        "dosage_per_time",
                        "daily_frequency",
                        "total_days",
                    ],
                    "properties": {
                        "drug_name": {
                            "type": "STRING",
                            "description": "약품명",
                        },
                        "dosage_per_time": {
                            "type": "STRING",
                            "description": "Dose per administration, for example '1정'.",
                        },
                        "daily_frequency": {
                            "type": "STRING",
                            "description": "Daily frequency, for example '3회'.",
                        },
                        "total_days": {
                            "type": "STRING",
                            "description": "Total duration, for example '7일'.",
                        },
                    },
                },
            },
        },
    }

    # Function Name: __init__
    # Description:
    # - Binds the Gemini client, bounded OCR analysis boundary and catalog-backed name verifier.
    # Parameters:
    # - client (genai.Client | None): Gemini client shared by prescription OCR and name verification.
    # - model_name (str): Configured AI model identifier.
    # - db (Session | None): SQLAlchemy session for this unit of work.
    # - medication_name_verifier (PrescriptionMedicationNameVerifier | None): Catalog-constrained OCR medication-name verifier.
    # - ocr_service_boundary (OCRServiceBoundary | None): Bounded external OCR-text analysis boundary.
    # Returns:
    # - None.
    def __init__(
        self,
        client: genai.Client | None = None,
        model_name: str = "gemini-3.1-flash-lite",
        db: Session | None = None,
        medication_name_verifier: PrescriptionMedicationNameVerifier | None = None,
        ocr_service_boundary: OCRServiceBoundary | None = None,
    ) -> None:
        self.client = client or genai.Client(
            api_key=settings.GEMINI_API_KEY,
            http_options={"api_version": "v1alpha"},
        )
        self.model_name = model_name
        self.ocr_service_boundary = ocr_service_boundary or OCRServiceBoundary(
            client=self.client,
            model_name=self.model_name,
            response_schema=self._PRESCRIPTION_RESPONSE_SCHEMA,
            request_timeout_seconds=settings.PRESCRIPTION_OCR_TIMEOUT_SECONDS,
        )
        self.medication_name_verifier = (
            medication_name_verifier
            or PrescriptionMedicationNameVerifier(
                db=db,
                ai_timeout_seconds=(
                    settings.PRESCRIPTION_NAME_FALLBACK_TIMEOUT_SECONDS
                ),
            )
        )

    # 함수이름: requestPrescriptionText
    # 함수역할:
    # - 기기에서 개인정보를 제거한 OCR 텍스트를 구조화 처방 정보로 변환한다.
    # - 개인정보 보호 경계상 원본 처방전 이미지는 백엔드에서 받지 않는다.
    # 매개변수:
    # - masked_text (str): 기기 내 OCR과 민감정보 제거가 끝난 처방전 텍스트
    # 반환값:
    # - API 호환 복약 일정 분석 결과
    async def requestPrescriptionText(
        self,
        masked_text: str,
    ) -> dict[str, object]:
        normalized_text = masked_text.strip()
        if not normalized_text:
            raise ValueError("Masked prescription text is empty.")
        if len(normalized_text) > 100_000:
            raise ValueError("Masked prescription text exceeds 100,000 characters.")
        try:
            response_text = await self.ocr_service_boundary.extractPrescriptionTextData(
                normalized_text
            )
        except TimeoutError as exc:
            raise PrescriptionAnalysisTimeoutError(
                "처방전 인식 서비스 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요."
            ) from exc
        return await self._build_prescription_response(response_text)

    # Function Name: _build_prescription_response
    # Description:
    # - Parses AI JSON, applies secondary privacy masking and normalization, then verifies medication names and assigns a new prescription batch.
    # Parameters:
    # - response_text (str): Raw AI response text before JSON fence removal and decoding.
    # Returns:
    # - Safe prescription metadata, verified medication rows and parsing counts.
    async def _build_prescription_response(
        self,
        response_text: str,
    ) -> dict[str, object]:
        cleaned_text = self._clean_response_text(response_text)

        try:
            raw_data = json.loads(cleaned_text)
        except json.JSONDecodeError as exc:
            logger.error(
                "Prescription analysis JSON decoding failed: response_length=%d",
                len(response_text),
            )
            raise ValueError("AI returned an invalid JSON response.") from exc

        masked_data = self._apply_secondary_masking(raw_data)
        (
            hospital_name,
            prescription_date,
            medication_candidates,
            raw_medication_count,
        ) = normalize_prescription_candidates(masked_data)
        safe_data = self.buildAnalysisResult(
            medication_candidates,
            hospital_name=hospital_name,
            prescription_date=prescription_date,
        ).to_payload(raw_medication_count=raw_medication_count)
        prescription_date = safe_data.get("prescription_date", INFO_UNAVAILABLE)
        verified_medication_schedules = await self._to_verified_medication_schedules(
            safe_data.get("medications", []),
        )
        medication_schedules = [
            self._to_prescription_medication_payload(
                medication_schedule,
                verification,
                prescription_date,
            )
            for medication_schedule, verification in verified_medication_schedules
        ]
        return {
            "hospital_name": safe_data.get("hospital_name", INFO_UNAVAILABLE),
            "prescription_date": prescription_date,
            "prescription_batch_id": secrets.token_urlsafe(18),
            "medications": medication_schedules,
            "raw_medication_count": safe_data.get(
                "raw_medication_count",
                len(medication_schedules),
            ),
            "parsed_medication_count": len(medication_schedules),
            "skipped_medication_count": safe_data.get("skipped_medication_count", 0),
        }

    # Function Name: buildAnalysisResult
    # Description:
    # - Class diagram compatible operation for promoting candidates into a prescription analysis result entity.
    # Parameters:
    # - candidates (MedicationCandidateList): MedicationCandidateList extracted from a prescription.
    # - hospital_name (str): Hospital name retained in the normalized prescription.
    # - prescription_date (str): Prescription dispensing date, if available.
    # Returns:
    # - PrescriptionAnalysisResult entity.
    def buildAnalysisResult(
        self,
        candidates: MedicationCandidateList,
        *,
        hospital_name: str = INFO_UNAVAILABLE,
        prescription_date: str = INFO_UNAVAILABLE,
    ) -> PrescriptionAnalysisResult:
        analysis_result = PrescriptionAnalysisResult(
            hospital_name=hospital_name,
            prescription_date=prescription_date,
        )
        for candidate in candidates.candidates:
            analysis_result.addMedicationCandidate(candidate)
        return analysis_result

    # Function Name: _clean_response_text
    # Description:
    # - Removes markdown fences and surrounding whitespace from model output.
    # Parameters:
    # - response_text (str): Raw Gemini response text.
    # Returns:
    # - JSON-only string.
    def _clean_response_text(self, response_text: str) -> str:
        cleaned_text = response_text.strip()
        if cleaned_text.startswith("```json"):
            cleaned_text = cleaned_text[7:]
        if cleaned_text.startswith("```"):
            cleaned_text = cleaned_text[3:]
        if cleaned_text.endswith("```"):
            cleaned_text = cleaned_text[:-3]
        return cleaned_text.strip()

    # Function Name: _apply_secondary_masking
    # Description:
    # - Applies regex-based secondary masking to structured prescription data.
    # Parameters:
    # - data (dict[str, Any]): Decoded prescription dictionary.
    # Returns:
    # - Masked prescription dictionary.
    def _apply_secondary_masking(self, data: dict[str, Any]) -> dict[str, Any]:
        data_str = json.dumps(data, ensure_ascii=False)
        return json.loads(self.maskSensitiveInfo(data_str))

    # Function Name: maskSensitiveInfo
    # Description:
    # - Class diagram compatible operation for removing sensitive identifiers.
    # Parameters:
    # - rawText (str): Raw prescription text or serialized extraction payload.
    # Returns:
    # - Text with sensitive identifiers masked.
    def maskSensitiveInfo(self, rawText: str) -> str:
        return PrescriptionText(raw_text=rawText).removeSensitiveInfoByRegex()

    # Function Name: _to_verified_medication_schedules
    # Description:
    # - Verifies candidate names in one batch and copies schedules only when their canonical names change.
    # Parameters:
    # - items (list[dict[str, Any]]): Normalized prescription medication dictionaries.
    # Returns:
    # - Ordered pairs of schedule entities and name-verification evidence.
    async def _to_verified_medication_schedules(
        self,
        items: list[dict[str, Any]],
    ) -> list[tuple[MedicationSchedule, MedicationNameVerification]]:
        medication_schedules = [
            MedicationSchedule(**item) for item in items
        ]
        verifications = await self.medication_name_verifier.verify_many(
            [
                medication_schedule.medication_name
                for medication_schedule in medication_schedules
            ],
            self.client,
            self.model_name,
        )

        verified_schedules: list[tuple[MedicationSchedule, MedicationNameVerification]] = []
        for medication_schedule, verification in zip(
            medication_schedules,
            verifications,
        ):
            if verification.canonical_name != medication_schedule.medication_name:
                medication_schedule = medication_schedule.model_copy(
                    update={"medication_name": verification.canonical_name},
                )
            verified_schedules.append((medication_schedule, verification))
        return verified_schedules

    # Function Name: _to_prescription_medication_payload
    # Description:
    # - Converts a MedicationSchedule entity into the API payload expected by the current Flutter analysis-result flow.
    # Parameters:
    # - medication_schedule (MedicationSchedule): Validated MedicationSchedule entity.
    # - verification (MedicationNameVerification): Canonical name, source and confidence for one OCR medication.
    # - prescription_date (str): Prescription dispensing date, if available.
    # Returns:
    # - Dictionary containing only prescription-analysis response fields.
    def _to_prescription_medication_payload(
        self,
        medication_schedule: MedicationSchedule,
        verification: MedicationNameVerification,
        prescription_date: str,
    ) -> dict[str, object]:
        return {
            "prescription_date": prescription_date,
            "drug_name": medication_schedule.medication_name,
            "raw_drug_name": verification.raw_name,
            "name_confidence": verification.confidence,
            "name_correction_source": verification.source,
            "dosage_per_time": medication_schedule.dosage,
            "daily_frequency": medication_schedule.intake_time,
            "total_days": medication_schedule.medication_time,
        }
