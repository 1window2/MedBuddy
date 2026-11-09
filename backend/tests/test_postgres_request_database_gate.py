# File Name: test_postgres_request_database_gate.py
# Role: Checks on PostgreSQL that a burst of more requests than worker threads no longer stalls the
#   process: requests queue on the event loop for their account turn and a database slot.

import asyncio
import os
import time
from collections.abc import Iterator
from uuid import uuid4

import httpx
import pytest
from fastapi import Depends, FastAPI, Request
from sqlalchemy import text
from sqlalchemy.orm import Session

from api import dependencies
from api.dependencies import get_authenticated_principal, get_registered_principal
from core.database import SessionLocal, engine, get_db
from core.request_database_work import run_request_database_work
from entities.authenticated_principal_entity import AuthenticatedPrincipal

pytestmark = pytest.mark.skipif(
    os.getenv("MEDBUDDY_RUN_POSTGRES_INTEGRATION") != "1" or engine.dialect.name != "postgresql",
    reason="PostgreSQL request admission needs the PostgreSQL integration database.",
)

# Without the gate, more in-flight requests than the 40 AnyIO worker threads stalled every request
# until the 10 s pool timeout or the 5 s account lock timeout, then failed with 503.
_BURST_LIMIT_SECONDS = 4.0
_ROUTES = (("GET", "/read"), ("POST", "/write"), ("GET", "/steps"))


# Function Name: account_prefix
# Description:
# - Gives the test its own account names and removes the accounts it registered.
# Parameters:
# - None.
# Returns:
# - Iterator yielding the prefix.
@pytest.fixture
def account_prefix() -> Iterator[str]:
    prefix = f"gate-test-{uuid4().hex[:8]}-"
    yield prefix
    with SessionLocal() as db:
        db.execute(text("DELETE FROM user_accounts WHERE user_hash LIKE :prefix"), {"prefix": f"{prefix}%"})
        db.commit()


# Function Name: build_app
# Description:
# - Builds an app with the production registration dependency and three endpoint shapes of the
#   application: a synchronous read, a synchronous write that reads again after its commit, and
#   an asynchronous route whose database steps run through run_request_database_work.
# Parameters:
# - prefix (str): Account name prefix taken from the X-Test-Account header.
# Returns:
# - FastAPI application.
def build_app(prefix: str) -> FastAPI:
    app = FastAPI()

    # Function Name: header_principal
    # Description:
    # - Stands in for token verification: the account comes from the X-Test-Account header.
    # Parameters:
    # - request (Request): Incoming request.
    # Returns:
    # - AuthenticatedPrincipal of that account.
    def header_principal(request: Request) -> AuthenticatedPrincipal:
        account = prefix + request.headers["x-test-account"]
        return AuthenticatedPrincipal(subject=account, issuer="gate-test", user_hash=account)

    # Function Name: read_account
    # Description:
    # - Reads the registered account row in the request transaction.
    # Parameters:
    # - principal (AuthenticatedPrincipal): Registered caller.
    # - db (Session): Request session.
    # Returns:
    # - The account name.
    @app.get("/read")
    def read_account(
        principal: AuthenticatedPrincipal = Depends(get_registered_principal),
        db: Session = Depends(get_db),
    ) -> dict[str, str]:
        return {"user_hash": db.execute(
            text("SELECT user_hash FROM user_accounts WHERE user_hash = :owner"),
            {"owner": principal.user_hash},
        ).scalar_one()}

    # Function Name: write_account
    # Description:
    # - Commits and reads again in one thread, as a save followed by a refresh does.
    # Parameters:
    # - principal (AuthenticatedPrincipal): Registered caller.
    # - db (Session): Request session.
    # Returns:
    # - The account name.
    @app.post("/write")
    def write_account(
        principal: AuthenticatedPrincipal = Depends(get_registered_principal),
        db: Session = Depends(get_db),
    ) -> dict[str, str]:
        db.commit()
        return read_account(principal, db)

    # Function Name: step_account
    # Description:
    # - Ends the registration transaction in one step and reads in a later one.
    # Parameters:
    # - principal (AuthenticatedPrincipal): Registered caller.
    # - db (Session): Request session.
    # Returns:
    # - The account name.
    @app.get("/steps")
    async def step_account(
        principal: AuthenticatedPrincipal = Depends(get_registered_principal),
        db: Session = Depends(get_db),
    ) -> dict[str, str]:
        await run_request_database_work(db.commit)
        return await run_request_database_work(read_account, principal, db)

    app.dependency_overrides[get_authenticated_principal] = header_principal
    return app


# Function Name: burst
# Description:
# - Sends all requests at once and reports their status codes and the elapsed time.
# Parameters:
# - client (httpx.AsyncClient): Client bound to the test app.
# - accounts (list[str]): Account of each request.
# Returns:
# - Status codes and elapsed seconds.
async def burst(client: httpx.AsyncClient, accounts: list[str]) -> tuple[list[int], float]:
    started = time.perf_counter()
    responses = await asyncio.gather(*(
        client.request(*_ROUTES[index % len(_ROUTES)], headers={"X-Test-Account": account})
        for index, account in enumerate(accounts)
    ))
    return [response.status_code for response in responses], time.perf_counter() - started


# Function Name: test_burst_beyond_worker_threads_is_served_without_stalling
# Description:
# - 96 accounts at once, then 8 accounts with 12 requests each, over all three endpoint shapes,
#   are all answered quickly and the gate holds nothing afterwards.
# Parameters:
# - account_prefix (str): Per-test account prefix.
# - monkeypatch (pytest.MonkeyPatch): Turns per-account quotas off for the burst.
# Returns:
# - None.
@pytest.mark.anyio
async def test_burst_beyond_worker_threads_is_served_without_stalling(
    account_prefix: str, monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(dependencies.settings, "RATE_LIMIT_ENABLED", False)
    transport = httpx.ASGITransport(app=build_app(account_prefix))
    async with httpx.AsyncClient(transport=transport, base_url="http://gate.test", timeout=30) as client:
        for accounts in (
            [f"distinct-{index}" for index in range(96)],
            [f"busy-{index % 8}" for index in range(96)],
        ):
            codes, elapsed = await burst(client, accounts)
            assert codes == [200] * len(accounts)
            assert elapsed < _BURST_LIMIT_SECONDS
    gate = dependencies._postgres_request_gate
    assert gate.slots.available == gate.slots.capacity
    assert gate.accounts.active_scope_count == 0
