"""외부 처방전 분석 전 개인정보 구역과 직접 식별자를 검사한다."""

import re
import unicodedata


# 기기의 PrescriptionPrivacyFilter와 같은 라벨·약 행 기준을 사용한다.
_PRIVATE_LABEL = re.compile(
    r"환\s*자\s*(?:명|성\s*명|이\s*름|번\s*호|정보)|수진자(?:\s*(?:명|성명))?|"
    r"(?<![가-힣])성\s*명|주\s*민\s*(?:등\s*록)?\s*번\s*호|외국인\s*등록\s*번호|"
    r"생\s*년\s*월\s*일|생일|주\s*소|전화\s*번호|연락처|휴대폰|보험\s*번호|"
    r"차트\s*번호|의무\s*기록\s*번호|"
    r"\b(?:patient(?:\s*(?:name|id|number|information))?|(?<!drug )(?<!medication )name|dob|"
    r"date\s+of\s+birth|birth\s*date|address|phone|telephone|mobile|email|"
    r"resident\s*(?:id|number)|chart\s*(?:id|number))\b",
    re.IGNORECASE,
)
_MEDICATION_ROW = re.compile(
    r"\d\s*(?:mg|mcg|μg|µg|ml|g|iu)(?![a-z])|"
    r"\d\s*(?:밀리그램|정|캡슐|캅셀|포|회|일분)(?:씩|(?![가-힣]))|"
    r"(?:캡슐|캅셀|시럽|현탁액|점안액|연고|서방정|장용정)(?![가-힣])",
    re.IGNORECASE,
)
_MEDICATION_HEADER = re.compile(
    r"^(?:약품\s*명|의약품\s*명|약\s*이름|투약\s*내역|처방\s*내역|"
    r"medications?|drug\s*name)(?:\s|[:：|/]|$)", re.IGNORECASE,
)
_PRESCRIPTION_DATE = re.compile(
    r"(?:조제|처방)\s*일(?:자)?|\b(?:prescription|dispens(?:ing|ed))\s*date\b",
    re.IGNORECASE,
)
_DATE = re.compile(
    r"(?<!\d)(?:19|20)\d{2}\s*[.\-/년]\s*\d{1,2}\s*[.\-/월]\s*\d{1,2}\s*일?(?!\d)"
)
_RRN = re.compile(r"(?<!\d)\d{6}\s*[-–—~ ]?\s*[\d*]{7}(?![\d*])")
_PHONE = re.compile(
    r"(?<!\d)(?:\+82\s*[-. ]?\s*(?:\(0\)\s*)?(?:10|2|[3-6][1-5])|"
    r"01[016789]|0[2-6][1-5]?)\s*[-.) ]?\s*\d{3,4}\s*[-. ]?\s*\d{4}(?!\d)"
)
_EMAIL = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)
_AGE_GENDER = re.compile(
    r"(?<!\d)(?:만\s*)?\d{1,3}\s*세\s*[/·,\s(-]?\s*(?:남|여)(?:성)?(?![가-힣])|"
    r"(?<![가-힣])(?:남|여)(?:성)?\s*[/·,\s(-]?\s*(?:만\s*)?\d{1,3}\s*세"
)
_NAME_WITH_HONORIFIC = re.compile(r"(?<![가-힣])[가-힣]{2,5}\s*(?:님|귀하)(?![가-힣])")
_ADDRESS = re.compile(
    r"[가-힣]{2,}(?:대로|로|길)\s*\d+(?:번길)?|"
    r"[가-힣]{2,}(?:동|읍|면|리)\s*\d+(?:-\d+)?|\d+\s*동\s*\d+\s*호|"
    r"[가-힣]+(?:시|도)\s+[가-힣]+(?:시|군|구)\b"
)
_REJECT_MESSAGE = (
    "처방전 텍스트에 개인정보가 남아 있거나 약 정보와 구분하기 어렵습니다. "
    "환자 정보가 없는 약 목록과 조제일자만 다시 선택해주세요."
)


class PrescriptionPrivacyError(ValueError):
    """개인정보를 안전하게 분리할 수 없어 외부 전송을 중단한다."""


def deidentify_prescription_text(text: str) -> str:
    """식별자 라벨 구역을 제외하고 안전하게 분리된 처방 정보만 반환한다."""
    normalized = unicodedata.normalize("NFKC", text).replace("\r\n", "\n").replace("\r", "\n")
    # OCR의 보이지 않는 구분자로 식별자 검사가 우회되지 않게 한다.
    normalized = "".join(char for char in normalized if unicodedata.category(char) != "Cf")
    if any(unicodedata.category(char) == "Cc" and char not in "\n\t" for char in normalized):
        raise PrescriptionPrivacyError(_REJECT_MESSAGE)
    if len(normalized) > 20_000:
        raise PrescriptionPrivacyError(_REJECT_MESSAGE)

    result: list[str] = []
    private_section = False
    date_value_expected = False
    for source_line in normalized.splitlines():
        line = re.sub(r"[ \t]+", " ", source_line).strip()
        if not line:
            continue
        # 기기에서 이미 가린 정확한 대체 문구는 개인정보 라벨로 다시 해석하지 않는다.
        for placeholder in ("[주민번호 제거]", "[연락처 제거]", "[이메일 제거]"):
            line = line.replace(placeholder, "[REDACTED]")
        medication_row = bool(_MEDICATION_ROW.search(line))
        if _PRIVATE_LABEL.search(line):
            # 같은 줄의 일부를 지워 약명·용량까지 잘못 바꾸는 대신 재선택을 요구한다.
            if medication_row or _PRESCRIPTION_DATE.search(line):
                raise PrescriptionPrivacyError(_REJECT_MESSAGE)
            private_section = True
            date_value_expected = False
            continue

        prescription_date = bool(_PRESCRIPTION_DATE.search(line))
        date_value = date_value_expected and bool(_DATE.fullmatch(line))
        if private_section and not (medication_row or _MEDICATION_HEADER.search(line)):
            # 이름·주소가 여러 줄이어도 약 목록 경계가 확인되기 전에는 내보내지 않는다.
            if not (prescription_date or date_value):
                continue
        elif private_section:
            # 이름만 적힌 약 행을 환자 값으로 제외했을 수 있어 용량만 남긴 채 보내지 않는다.
            if medication_row and re.match(r"^\d", line):
                raise PrescriptionPrivacyError(_REJECT_MESSAGE)
            private_section = False

        if _ADDRESS.search(line) or _NAME_WITH_HONORIFIC.search(line) or _AGE_GENDER.search(line):
            raise PrescriptionPrivacyError(_REJECT_MESSAGE)
        # 주민번호 앞 여섯 자리도 생년월일이므로 부분 마스킹을 사용하지 않는다.
        for pattern in (_RRN, _PHONE, _EMAIL):
            line = pattern.sub("[REDACTED]", line)
        if _DATE.search(line) and not (prescription_date or date_value):
            raise PrescriptionPrivacyError(_REJECT_MESSAGE)
        date_value_expected = prescription_date and not bool(_DATE.search(line))
        result.append(line)

    safe_text = "\n".join(result).strip()
    if not safe_text or not safe_text.replace("[REDACTED]", "").strip():
        raise PrescriptionPrivacyError(_REJECT_MESSAGE)
    # 변경 후에도 고위험 표기가 남으면 제공자 호출 전에 차단한다.
    if any(pattern.search(safe_text) for pattern in (_RRN, _PHONE, _EMAIL, _PRIVATE_LABEL)):
        raise PrescriptionPrivacyError(_REJECT_MESSAGE)
    return safe_text
