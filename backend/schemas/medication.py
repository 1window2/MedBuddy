# 파일명: medication.py
# 역할: 약품 관련 요청/응답 DTO를 정의한다.

from datetime import date
from typing import Optional

from pydantic import BaseModel, Field

from entities.medication_detail_entity import MedicationDetail
from entities.patient_hash_entity import DEFAULT_PATIENT_HASH


# 클래스명: MedicationRequest
# 역할: 약품 상세 조회 요청 DTO이다.
# 속성:
#   - extracted_text: 프론트엔드 또는 분석 흐름에서 추출한 원본 약품 텍스트
class MedicationRequest(BaseModel):
    extracted_text: Optional[str] = None


# 클래스명: SavedMedicationCreate
# 역할: 복약 정보 저장 요청 DTO이다.
# 속성:
#   - patient_hash: 저장 복약 정보의 소유 범위를 구분하는 환자 해시
#   - item_name: 약품명
#   - efficacy: 약품 효능 요약
#   - use_method: 약품 복용 방법 요약
#   - warning_message: 약품 주의사항 요약
#   - dosage_per_time: 처방전 분석에서 추출한 선택적 1회 투약량
#   - daily_frequency: 처방전 분석에서 추출한 선택적 1일 복용 횟수
#   - total_days: 처방전 분석에서 추출한 선택적 총 복용 일수
#   - image_url: 공공데이터에서 제공하는 선택적 약품 이미지 URL
#   - ai_guide: 선택적으로 생성되는 환자 안내 문구
class SavedMedicationCreate(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH
    prescription_date: Optional[date] = None
    item_name: str
    efficacy: str
    use_method: str
    warning_message: str
    dosage_per_time: Optional[str] = None
    daily_frequency: Optional[str] = None
    total_days: Optional[str] = None
    image_url: Optional[str] = None
    ai_guide: Optional[str] = None


# 클래스명: MedicationStatusUpdate
# 역할: 오늘 복약 완료 상태 변경 요청 DTO이다.
# 속성:
#   - medication_status: Whether the medication is completed.
class MedicationStatusUpdate(BaseModel):
    medication_status: bool


# 클래스명: PatientCodeCreate
# 역할: 임시 환자 연동 코드 생성 요청 DTO이다.
# 속성:
#   - patient_hash: 생성된 연동 코드에 담길 환자 해시
class PatientCodeCreate(BaseModel):
    patient_hash: str = DEFAULT_PATIENT_HASH


# 클래스명: PatientCodeRegister
# 역할: 환자 코드를 통한 보호자 등록 요청 DTO이다.
# 속성:
#   - caregiver_hash: 보호자 소유권을 구분하는 해시
#   - patient_code: 환자가 생성한 임시 연동 코드
class PatientCodeRegister(BaseModel):
    caregiver_hash: str = DEFAULT_PATIENT_HASH
    patient_code: str


# 클래스명: MedicationResponse
# 역할: 약품 상세 조회 결과 응답 DTO이다.
# 속성:
#   - success: 조회 결과 존재 여부
#   - message: User-facing result message.
#   - data: MedicationDetail result list.
class MedicationResponse(BaseModel):
    success: bool
    message: str
    data: list[MedicationDetail] = Field(default_factory=list)
