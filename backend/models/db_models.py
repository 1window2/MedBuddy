from sqlalchemy import Column, Integer, String
from core.database import Base 

class SavedMedication(Base):
    __tablename__ = "saved_medications"

    id = Column(Integer, primary_key=True, index=True)
    item_name = Column(String, index=True)      # 약 이름
    efficacy = Column(String)                   # 식약처 효능
    use_method = Column(String)                 # 사용법
    warning_message = Column(String)            # 주의사항
    ai_guide = Column(String, nullable=True)    # AI 요약