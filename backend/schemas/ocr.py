from pydantic import BaseModel, Field
from typing import List

class MedicationItem(BaseModel):
    """개별 약품에 대한 정보"""
    drug_name: str = Field(description="약품의 이름")
    dosage_per_time: str = Field(description="1회 투약량 (예: 1정, 1포)")
    daily_frequency: str = Field(description="1일 투여 횟수 (예: 3회)")
    total_days: str = Field(description="총 투약 일수 (예: 7일)")

class PrescriptionData(BaseModel):
    """약봉투에서 추출할 최종 데이터 구조"""
    # 값이 없을 때의 행동 지침 추가
    hospital_name: str = Field(description="병원 또는 약국 이름 (사진에 없으면 '알 수 없음' 입력)")
    prescription_date: str = Field(description="조제 일자 YYYY-MM-DD 형식 (사진에 없으면 '알 수 없음' 입력)")
    medications: List[MedicationItem] = Field(description="처방받은 약품 목록")