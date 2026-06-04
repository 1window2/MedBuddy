# File Name: saved_medication_entity.py
# Role: SQLAlchemy entity for saved medication snapshots.

from sqlalchemy import Column, Integer, String

from core.database import Base


# Class Name: _SavedMedication
# Role: Internal SQLAlchemy row for saved medication detail snapshots.
# Responsibilities:
#   - Map saved medication fields to the saved_medications table.
class _SavedMedication(Base):
    __tablename__ = "saved_medications"

    id = Column(Integer, primary_key=True, index=True)
    item_name = Column(String, index=True)
    efficacy = Column(String)
    use_method = Column(String)
    warning_message = Column(String)
    ai_guide = Column(String, nullable=True)
