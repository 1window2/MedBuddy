#OCR 처리 로직

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