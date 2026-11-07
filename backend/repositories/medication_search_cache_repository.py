# File Name: medication_search_cache_repository.py
# Role: Remembers the public products a medication search returned and reads them back for chat.

from collections.abc import Callable, Iterable
from datetime import timedelta

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from starlette.concurrency import run_in_threadpool

from entities.medication_detail_entity import MedicationDetail, MedicationSearchCacheRecord
from entities.medication_image_url_entity import safe_medication_image_url
from entities.user_account_entity import utc_now

SEARCH_CACHE_MAX_AGE = timedelta(hours=24)
_ITEM_SEQ_MAX_LENGTH = 64
_NAME_MAX_LENGTH = 300
_MANUFACTURER_MAX_LENGTH = 200


# Class Name: MedicationSearchCacheRepository
# Role: Stores and reads the short-lived public product cache of the medication search.
# Responsibilities:
# - Upsert the products of one search result and drop entries older than a day.
# - Return only fresh entries, so a chat attachment needs a search from the last 24 hours.
# Attributes:
# - db (Session): Session of the current work.
class MedicationSearchCacheRepository:
    # Function Name: __init__
    # Description: Bind the session used to read and persist authoritative medication search snapshots.
    # Parameters: db (Session) is the caller's database session.
    # Returns: None.
    def __init__(self, db: Session) -> None:
        self.db = db

    # Function Name: remember
    # Description:
    # - Saves the public fields of each product with an item number and prunes expired rows.
    # - Products without an item number, or with fields longer than the chat schema allows,
    #   are skipped; they cannot be attached.
    # Parameters:
    # - details (Iterable[MedicationDetail]): Products the search returned to a user.
    # Returns:
    # - None. Commits its own transaction.
    def remember(self, details: Iterable[MedicationDetail]) -> None:
        now = utc_now()
        rows: dict[str, dict[str, object]] = {}
        for detail in details:
            item_seq = (detail.item_seq or "").strip()
            name = (detail.item_name or "").strip()
            manufacturer = (detail.manufacturer or "").strip()
            if (
                not item_seq or len(item_seq) > _ITEM_SEQ_MAX_LENGTH
                or not name or len(name) > _NAME_MAX_LENGTH
                or len(manufacturer) > _MANUFACTURER_MAX_LENGTH
            ):
                continue
            rows[item_seq] = dict(
                item_name=name, manufacturer=manufacturer,
                image_url=safe_medication_image_url(detail.image_url), fetched_at=now,
            )
        try:
            self.db.query(MedicationSearchCacheRecord).filter(
                MedicationSearchCacheRecord.fetched_at <= now - SEARCH_CACHE_MAX_AGE,
            ).delete(synchronize_session=False)
            for item_seq, values in rows.items():
                query = self.db.query(MedicationSearchCacheRecord).filter_by(item_seq=item_seq)
                if query.update(values, synchronize_session=False):
                    continue
                try:
                    # 같은 품목을 동시에 처음 저장해도 검색 자체가 실패하지 않게 한다.
                    with self.db.begin_nested():
                        self.db.add(MedicationSearchCacheRecord(item_seq=item_seq, **values))
                        self.db.flush()
                except IntegrityError:
                    if not query.update(values, synchronize_session=False):
                        raise
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise

    # Function Name: find
    # Description: Reads the fresh cached products for the given item numbers.
    # Parameters:
    # - item_seqs (Iterable[str]): Item numbers to look up.
    # Returns:
    # - Mapping of item number to item_name, manufacturer and image_url; missing or expired
    #   products are absent.
    def find(self, item_seqs: Iterable[str]) -> dict[str, dict[str, str]]:
        wanted = {item for item in item_seqs if item}
        if not wanted:
            return {}
        cutoff = utc_now() - SEARCH_CACHE_MAX_AGE
        records = self.db.query(MedicationSearchCacheRecord).filter(
            MedicationSearchCacheRecord.item_seq.in_(wanted),
            MedicationSearchCacheRecord.fetched_at > cutoff,
        ).all()
        return {
            str(record.item_seq): {
                "item_name": str(record.item_name),
                "manufacturer": str(record.manufacturer or ""),
                "image_url": safe_medication_image_url(record.image_url),
            }
            for record in records
        }


# Class Name: AsyncMedicationSearchCache
# Role: Persist detached medication search results outside the event loop.
# Responsibilities: Run each cache write in a worker-owned session and close it on success or failure.
# Attributes: _session_factory creates an independent session per write.
class AsyncMedicationSearchCache:
    # Function Name: __init__
    # Description: Retain a session factory without opening a database connection.
    # Parameters: session_factory (Callable[[], Session]) supplies an independent session per asynchronous write.
    # Returns: None.
    def __init__(self, session_factory: Callable[[], Session]) -> None:
        self._session_factory = session_factory

    # Function Name: remember
    # Description: Save the detached search results in a fresh worker session, keeping database work off the event loop.
    # Parameters: details (list[MedicationDetail]) contains products to cache.
    # Returns: None; persistence failures propagate after the worker session closes.
    async def remember(self, details: list[MedicationDetail]) -> None:
        # Function Name: execute
        # Description: Persists the captured search products using a new worker-owned session, closed even when saving fails.
        # Parameters: None; captures details and the adapter's session factory.
        # Returns: None; persistence errors propagate to the asynchronous caller.
        def execute() -> None:
            with self._session_factory() as db:
                MedicationSearchCacheRepository(db).remember(details)

        await run_in_threadpool(execute)
