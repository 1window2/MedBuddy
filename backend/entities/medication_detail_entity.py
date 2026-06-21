# 파일명: medication_detail_entity.py
# 역할: Entity/DTO definitions for medication detail information.

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import Column, DateTime, Integer, String, Text, func

from core.database import Base


# 클래스명: MedicationDetail
# 역할: medication detail information shown to the user을 표현한다.
# 주요 책임:
#   - Carry efficacy, usage, warning, source, and optional guide text.
# 속성:
#   - item_name: Public medication item name.
#   - efficacy: 약품 효능 요약
#   - usage_method: 약품 복용 방법 요약
#   - warning: 약품 주의사항 요약
#   - dosage_per_time: 처방전 분석에서 추출한 선택적 1회 투약량
#   - daily_frequency: 처방전 분석에서 추출한 선택적 1일 복용 횟수
#   - total_days: 처방전 분석에서 추출한 선택적 총 복용 일수
#   - image_url: 공공데이터에서 제공하는 선택적 약품 이미지 URL
#   - source: Data source label.
#   - ai_guide: 선택적으로 생성되는 환자 안내 문구
class MedicationDetail(BaseModel):
    model_config = ConfigDict(populate_by_name=True, serialize_by_alias=True)

    item_name: str
    efficacy: str
    usage_method: str = Field(alias="use_method")
    warning: str = Field(alias="warning_message")
    precaution: str = ""
    interaction: str = ""
    side_effect: str = ""
    storage_method: str = ""
    dosage_per_time: str = ""
    daily_frequency: str = ""
    total_days: str = ""
    image_url: str = ""
    source: str = "e약은요"
    ai_guide: Optional[str] = None

    # 함수명: saveMedicationDetail
    # 함수역할:
    # - 클래스 다이어그램 연산을 위한 placeholder이다. 현재 저장은
    #   쓰기 책임을 control 클래스에 두기 위해 CheckSavedMedication이 조정한다.
    # 반환값:
    # - None.
    def saveMedicationDetail(self) -> None:
        raise NotImplementedError(
            "Medication detail saving is handled by CheckSavedMedication."
        )

    # 함수명: checkMedicationDetail
    # 함수역할:
    # - 클래스 다이어그램 연산을 위한 placeholder이다. 현재 상세 조회는
    #   coordinated by CheckMedicationDetail.
    # 반환값:
    # - 현재 MedicationDetail 인스턴스
    def checkMedicationDetail(self) -> "MedicationDetail":
        return self

    # 함수명: get_medication_detail
    # 함수역할:
    # - control 코드에서 이어서 사용할 수 있도록 현재 MedicationDetail 인스턴스를 반환한다
    #   the class diagram operation name.
    # 반환값:
    # - 현재 MedicationDetail 인스턴스
    def get_medication_detail(self) -> "MedicationDetail":
        return self

    # 함수명: getMedicationDetail
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 get_medication_detail wrapper이다.
    # 반환값:
    # - 현재 MedicationDetail 인스턴스
    def getMedicationDetail(self) -> "MedicationDetail":
        return self.get_medication_detail()

    # 함수명: get_voice_guide_text
    # 함수역할:
    # - 음성 안내 기능 구현 시 TTS boundary로 넘길 수 있는 문장을 만든다.
    # 반환값:
    # - Voice guide source text.
    def get_voice_guide_text(self) -> str:
        return "\n".join(
            item
            for item in [
                self.item_name,
                self.efficacy,
                self.usage_method,
                self.dosage_per_time,
                self.daily_frequency,
                self.total_days,
                self.warning,
                self.ai_guide or "",
            ]
            if item.strip()
        )

    # 함수명: getVoiceGuideText
    # 함수역할:
    # - 클래스 다이어그램과의 호환을 위한 get_voice_guide_text wrapper이다.
    # 반환값:
    # - Voice guide source text.
    def getVoiceGuideText(self) -> str:
        return self.get_voice_guide_text()


# 클래스명: _DrugBasicInfo
# 역할: 로컬에 동기화한 e약은요 데이터를 저장하는 내부 SQLAlchemy 엔티티이다.
# 주요 책임:
#   - Store public medication records fetched from the e약은요 API.
#   - Preserve the raw API payload for traceability and refresh validation.
# 속성:
#   - item_seq: Public API item sequence identifier.
#   - item_name: Original medication item name.
#   - normalized_item_name: Search-normalized medication name.
#   - raw_json: Original public API payload.
class _DrugBasicInfo(Base):
    __tablename__ = "drug_basic_infos"

    id = Column(Integer, primary_key=True, index=True)
    item_seq = Column(String, unique=True, index=True, nullable=True)
    item_name = Column(String, index=True, nullable=False)
    normalized_item_name = Column(String, index=True, nullable=False)
    entp_name = Column(String, nullable=True)
    efficacy = Column(Text, nullable=True)
    use_method = Column(Text, nullable=True)
    warning_message = Column(Text, nullable=True)
    interaction = Column(Text, nullable=True)
    side_effect = Column(Text, nullable=True)
    deposit_method = Column(Text, nullable=True)
    ai_guide = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


# 클래스명: _DrugApprovalInfo
# 역할: 로컬에 동기화한 의약품 허가 상세 데이터를 저장하는 내부 SQLAlchemy 엔티티이다.
# 주요 책임:
#   - Store raw approval documents fetched from the public approval API.
#   - 첫 사용 시 생성한 환자용 요약문을 저장한다.
# 속성:
#   - item_seq: Public item identifier or product standard code.
#   - item_name: Original medication item name.
#   - normalized_item_name: Search-normalized medication name.
#   - efficacy_doc: 허가 정보의 원본 효능 문서
#   - use_method_doc: 허가 정보의 원본 용법 문서
#   - warning_doc: 허가 정보의 원본 주의사항 문서
class _DrugApprovalInfo(Base):
    __tablename__ = "drug_approval_infos"

    id = Column(Integer, primary_key=True, index=True)
    item_seq = Column(String, unique=True, index=True, nullable=True)
    item_name = Column(String, index=True, nullable=False)
    normalized_item_name = Column(String, index=True, nullable=False)
    entp_name = Column(String, nullable=True)
    main_ingredient = Column(Text, nullable=True)
    efficacy_doc = Column(Text, nullable=True)
    use_method_doc = Column(Text, nullable=True)
    warning_doc = Column(Text, nullable=True)
    summary_efficacy = Column(Text, nullable=True)
    summary_use_method = Column(Text, nullable=True)
    summary_warning_message = Column(Text, nullable=True)
    ai_guide = Column(Text, nullable=True)
    raw_json = Column(Text, nullable=False)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
