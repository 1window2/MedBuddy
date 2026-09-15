# File Name: prescription_analysis_entity.py
# Role: Represents privacy-filtered prescription text, deduplicated medication candidates and analysis row counts.

import re
from dataclasses import dataclass, field


_RRN_PATTERN = re.compile(r"(\d{6})[-]\d{7}")


# Class Name: PrescriptionText
# Role:
# - Holds raw and medication-only prescription text.
# Responsibilities:
# - Separate original OCR text from the medication-only text used at the privacy boundary.
# Attributes:
# - raw_text (str): Source OCR text before medication-name normalization.
# - medication_only_text (str): Privacy-filtered text restricted to medication information.
@dataclass(frozen=True)
class PrescriptionText:
    raw_text: str
    medication_only_text: str = ""

    # Function Name: rawText
    # Description:
    # - Reads the stored source OCR text before medication-name normalization.
    # Parameters:
    # - None.
    # Returns:
    # - Source OCR text before medication-name normalization.
    @property
    def rawText(self) -> str:
        return self.raw_text

    # Function Name: medicationOnlyText
    # Description:
    # - Reads the stored privacy-filtered text restricted to medication information.
    # Parameters:
    # - None.
    # Returns:
    # - Privacy-filtered text restricted to medication information.
    @property
    def medicationOnlyText(self) -> str:
        return self.medication_only_text

    # Function Name: removeSensitiveInfoByRegex
    # Description:
    # - Masks resident registration numbers in the prescription text.
    # Parameters:
    # - None.
    # Returns:
    # - Text with sensitive identifiers masked.
    def removeSensitiveInfoByRegex(self) -> str:
        source_text = self.medication_only_text or self.raw_text
        return _RRN_PATTERN.sub(r"\1-*******", source_text)


# Class Name: MedicationCandidate
# Role:
# - Represents one medication candidate extracted from a prescription.
# Responsibilities:
# - Keep drug identity and dose, frequency and duration together for duplicate detection and serialization.
# Attributes:
# - drug_name (str): Medication name to search or serialize.
# - dosage_per_time (str): Dose per administration from the prescription.
# - daily_frequency (str): Number or description of doses per day.
# - total_days (str): Prescribed course duration.
@dataclass(frozen=True)
class MedicationCandidate:
    drug_name: str
    dosage_per_time: str
    daily_frequency: str
    total_days: str

    # Function Name: drugName
    # Description:
    # - Reads the stored medication name to search or serialize.
    # Parameters:
    # - None.
    # Returns:
    # - Medication name to search or serialize.
    @property
    def drugName(self) -> str:
        return self.drug_name

    # Function Name: dosagePerTime
    # Description:
    # - Reads the stored dose per administration from the prescription.
    # Parameters:
    # - None.
    # Returns:
    # - Dose per administration from the prescription.
    @property
    def dosagePerTime(self) -> str:
        return self.dosage_per_time

    # Function Name: dailyFrequency
    # Description:
    # - Reads the stored number or description of doses per day.
    # Parameters:
    # - None.
    # Returns:
    # - Number or description of doses per day.
    @property
    def dailyFrequency(self) -> str:
        return self.daily_frequency

    # Function Name: totalDays
    # Description:
    # - Reads the stored prescribed course duration.
    # Parameters:
    # - None.
    # Returns:
    # - Prescribed course duration.
    @property
    def totalDays(self) -> str:
        return self.total_days

    # Function Name: identity_key
    # Description:
    # - Uses the drug name and all dosage-course fields to distinguish duplicate OCR candidates.
    # Parameters:
    # - None.
    # Returns:
    # - Four-part name, dose, frequency and duration identity tuple.
    def identity_key(self) -> tuple[str, str, str, str]:
        return (
            self.drug_name,
            self.dosage_per_time,
            self.daily_frequency,
            self.total_days,
        )

    # Function Name: to_payload
    # Description:
    # - Exposes the normalized candidate using the prescription analysis API field names.
    # Parameters:
    # - None.
    # Returns:
    # - Drug name and dosage-course field dictionary.
    def to_payload(self) -> dict[str, str]:
        return {
            "drug_name": self.drug_name,
            "dosage_per_time": self.dosage_per_time,
            "daily_frequency": self.daily_frequency,
            "total_days": self.total_days,
        }


# Class Name: MedicationCandidateList
# Role:
# - Collects medication candidates extracted from a prescription.
# Responsibilities:
# - Preserve candidate order while supporting exact-name lookup and full-course deduplication.
# Attributes:
# - candidates (list[MedicationCandidate]): Ordered OCR medication candidates, including duplicates until explicitly deduplicated.
@dataclass
class MedicationCandidateList:
    candidates: list[MedicationCandidate] = field(default_factory=list)

    # Function Name: addCandidate
    # Description:
    # - Adds one medication candidate.
    # Parameters:
    # - candidate (MedicationCandidate): Normalized drug name and prescription dose-course fields.
    # Returns:
    # - None.
    def addCandidate(self, candidate: MedicationCandidate) -> None:
        self.candidates.append(candidate)

    # Function Name: isEmpty
    # Description:
    # - Checks whether prescription normalization produced any medication candidates.
    # Parameters:
    # - None.
    # Returns:
    # - True when the candidate collection is empty.
    def isEmpty(self) -> bool:
        return not self.candidates

    # Function Name: findByName
    # Description:
    # - Finds the first candidate whose stored drug name equals the supplied name.
    # Parameters:
    # - drugName (str): Exact medication name sought in the candidate collection.
    # Returns:
    # - Matching candidate, or None when the name is absent.
    def findByName(self, drugName: str) -> MedicationCandidate | None:
        return next(
            (
                candidate
                for candidate in self.candidates
                if candidate.drug_name == drugName
            ),
            None,
        )

    # Function Name: deduplicated
    # Description:
    # - Retains the first occurrence of each complete medication-and-course identity.
    # Parameters:
    # - None.
    # Returns:
    # - New candidate collection preserving the original encounter order.
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

    # Function Name: to_payload
    # Description:
    # - Serializes every normalized medication candidate in collection order.
    # Parameters:
    # - None.
    # Returns:
    # - List of prescription medication field dictionaries.
    def to_payload(self) -> list[dict[str, str]]:
        return [candidate.to_payload() for candidate in self.candidates]


# Class Name: PrescriptionAnalysisResult
# Role:
# - Represents a normalized prescription analysis result.
# Responsibilities:
# - Combine normalized metadata with candidate counts and clamp skipped-row accounting during serialization.
# Attributes:
# - hospital_name (str): Hospital name retained in the normalized prescription.
# - prescription_date (str): Prescription dispensing date, if available.
@dataclass
class PrescriptionAnalysisResult:
    hospital_name: str
    prescription_date: str
    medication_candidates: MedicationCandidateList = field(
        default_factory=MedicationCandidateList
    )

    # Function Name: hospitalName
    # Description:
    # - Reads the stored hospital name retained in the normalized prescription.
    # Parameters:
    # - None.
    # Returns:
    # - Hospital name retained in the normalized prescription.
    @property
    def hospitalName(self) -> str:
        return self.hospital_name

    # Function Name: prescriptionDate
    # Description:
    # - Reads the stored prescription dispensing date, if available.
    # Parameters:
    # - None.
    # Returns:
    # - Prescription dispensing date, if available.
    @property
    def prescriptionDate(self) -> str:
        return self.prescription_date

    # Function Name: candidateCount
    # Description:
    # - Counts candidates retained in the normalized prescription result.
    # Parameters:
    # - None.
    # Returns:
    # - Current number of medication candidates.
    @property
    def candidateCount(self) -> int:
        return len(self.medication_candidates.candidates)

    # Function Name: addMedicationCandidate
    # Description:
    # - Adds one medication candidate to this analysis result.
    # Parameters:
    # - candidate (MedicationCandidate): Normalized drug name and prescription dose-course fields.
    # Returns:
    # - None.
    def addMedicationCandidate(self, candidate: MedicationCandidate) -> None:
        self.medication_candidates.addCandidate(candidate)

    # Function Name: to_payload
    # Description:
    # - Serializes prescription metadata and candidates and clamps the skipped-row count to zero.
    # Parameters:
    # - raw_medication_count (int): Number of source medication rows before normalization and deduplication.
    # Returns:
    # - Prescription payload with raw, parsed and skipped medication counts.
    def to_payload(self, raw_medication_count: int) -> dict[str, object]:
        skipped_medication_count = max(
            0,
            raw_medication_count - self.candidateCount,
        )
        return {
            "hospital_name": self.hospital_name,
            "prescription_date": self.prescription_date,
            "medications": self.medication_candidates.to_payload(),
            "raw_medication_count": raw_medication_count,
            "parsed_medication_count": self.candidateCount,
            "skipped_medication_count": skipped_medication_count,
        }
