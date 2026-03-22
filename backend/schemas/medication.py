#데이터 입출력 모델 (Pydantic)

from pydantic import BaseModel
from typing import Optional, List

# 클라이언트에서 백엔드로 보내는 요청
class MedicationRequest(BaseModel):
    extracted_text: Optional[str] = None  # 앱의 ML Kit가 추출한 텍스트

# API가 반환할 개별 약 정보 구조
class DrugInfo(BaseModel):
    item_name: str         # 제품명
    efficacy: str          # 효능
    use_method: str        # 사용법
    warning_message: str   # 주의사항
    ai_guide: Optional[str] = None  # AI가 생성한 복용안내

# 앱에서 '내 약통에 담기'를 눌렀을 때 백엔드로 보낼 데이터 구조
class SavedMedicationCreate(BaseModel):
    item_name: str
    efficacy: str
    use_method: str
    warning_message: str
    ai_guide: Optional[str] = None

# 최종 응답 모델
class MedicationResponse(BaseModel):
    success: bool
    message: str
    data: List[DrugInfo] = []
