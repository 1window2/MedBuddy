# File Name: korean_holiday_cache.py
# Role: Gives each blocking calendar-cache operation its own database session.

from collections.abc import Callable
from datetime import date, timedelta

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from boundaries.pharmacy_api_boundary import PharmacyApiUnavailableError
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository


# Class Name: SessionScopedKoreanHolidayCache
# Role: Thread-safe calendar adapter with operation-scoped sessions.
# Responsibilities: Never retain a request session or transaction across an await.
class SessionScopedKoreanHolidayCache:
    # Function Name: __init__
    # Description: Stores a factory, not a live ORM session.
    # Parameters: session_factory: Creates a session for one worker operation.
    # Returns: None.
    def __init__(self, session_factory: Callable[[], Session]) -> None:
        self._session_factory = session_factory

    # Function Name: get_cached_korean_holidays
    # Description: Reads a verified snapshot and releases its transaction before returning.
    # Parameters: year, month: Calendar month; max_age: Accepted snapshot age.
    # Returns: Cached immutable dates or None; sanitized availability error on DB failure.
    def get_cached_korean_holidays(
        self, year: int, month: int, *, max_age: timedelta,
    ) -> frozenset[date] | None:
        try:
            with self._session_factory() as db:
                return PharmacyCatalogRepository(db).get_cached_korean_holidays(
                    year, month, max_age=max_age,
                )
        except SQLAlchemyError:
            raise PharmacyApiUnavailableError("Calendar cache is unavailable.") from None

    # Function Name: replace_korean_holidays
    # Description: Persists a complete month in an independent, promptly closed transaction.
    # Parameters: year, month: Calendar month; holidays: Verified dates.
    # Returns: None; sanitized availability error on DB failure.
    def replace_korean_holidays(
        self, year: int, month: int, holidays: frozenset[date],
    ) -> None:
        try:
            with self._session_factory() as db:
                PharmacyCatalogRepository(db).replace_korean_holidays(year, month, holidays)
        except SQLAlchemyError:
            raise PharmacyApiUnavailableError("Calendar cache is unavailable.") from None
