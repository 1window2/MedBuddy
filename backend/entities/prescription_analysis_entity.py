# File Name: prescription_analysis_entity.py
# Role: Entity classes for prescription analysis results from the class diagram.

import re
from dataclasses import dataclass, field


_RRN_PATTERN = re.compile(r"(\d{6})[-]\d{7}")


# Class Name: PrescriptionText
# Role: Holds raw and medication-only prescription text.
@dataclass(frozen=True)
class PrescriptionText:
    raw_text: str
    medication_only_text: str = ""

    @property
    def rawText(self) -> str:
        return self.raw_text

    @property
    def medicationOnlyText(self) -> str:
        return self.medication_only_text

    # Function Name: removeSensitiveInfoByRegex
    # Description:
    # - Masks resident registration numbers in the prescription text.
    # Returns:
    # - Text with sensitive identifiers masked.
    def removeSensitiveInfoByRegex(self) -> str:
        source_text = self.medication_only_text or self.raw_text
        return _RRN_PATTERN.sub(r"\1-*******", source_text)


# Class Name: MedicationCandidate
# Role: Represents one medication candidate extracted from a prescription.
@dataclass(frozen=True)
class MedicationCandidate:
    drug_name: str
    dosage_per_time: str
    daily_frequency: str
    total_days: str

    @property
    def drugName(self) -> str:
        return self.drug_name

    @property
    def dosagePerTime(self) -> str:
        return self.dosage_per_time

    @property
    def dailyFrequency(self) -> str:
        return self.daily_frequency

    @property
    def totalDays(self) -> str:
        return self.total_days

    def identity_key(self) -> tuple[str, str, str, str]:
        return (
            self.drug_name,
            self.dosage_per_time,
            self.daily_frequency,
            self.total_days,
        )

    def to_payload(self) -> dict[str, str]:
        return {
            "drug_name": self.drug_name,
            "dosage_per_time": self.dosage_per_time,
            "daily_frequency": self.daily_frequency,
            "total_days": self.total_days,
        }


# Class Name: MedicationCandidateList
# Role: Collects medication candidates extracted from a prescription.
@dataclass
class MedicationCandidateList:
    candidates: list[MedicationCandidate] = field(default_factory=list)

    # Function Name: addCandidate
    # Description:
    # - Adds one medication candidate.
    def addCandidate(self, candidate: MedicationCandidate) -> None:
        self.candidates.append(candidate)

    # Function Name: isEmpty
    # Description:
    # - Reports whether the list has no medication candidates.
    def isEmpty(self) -> bool:
        return not self.candidates

    # Function Name: findByName
    # Description:
    # - Finds the first medication candidate with the requested drug name.
    def findByName(self, drugName: str) -> MedicationCandidate | None:
        return next(
            (
                candidate
                for candidate in self.candidates
                if candidate.drug_name == drugName
            ),
            None,
        )

    def deduplicated(self) -> "MedicationCandidateList":
        deduplicated_candidates = MedicationCandidateList()
        seen_keys: set[tuple[str, str, str, str]] = set()
        for candidate in self.candidates:
            candidate_key = candidate.identity_key()
            if candidate_key in seen_keys:
                continue
            seen_keys.add(candidate_key)
            deduplicated_candidates.addCandidate(candidate)
        return deduplicated_candidates

    def to_payload(self) -> list[dict[str, str]]:
        return [candidate.to_payload() for candidate in self.candidates]


# Class Name: PrescriptionAnalysisResult
# Role: Represents a normalized prescription analysis result.
@dataclass
class PrescriptionAnalysisResult:
    hospital_name: str
    prescription_date: str
    medication_candidates: MedicationCandidateList = field(
        default_factory=MedicationCandidateList
    )

    @property
    def hospitalName(self) -> str:
        return self.hospital_name

    @property
    def prescriptionDate(self) -> str:
        return self.prescription_date

    @property
    def candidateCount(self) -> int:
        return len(self.medication_candidates.candidates)

    # Function Name: addMedicationCandidate
    # Description:
    # - Adds one medication candidate to this analysis result.
    def addMedicationCandidate(self, candidate: MedicationCandidate) -> None:
        self.medication_candidates.addCandidate(candidate)

    def to_payload(self, raw_medication_count: int) -> dict[str, object]:
        return {
            "hospital_name": self.hospital_name,
            "prescription_date": self.prescription_date,
            "medications": self.medication_candidates.to_payload(),
            "raw_medication_count": raw_medication_count,
            "parsed_medication_count": self.candidateCount,
            "skipped_medication_count": raw_medication_count - self.candidateCount,
        }
