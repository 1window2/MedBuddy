# File Name: catalog_refresh_state_entity.py
# Role: Persist when the periodic catalogue refresh last started and last completed.

from sqlalchemy import Column, DateTime, String

from core.database import Base


# Name of the single schedule row written by the self-hosted refresh loop.
CATALOG_REFRESH_SCHEDULE_NAME = "weekly"


# Class Name: CatalogRefreshState
# Role: Durable schedule state of the periodic drug and pharmacy catalogue refresh.
# Responsibilities: Let the refresh loop resume its schedule after a container restart instead of
#   waiting a full interval again, and space out attempts after a failure.
# Attributes: name - schedule key; last_attempt_at - start of the latest refresh (UTC, naive);
#   last_success_at - completion of the latest refresh in which every catalogue was synchronized.
class CatalogRefreshState(Base):
    __tablename__ = "catalog_refresh_state"
    name = Column(String(64), primary_key=True)
    last_attempt_at = Column(DateTime, nullable=True)
    last_success_at = Column(DateTime, nullable=True)
