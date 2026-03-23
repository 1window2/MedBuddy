import re
from typing import List, Dict, Any, Optional


# 정규식: 날짜 추출용
# 역할:
# - 2026-03-21
# - 2026.03.21
# - 2026/3/21
# 같은 날짜 형식을 찾기 위한 패턴
DATE_PATTERN = re.compile(r"(\d{4})[./-](\d{1,2})[./-](\d{1,2})")


# 정규식: 약품 한 줄 파싱용
# 역할:
# - "타이레놀정500mg 1 3 5"
# - "코푸정 0.5 2 7"
# 같은 형식에서
#   [약이름] [1회투약량] [1일복용횟수] [총복용일수]
# 를 분리하기 위한 패턴
MED_LINE_PATTERN = re.compile(
    r"(.+?)\s+(\d+(?:\.\d+)?)\s+(\d+)\s+(\d+)$"
)


# 함수명: normalize_text
# 함수역할:
# - OCR 결과에서 불필요한 공백, 콜론(:) 등을 정리해서
#   파싱하기 쉬운 형태로 통일한다.
# 매개변수:
# - text: OCR로 인식된 원본 한 줄 문자열
# 반환값:
# - 정리된 문자열
def normalize_text(text: str) -> str:
    text = text.strip()
    text = text.replace(":", " ")
    text = " ".join(text.split())
    return text


# 함수명: normalize_date
# 함수역할:
# - 문자열 안에서 날짜를 찾아 YYYY-MM-DD 형식으로 통일한다.
# 매개변수:
# - text: 날짜가 포함될 수 있는 문자열
# 반환값:
# - 날짜를 찾으면 "YYYY-MM-DD" 문자열 반환
# - 못 찾으면 None 반환
def normalize_date(text: str) -> Optional[str]:
    match = DATE_PATTERN.search(text)
    if not match:
        return None

    year, month, day = match.groups()
    return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"


# 함수명: extract_patient_name
# 함수역할:
# - "환자명 홍길동", "환자명: 홍길동" 같은 줄에서
#   환자 이름만 추출한다.
# 매개변수:
# - line: OCR 결과 한 줄
# 반환값:
# - 환자명을 찾으면 문자열 반환
# - 못 찾으면 None 반환
def extract_patient_name(line: str) -> Optional[str]:
    if "환자명" not in line:
        return None

    cleaned = line.replace("환자명", "").strip()
    cleaned = cleaned.strip(":").strip()
    return cleaned if cleaned else None


# 함수명: extract_prescription_date
# 함수역할:
# - "처방일자 2026-03-21", "처방일 2026.03.21" 같은 줄에서
#   처방 날짜를 추출한다.
# 매개변수:
# - line: OCR 결과 한 줄
# 반환값:
# - 날짜를 찾으면 "YYYY-MM-DD" 문자열 반환
# - 못 찾으면 None 반환
def extract_prescription_date(line: str) -> Optional[str]:
    if "처방일" not in line and "처방일자" not in line:
        return None

    return normalize_date(line)


# 함수명: parse_medication_line
# 함수역할:
# - 약품 정보 한 줄을 파싱해서 dict 형태로 반환한다.
# 예:
# - "타이레놀정500mg 1 3 5"
#   → {
#       "name": "타이레놀정500mg",
#       "dose_per_time": 1,
#       "frequency_per_day": 3,
#       "duration_days": 5
#     }
# 매개변수:
# - line: OCR 결과 한 줄
# 반환값:
# - 파싱 성공 시 약품 정보 dict 반환
# - 실패 시 None 반환
def parse_medication_line(line: str) -> Optional[Dict[str, Any]]:
    match = MED_LINE_PATTERN.match(line)
    if not match:
        return None

    # 변수명: name
    # 변수역할:
    # - 약 이름 저장
    name = match.group(1).strip()

    # 변수명: dose_raw
    # 변수역할:
    # - 1회 투약량 원본 문자열 저장
    dose_raw = match.group(2)

    # 변수명: freq_raw
    # 변수역할:
    # - 1일 복용 횟수 원본 문자열 저장
    freq_raw = match.group(3)

    # 변수명: days_raw
    # 변수역할:
    # - 총 복용 일수 원본 문자열 저장
    days_raw = match.group(4)

    # 변수명: dose
    # 변수역할:
    # - 1회 투약량을 숫자형으로 변환
    dose = float(dose_raw)
    if dose.is_integer():
        dose = int(dose)

    return {
        "name": name,
        "dose_per_time": dose,
        "frequency_per_day": int(freq_raw),
        "duration_days": int(days_raw),
    }


# 함수명: parse_prescription
# 함수역할:
# - OCR 줄 리스트를 받아서
#   환자명 / 처방일자 / 약 목록을 구조화된 JSON(dict) 형태로 만든다.
# 매개변수:
# - lines: OCR 결과를 줄 단위로 나눈 문자열 리스트
# 반환값:
# - 구조화된 처방전 정보 dict
def parse_prescription(lines: List[str]) -> Dict[str, Any]:
    # 변수명: result
    # 변수역할:
    # - 최종적으로 반환할 구조화 결과 저장
    result = {
        "patient_name": None,
        "prescription_date": None,
        "medicines": [],
    }

    for raw_line in lines:
        # 변수명: line
        # 변수역할:
        # - 한 줄 OCR 텍스트를 정규화한 결과 저장
        line = normalize_text(raw_line)

        if not line:
            continue

        # 1. 환자명 추출
        patient_name = extract_patient_name(line)
        if patient_name:
            result["patient_name"] = patient_name
            continue

        # 2. 처방일자 추출
        prescription_date = extract_prescription_date(line)
        if prescription_date:
            result["prescription_date"] = prescription_date
            continue

        # 3. 약품 행 추출
        medicine = parse_medication_line(line)
        if medicine:
            result["medicines"].append(medicine)

    return result