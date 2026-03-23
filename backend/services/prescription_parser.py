import re
from typing import List, Dict, Any, Optional


# 변수이름: DATE_PATTERN
# 변수역할:
# - 날짜 문자열을 찾기 위한 정규표현식 패턴
# - 예:
#   2026-03-21
#   2026.03.21
#   2026/3/21
DATE_PATTERN = re.compile(r"(\d{4})[./-](\d{1,2})[./-](\d{1,2})")


# 변수이름: MED_LINE_PATTERN
# 변수역할:
# - 약품 정보 한 줄을 파싱하기 위한 정규표현식 패턴
# - 형식:
#   [약이름] [1회투약량] [1일복용횟수] [총복용일수]
# - 예:
#   타이레놀정500mg 1 3 5
#   코푸정 0.5 2 7
MED_LINE_PATTERN = re.compile(
    r"(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s+(\d+)$"
)


# 함수이름: normalize_text
# 함수역할:
# - OCR 결과 한 줄에서 불필요한 공백/콜론 등을 정리한다.
# - 파싱하기 쉬운 형태로 문자열을 정규화한다.
# 매개변수:
# - text: OCR 결과 한 줄 문자열
# 반환값:
# - 정리된 문자열
def normalize_text(text: str) -> str:
    text = text.strip()
    text = text.replace(":", " ")
    text = " ".join(text.split())
    return text


# 함수이름: normalize_date
# 함수역할:
# - 문자열 안에서 날짜를 찾아 YYYY-MM-DD 형식으로 통일한다.
# 매개변수:
# - text: 날짜가 포함될 수 있는 문자열
# 반환값:
# - 날짜를 찾으면 YYYY-MM-DD 문자열
# - 찾지 못하면 None
def normalize_date(text: str) -> Optional[str]:
    match = DATE_PATTERN.search(text)
    if not match:
        return None

    # 변수이름: year, month, day
    # 변수역할:
    # - 정규표현식으로 추출한 연/월/일 값
    year, month, day = match.groups()

    return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"


# 함수이름: extract_patient_name
# 함수역할:
# - "환자명 홍길동", "환자명: 홍길동" 같은 줄에서 환자 이름을 추출한다.
# 매개변수:
# - line: OCR 결과 한 줄
# 반환값:
# - 환자명을 찾으면 문자열
# - 찾지 못하면 None
def extract_patient_name(line: str) -> Optional[str]:
    if "환자명" not in line:
        return None

    # 변수이름: cleaned
    # 변수역할:
    # - "환자명" 제거 후 실제 이름 부분만 남긴 문자열
    cleaned = line.replace("환자명", "").strip()
    cleaned = cleaned.strip(":").strip()

    return cleaned if cleaned else None


# 함수이름: extract_prescription_date
# 함수역할:
# - "처방일자 2026-03-21", "처방일 2026.03.21" 같은 줄에서 날짜를 추출한다.
# 매개변수:
# - line: OCR 결과 한 줄
# 반환값:
# - 날짜를 찾으면 YYYY-MM-DD 문자열
# - 찾지 못하면 None
def extract_prescription_date(line: str) -> Optional[str]:
    if "처방일" not in line and "처방일자" not in line:
        return None

    return normalize_date(line)


# 함수이름: parse_medication_line
# 함수역할:
# - 약품 정보 한 줄을 dict 형태로 파싱한다.
# - 예:
#   "타이레놀정500mg 1 3 5"
#   ->
#   {
#       "name": "타이레놀정500mg",
#       "dose_per_time": 1,
#       "frequency_per_day": 3,
#       "duration_days": 5
#   }
# 매개변수:
# - line: OCR 결과 한 줄
# 반환값:
# - 파싱 성공 시 약품 정보 dict
# - 실패 시 None
def parse_medication_line(line: str) -> Optional[Dict[str, Any]]:
    # 변수이름: parts
    # 변수역할:
    # - 문자열을 뒤에서부터 3개 기준으로 나눈 리스트
    # - [약이름, dose, freq, days]
    parts = line.rsplit(maxsplit=3)

    if len(parts) != 4:
        return None

    # 변수이름: name, dose_raw, freq_raw, days_raw
    # 변수역할:
    # - 각각 약 이름, 1회 투약량, 1일 복용 횟수, 총 복용 일수
    name, dose_raw, freq_raw, days_raw = parts

    try:
        # 변수이름: dose
        # 변수역할:
        # - 숫자형으로 변환된 1회 투약량
        dose = float(dose_raw)
        if dose.is_integer():
            dose = int(dose)

        # 변수이름: frequency_per_day
        # 변수역할:
        # - 하루 복용 횟수
        frequency_per_day = int(freq_raw)

        # 변수이름: duration_days
        # 변수역할:
        # - 총 복용 일수
        duration_days = int(days_raw)

    except ValueError:
        return None

    return {
        "name": name.strip(),
        "dose_per_time": dose,
        "frequency_per_day": frequency_per_day,
        "duration_days": duration_days,
    }


# 함수이름: parse_prescription
# 함수역할:
# - OCR 줄 리스트를 받아 처방전 정보를 구조화된 dict(JSON 형태)로 변환한다.
# 매개변수:
# - lines: OCR 결과를 줄 단위로 나눈 문자열 리스트
# 반환값:
# - 처방전 정보를 담은 dict
def parse_prescription(lines: List[str]) -> Dict[str, Any]:
    # 변수이름: result
    # 변수역할:
    # - 최종적으로 반환할 구조화 결과 저장
    result = {
        "patient_name": None,
        "prescription_date": None,
        "medicines": [],
    }

    for raw_line in lines:
        # 변수이름: line
        # 변수역할:
        # - 정리된 OCR 한 줄 텍스트
        line = normalize_text(raw_line)

        if not line:
            continue

        # 변수이름: patient_name
        # 변수역할:
        # - 환자명 추출 결과
        patient_name = extract_patient_name(line)
        if patient_name:
            result["patient_name"] = patient_name
            continue

        # 변수이름: prescription_date
        # 변수역할:
        # - 처방일자 추출 결과
        prescription_date = extract_prescription_date(line)
        if prescription_date:
            result["prescription_date"] = prescription_date
            continue

        # 변수이름: medicine
        # 변수역할:
        # - 약품 한 줄 파싱 결과
        medicine = parse_medication_line(line)
        if medicine:
            result["medicines"].append(medicine)

    return result
