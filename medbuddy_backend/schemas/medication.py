#데이터 입출력 모델 (Pydantic)

from pydantic import BaseModel
from typing import Optional, List

# 클라이언트(앱)에서 백엔드로 보내는 요청
class MedicationRequest(BaseModel):
    extracted_text: Optional[str] = None  # 앱의 ML Kit가 추출한 텍스트
    # image_file: bytes = None # 만약 백엔드에서 직접 OCR을 한다면 이런 필드가 추가될 수 있음

# API가 반환할 개별 약 정보 구조
class DrugInfo(BaseModel):
    item_name: str         # 제품명
    efficacy: str          # 효능
    use_method: str        # 사용법
    warning_message: str   # 주의사항

# 최종 응답 모델
class MedicationResponse(BaseModel):
    success: bool
    message: str
    data: List[DrugInfo] = []