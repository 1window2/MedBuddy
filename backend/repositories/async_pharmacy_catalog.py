# File Name: async_pharmacy_catalog.py
# Role: Runs nearby-pharmacy catalogue operations in short-lived worker sessions.

from collections.abc import Callable
from datetime import date, datetime, timedelta
from typing import TypeVar

from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from entities.nearby_pharmacy_entity import NearbyPharmacy
from entities.pharmacy_catalog_entity import PharmacyCatalogEntry, PharmacyHolidaySchedule
from repositories.pharmacy_catalog_repository import PharmacyCatalogRepository

_T = TypeVar("_T")


# Class Name: AsyncPharmacyCatalog
# Role: Exposes blocking catalogue operations to the async search use case.
# Responsibilities:
# - Own a fresh ORM session for each worker operation and close it before returning.
# - Keep SQL work off the event loop and away from a request-owned session.
class AsyncPharmacyCatalog:
    # Function Name: __init__
    # Description: Retains a session factory without opening a transaction.
    # Parameters: session_factory: Creates one independent ORM session per operation.
    # Returns: None.
    def __init__(self, session_factory: Callable[[], Session]) -> None:
        self._session_factory = session_factory

    # Function Name: _run
    # Description: Executes one repository operation in a worker and closes its session.
    # Parameters: operation: Synchronous operation against a new repository.
    # Returns: Operation result, detached from the ORM session.
    async def _run(self, operation: Callable[[PharmacyCatalogRepository], _T]) -> _T:
        def execute() -> _T:
            with self._session_factory() as db:
                return operation(PharmacyCatalogRepository(db))

        return await run_in_threadpool(execute)

    # Function Name: count
    # Description: Counts catalogue rows outside the event loop.
    # Parameters: None.
    # Returns: Catalogue row count.
    async def count(self) -> int:
        return await self._run(lambda repository: repository.count())

    # Function Name: latest_updated_at
    # Description: Reads the latest source timestamp in a worker session.
    # Parameters: None.
    # Returns: Latest source timestamp or None.
    async def latest_updated_at(self) -> datetime | None:
        return await self._run(lambda repository: repository.latest_updated_at())

    # Function Name: search_nearby_candidates
    # Description: Materializes detached catalogue entries within the search bounds.
    # Parameters: latitude, longitude: Search coordinates; max_distance_km: Bounding radius.
    # Returns: Candidate entries.
    async def search_nearby_candidates(
        self, *, latitude: float, longitude: float, max_distance_km: float,
    ) -> list[PharmacyCatalogEntry]:
        return await self._run(lambda repository: repository.search_nearby_candidates(
            latitude=latitude, longitude=longitude, max_distance_km=max_distance_km,
        ))

    # Function Name: get_cached_holiday_schedules
    # Description: Reads one dated roster without retaining its transaction.
    # Parameters: value: Roster date; max_age: Accepted cache age.
    # Returns: Cached schedules, including a verified empty roster, or None.
    async def get_cached_holiday_schedules(
        self, value: date, *, max_age: timedelta,
    ) -> dict[str, PharmacyHolidaySchedule] | None:
        return await self._run(lambda repository: repository.get_cached_holiday_schedules(
            value, max_age=max_age,
        ))

    # Function Name: replace_holiday_schedules
    # Description: Commits a complete dated roster in its own worker session.
    # Parameters: value: Roster date; schedules: Verified complete roster.
    # Returns: None.
    async def replace_holiday_schedules(
        self, value: date, schedules: list[PharmacyHolidaySchedule],
    ) -> None:
        await self._run(lambda repository: repository.replace_holiday_schedules(
            value, schedules,
        ))

    # Function Name: cache_search_results
    # Description: Stores public fallback results without blocking the event loop.
    # Parameters: pharmacies: Validated nearby public results.
    # Returns: None.
    async def cache_search_results(self, pharmacies: list[NearbyPharmacy]) -> None:
        await self._run(lambda repository: repository.cache_search_results(pharmacies))
