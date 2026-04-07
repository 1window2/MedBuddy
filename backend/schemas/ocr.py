from pydantic import BaseModel, Field
from typing import List, Optional

class MedicationItem(BaseModel):
    """개별 약품 정보"""
    drug_name: str = Field(..., description="약품의 이름")
    dosage_per_time: str = Field(..., description="1회 투약량 (예: 1정, 1포)")
    daily_frequency: str = Field(..., description="1일 투여 횟수 (예: 3회)")
    total_days: str = Field(..., description="총 투약 일수 (예: 7일)")

class PrescriptionData(BaseModel):
    """약봉투에서 추출할 최종 데이터 구조"""
    hospital_name: Optional[str] = Field(None, description="병원 또는 약국 이름")
    prescription_date: Optional[str] = Field(None, description="조제 일자 (YYYY-MM-DD 형식)")
    medications: List[MedicationItem] = Field(..., description="처방받은 약품 목록")