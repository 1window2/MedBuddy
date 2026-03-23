#OCR 처리 로직
from typing import List, Dict, Any
from services.prescription_parser import parse_prescription

class OCRService:
    def __init__(self):
        # 나중에 Tesseract나 Cloud Vision 모델을 초기화하는 코드가 들어갈 수 있어.
        pass

    def process_text(self, raw_text: str) -> str:
        """
        클라이언트에서 ML Kit로 추출해 보낸 텍스트의 노이즈를 제거하고
        실제 약 이름 후보군만 정제하는 로직이 들어가는 곳이야.
        """
        # 예: "처방전... 타이레놀정 500mg ... 식후 30분" -> "타이레놀" 추출
        refined_keyword = raw_text.replace("\n", " ").strip()
        return refined_keyword

    # 함수명: split_lines
    # 함수역할:
    # - OCR 전체 문자열을 줄 단위 리스트로 분리
    # 변수명: raw_text
    # 변수역할:
    # - 프론트에서 보낸 OCR 전체 문자열
    def split_lines(self, raw_text: str) -> List[str]:
        if not raw_text:
            return []

        # 변수명: lines
        # 변수역할:
        # - 공백 제거 후 남긴 줄 리스트
        lines = [line.strip() for line in raw_text.splitlines()]
        lines = [line for line in lines if line]
        return lines

    # 함수명: parse_prescription_text
    # 함수역할:
    # - OCR 전체 문자열을 줄 단위로 나눈 뒤 prescription_parser로 넘겨
    #   구조화된 JSON(dict) 형태로 반환
    # 변수명: raw_text
    # 변수역할:
    # - 프론트에서 보낸 OCR 전체 문자열
    def parse_prescription_text(self, raw_text: str) -> Dict[str, Any]:
        # 변수명: lines
        # 변수역할:
        # - 줄 단위로 분리된 OCR 텍스트
        lines = self.split_lines(raw_text)

        # 변수명: parsed_result
        # 변수역할:
        # - 파서가 만든 최종 구조화 결과
        parsed_result = parse_prescription(lines)
        return parsed_result
