# File Name: test_saved_medication_enrichment.py
# Role: Covers detached enrichment, exact identity, ownership and stale-write protection.

import asyncio
from datetime import datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import BackgroundTasks

from api import dependencies
from boundaries.medication_summary_boundary import MISSING_DETAIL_TEXT
from entities.medication_detail_entity import MedicationDetail
from entities.saved_medication_entity import _SavedMedication
from entities.user_account_entity import _UserAccount
from schemas.medication import _MAX_DETAIL_TEXT_LENGTH
from services import saved_medication_enrichment as enrichment
from support.db import make_engine, make_session_factory, seed_account, seed_medication
from test_main_app_pipeline import pipeline, quota_clock, _client, _headers  # noqa: F401

SEQ = "202001476"
VALUES = {field: f"Official {field}" for field in enrichment.DETAIL_FIELDS}


@pytest.fixture
def factory(tmp_path):
    engine = make_engine(tmp_path)
    yield make_session_factory(engine)
    engine.dispose()


@pytest.fixture(autouse=True)
def reset_dispatchers(monkeypatch):
    monkeypatch.setattr(enrichment, "_dispatchers", {})


def seed_target(factory, **overrides):
    fields = {field: "" for field in enrichment.DETAIL_FIELDS}
    fields.update(overrides)
    with factory() as db:
        row = seed_medication(db, item_seq=SEQ, **fields)
        identifier = row.id
        tasks = BackgroundTasks()
        enrichment.queue_saved_medication_enrichment(
            tasks, db, {"success": True, "id": identifier}, "patient-a", SEQ,
        )
        return identifier, tasks.tasks[0].args[1]


async def finish(dispatcher):
    await asyncio.gather(*list(dispatcher.jobs.values()))
    await asyncio.sleep(0)


async def provide(target, values):
    values.update(VALUES)


@pytest.mark.anyio
async def test_fills_only_missing_details_preserves_reviewed_data(factory, monkeypatch):
    identifier, target = seed_target(factory, efficacy="Reviewed effect", warning_message=MISSING_DETAIL_TEXT)
    monkeypatch.setattr(enrichment, "fetch_public_details", provide)
    dispatcher = enrichment.EnrichmentDispatcher()
    await dispatcher.dispatch(factory, target)
    await finish(dispatcher)
    with factory() as db:
        row = db.get(_SavedMedication, identifier)
        assert row.efficacy == "Reviewed effect"
        assert row.warning_message == VALUES["warning_message"]
        assert row.use_method == VALUES["use_method"]
        assert row.item_name == "test-tablet" and row.dosage_per_time == "1 tablet"
        assert row.schedule_slot_keys == "[]" and row.daily_frequency == "3 times"
        assert row.image_url == "https://nedrug.mfds.go.kr/medicine.jpg"
        assert row.ai_guide == "guide" and row.regimen_revision == 0


@pytest.mark.anyio
@pytest.mark.parametrize("change", [
    "delete-medication", "delete-account", "tombstone", "revision", "name", "schedule",
    "product", "owner", "stop", "supersede",
])
async def test_rechecks_after_lookup_and_rejects_deleted_or_changed_target(factory, monkeypatch, change):
    identifier, target = seed_target(factory)
    entered, release = asyncio.Event(), asyncio.Event()

    async def blocked(target, values):
        entered.set()
        await release.wait()
        values.update(VALUES)

    monkeypatch.setattr(enrichment, "fetch_public_details", blocked)
    dispatcher = enrichment.EnrichmentDispatcher()
    await dispatcher.dispatch(factory, target)
    await asyncio.wait_for(entered.wait(), 2)
    with factory() as db:
        row = db.get(_SavedMedication, identifier)
        account = db.get(_UserAccount, "patient-a")
        if change == "delete-medication":
            db.delete(row)
        elif change == "delete-account":
            db.delete(account)
        elif change == "tombstone":
            account.deletion_requested_at = datetime.now()
        elif change == "revision":
            row.regimen_revision += 1
        elif change == "name":
            row.item_name = "Edited name"
        elif change == "schedule":
            row.schedule_slot_keys = '["evening"]'
        elif change == "product":
            row.item_seq = "999"
        elif change == "owner":
            seed_account(db, "patient-b")
            row.patient_hash = "patient-b"
        elif change == "stop":
            row.stopped_on = datetime.now().date()
        else:
            row.superseded_by_id = 999
        db.commit()
    release.set()
    await finish(dispatcher)
    with factory() as db:
        row = db.get(_SavedMedication, identifier)
        assert row is None or row.efficacy == ""


@pytest.mark.anyio
async def test_user_detail_edit_during_lookup_wins_but_other_blanks_fill(factory, monkeypatch):
    identifier, target = seed_target(factory)

    async def editing_provider(target, values):
        with factory() as db:
            db.get(_SavedMedication, identifier).warning_message = "User reviewed warning"
            db.commit()
        values.update(VALUES)

    monkeypatch.setattr(enrichment, "fetch_public_details", editing_provider)
    dispatcher = enrichment.EnrichmentDispatcher()
    await dispatcher.dispatch(factory, target)
    await finish(dispatcher)
    with factory() as db:
        row = db.get(_SavedMedication, identifier)
        assert row.warning_message == "User reviewed warning"
        assert row.efficacy == VALUES["efficacy"]


def mock_provider(monkeypatch, *, basic=None, approval=None, cache=None, summary=None):
    cache_boundary = SimpleNamespace(get=AsyncMock(return_value=cache))
    monkeypatch.setattr(dependencies, "_medication_detail_cache", cache_boundary)
    small = SimpleNamespace(searchMedication=AsyncMock(return_value=basic or []))
    large = SimpleNamespace(searchMedication=AsyncMock(return_value=approval or []))
    generator = SimpleNamespace(summarize_advanced_item=AsyncMock(return_value=summary))
    monkeypatch.setattr(dependencies, "_public_drug_small_api", small)
    monkeypatch.setattr(dependencies, "_public_drug_large_api", large)
    monkeypatch.setattr(dependencies, "_get_medication_summary_generator", lambda: generator)
    return small, large, generator


@pytest.mark.anyio
async def test_public_ambiguous_list_selects_exact_id_not_first_name(factory, monkeypatch):
    _, target = seed_target(factory)
    small, large, generator = mock_provider(monkeypatch, basic=[
        {"itemSeq": "999", "itemName": "test-tablet", "efcyQesitm": "Wrong product"},
        {"itemSeq": SEQ, "itemName": "Official name", "efcyQesitm": "Exact effect",
         "useMethodQesitm": "Exact use", "atpnWarnQesitm": "Exact warning",
         "intrcQesitm": "Interaction", "seQesitm": "Side effect", "depositMethodQesitm": "Storage"},
    ])
    values = {}
    await enrichment.fetch_public_details(target, values)
    assert values["efficacy"] == "Exact effect"
    assert values["warning_message"] == "Exact warning"
    large.searchMedication.assert_not_awaited()
    generator.summarize_advanced_item.assert_not_awaited()


@pytest.mark.anyio
async def test_complete_basic_core_still_enriches_missing_safety_from_approval(factory, monkeypatch):
    _, target = seed_target(factory)
    _, large, _ = mock_provider(monkeypatch,
        basic=[{"itemSeq": SEQ, "itemName": "Official name", "efcyQesitm": "Basic effect",
                "useMethodQesitm": "Basic use", "atpnWarnQesitm": "Basic warning"}],
        approval=[{"ITEM_SEQ": SEQ, "ITEM_NAME": "Official name",
                   "intrcQesitm": "Approval interaction", "seQesitm": "Approval side effect",
                   "STORAGE_METHOD": "Approval storage"}],
    )
    values = {}
    await enrichment.fetch_public_details(target, values)
    large.searchMedication.assert_awaited_once()
    assert values["efficacy"] == "Basic effect" and values["warning_message"] == "Basic warning"
    assert values["interaction"] == "Approval interaction"
    assert values["side_effect"] == "Approval side effect" and values["storage_method"] == "Approval storage"


@pytest.mark.anyio
@pytest.mark.parametrize("identity", ["999", "", "0202001476"])
async def test_public_identity_miss_never_summarizes_or_enriches(factory, monkeypatch, identity):
    _, target = seed_target(factory)
    _, _, generator = mock_provider(monkeypatch,
        basic=[{"itemSeq": identity, "itemName": "test-tablet", "efcyQesitm": "Wrong"}],
        approval=[{"ITEM_SEQ": identity, "ITEM_NAME": "test-tablet", "EE_DOC_DATA": "Wrong"}],
    )
    values = {}
    await enrichment.fetch_public_details(target, values)
    assert values == {}
    generator.summarize_advanced_item.assert_not_awaited()


@pytest.mark.anyio
async def test_exact_cached_detail_used_without_external_lookup(factory, monkeypatch):
    _, target = seed_target(factory, interaction="Reviewed", side_effect="Reviewed", storage_method="Reviewed")
    small, large, _ = mock_provider(monkeypatch, cache=[
        MedicationDetail(item_seq="999", item_name="test-tablet", efficacy="Wrong", usage_method="Wrong", warning="Wrong"),
        MedicationDetail(item_seq=SEQ, item_name="Official", efficacy="Cached", usage_method="Use", warning="Warn"),
    ])
    values = {}
    await enrichment.fetch_public_details(target, values)
    assert values["efficacy"] == "Cached"
    small.searchMedication.assert_not_awaited()
    large.searchMedication.assert_not_awaited()


@pytest.mark.anyio
async def test_approval_summary_failure_still_keeps_readable_authoritative_fields(factory, monkeypatch):
    identifier, target = seed_target(factory)
    _, _, generator = mock_provider(monkeypatch, approval=[{
        "ITEM_SEQ": SEQ, "ITEM_NAME": "test-tablet",
        "EE_DOC_DATA": "<DOC><PARAGRAPH>Official effect</PARAGRAPH></DOC>",
        "UD_DOC_DATA": "Official use", "NB_DOC_DATA": "Official warning",
    }])
    generator.summarize_advanced_item.side_effect = RuntimeError("AI unavailable")
    dispatcher = enrichment.EnrichmentDispatcher()
    await dispatcher.dispatch(factory, target)
    await finish(dispatcher)
    with factory() as db:
        row = db.get(_SavedMedication, identifier)
        assert row.efficacy == "Official effect" and row.warning_message == "Official warning"


@pytest.mark.anyio
async def test_failure_can_retry_on_later_duplicate_save(factory, monkeypatch):
    identifier, target = seed_target(factory)
    monkeypatch.setattr(enrichment, "fetch_public_details", AsyncMock(side_effect=RuntimeError("offline")))
    dispatcher = enrichment.EnrichmentDispatcher()
    await dispatcher.dispatch(factory, target)
    await finish(dispatcher)
    assert not dispatcher.jobs
    with factory() as db:
        assert db.get(_SavedMedication, identifier).efficacy == ""
        tasks = BackgroundTasks()
        enrichment.queue_saved_medication_enrichment(tasks, db,
            {"success": False, "duplicate": True, "id": identifier}, "patient-a", SEQ)
        assert len(tasks.tasks) == 1
        retry_target = tasks.tasks[0].args[1]
    monkeypatch.setattr(enrichment, "fetch_public_details", provide)
    await dispatcher.dispatch(factory, retry_target)
    await finish(dispatcher)
    with factory() as db:
        assert db.get(_SavedMedication, identifier).efficacy == VALUES["efficacy"]


@pytest.mark.anyio
async def test_timeout_dedup_and_concurrency_are_bounded(factory, monkeypatch):
    targets = [seed_target(factory, item_name=f"product-{i}")[1] for i in range(4)]
    active = peak = calls = 0

    async def blocked(target, values):
        nonlocal active, peak, calls
        calls += 1
        active += 1
        peak = max(peak, active)
        try:
            await asyncio.Event().wait()
        finally:
            active -= 1

    monkeypatch.setattr(enrichment, "fetch_public_details", blocked)
    monkeypatch.setattr(enrichment, "ENRICHMENT_TIMEOUT_SECONDS", 0.2)
    monkeypatch.setattr(enrichment, "MAX_PENDING_ENRICHMENTS", 3)
    monkeypatch.setattr(enrichment, "MAX_PENDING_ENRICHMENTS_PER_OWNER", 10)
    dispatcher = enrichment.EnrichmentDispatcher()
    for target in targets:
        await dispatcher.dispatch(factory, target)
        await dispatcher.dispatch(factory, target)
    assert len(dispatcher.jobs) == 3
    await asyncio.wait_for(finish(dispatcher), 2)
    assert peak <= 2 and calls <= 3 and not dispatcher.jobs


def test_apply_rejects_oversized_warning_without_truncating(factory):
    identifier, target = seed_target(factory)
    enrichment._apply(factory, target, {"warning_message": "W" * (_MAX_DETAIL_TEXT_LENGTH + 1)})
    with factory() as db:
        assert db.get(_SavedMedication, identifier).warning_message == ""


@pytest.mark.parametrize("owner,item_seq", [("patient-b", SEQ), ("patient-a", "999"), ("patient-a", "invalid")])
def test_queue_requires_owner_and_exact_saved_identity(factory, owner, item_seq):
    identifier, _ = seed_target(factory)
    with factory() as db:
        tasks = BackgroundTasks()
        enrichment.queue_saved_medication_enrichment(tasks, db,
            {"success": False, "duplicate": True, "id": identifier}, owner, item_seq)
        assert not tasks.tasks


@pytest.mark.anyio
async def test_http_external_failure_does_not_change_save_success(pipeline, monkeypatch):
    monkeypatch.setattr(enrichment, "fetch_public_details", AsyncMock(side_effect=RuntimeError("Provider offline")))
    async with _client(pipeline.app) as client:
        response = await client.post("/api/v1/medication/save", headers=_headers(), json={
            "item_seq": SEQ, "item_name": "Saved despite outage", "efficacy": "", "use_method": "", "warning_message": "",
        })
        assert response.status_code == 200 and response.json()["success"]
        for dispatcher in list(enrichment._dispatchers.values()):
            await finish(dispatcher)
    with pipeline.factory() as db:
        row = db.get(_SavedMedication, response.json()["id"])
        assert row.item_name == "Saved despite outage" and row.efficacy == ""


@pytest.mark.anyio
async def test_real_account_guard_releases_before_slow_enrichment_and_second_save(pipeline, monkeypatch):
    entered, release = asyncio.Event(), asyncio.Event()

    async def blocked(target, values):
        entered.set()
        await release.wait()
        values.update(VALUES)

    monkeypatch.setattr(enrichment, "fetch_public_details", blocked)
    body = {"patient_hash": "default_patient", "item_seq": SEQ, "item_name": "First product",
            "efficacy": "", "use_method": "", "warning_message": ""}
    # Omit the legacy default owner: authorization derives the verified user's scope.
    body.pop("patient_hash")
    async with _client(pipeline.app) as client:
        try:
            first = await asyncio.wait_for(client.post("/api/v1/medication/save", json=body, headers=_headers()), 2)
            assert first.status_code == 200 and first.json()["success"]
            await asyncio.wait_for(entered.wait(), 2)
            second = await asyncio.wait_for(client.post("/api/v1/medication/save",
                json={**body, "item_name": "Second product"}, headers=_headers()), 2)
            assert second.status_code == 200 and second.json()["success"]
            assert not release.is_set()
        finally:
            release.set()
            for dispatcher in list(enrichment._dispatchers.values()):
                await finish(dispatcher)
        listed = await client.get("/api/v1/medication/list", headers=_headers())
        assert listed.status_code == 200
        with pipeline.factory() as db:
            assert all(row.efficacy == VALUES["efficacy"] for row in db.query(_SavedMedication).all())


def test_regimen_change_queues_the_new_course_still_missing_details(factory):
    from controls.manage_medication_care_control import ManageMedicationCare
    from test_medication_care import change, medication, principal

    with factory() as db:
        old_id = medication(db, item_seq=SEQ, **{field: "" for field in enrichment.DETAIL_FIELDS}).id
        response = ManageMedicationCare(db).change_medication(principal(), old_id, change())
        tasks = BackgroundTasks()
        enrichment.queue_changed_medication_enrichment(tasks, db, response)
        target = tasks.tasks[0].args[1]
        # The save's job targets old_id and stops at the superseded row; the new course needs its own.
        assert target.medication_id == response["id"] != old_id
        assert (target.owner, target.item_seq) == ("patient-a", SEQ)
        assert set(target.missing) == set(enrichment.DETAIL_FIELDS)

        refused = BackgroundTasks()
        enrichment.queue_changed_medication_enrichment(refused, db, {"success": False, "id": response["id"]})
        assert not refused.tasks


@pytest.mark.anyio
async def test_summary_is_skipped_when_only_unsummarisable_fields_are_missing(factory, monkeypatch):
    _, target = seed_target(
        factory, efficacy="Saved effect", use_method="Saved use", warning_message="Saved warning",
    )
    _, large, generator = mock_provider(monkeypatch, approval=[{
        "ITEM_SEQ": SEQ, "ITEM_NAME": "test-tablet", "EE_DOC_DATA": "Official effect",
    }])
    values = {}
    await enrichment.fetch_public_details(target, values)
    large.searchMedication.assert_awaited_once()
    # Interaction, side effects and storage cannot come from the summary.
    generator.summarize_advanced_item.assert_not_awaited()


@pytest.mark.anyio
async def test_answered_lookup_is_not_repeated_by_duplicate_saves(factory, monkeypatch):
    _, target = seed_target(factory)
    lookups = AsyncMock()
    monkeypatch.setattr(enrichment, "fetch_public_details", lookups)
    dispatcher = enrichment.EnrichmentDispatcher()
    for _ in range(3):
        await dispatcher.dispatch(factory, target)
        await finish(dispatcher)
    # The public data answered without filling the blanks: duplicate saves and replayed
    # changes do not look the row up again inside the retry window.
    assert lookups.await_count == 1
    monkeypatch.setattr(enrichment, "ENRICHMENT_RETRY_SECONDS", 0.0)
    await dispatcher.dispatch(factory, target)
    await finish(dispatcher)
    assert lookups.await_count == 2


@pytest.mark.anyio
async def test_one_account_cannot_fill_the_shared_queue(factory, monkeypatch):
    own = [seed_target(factory, item_name=f"product-{i}")[1] for i in range(6)]
    with factory() as db:
        seed_account(db, "patient-b")
        row = seed_medication(db, patient_hash="patient-b", item_seq=SEQ,
                              **{field: "" for field in enrichment.DETAIL_FIELDS})
        tasks = BackgroundTasks()
        enrichment.queue_saved_medication_enrichment(
            tasks, db, {"success": True, "id": row.id}, "patient-b", SEQ,
        )
        other = tasks.tasks[0].args[1]
    release = asyncio.Event()

    async def blocked(target, values):
        await release.wait()

    monkeypatch.setattr(enrichment, "fetch_public_details", blocked)
    dispatcher = enrichment.EnrichmentDispatcher()
    for target in own:
        await dispatcher.dispatch(factory, target)
    await dispatcher.dispatch(factory, other)
    owners = [key[1] for key in dispatcher.jobs]
    assert owners.count("patient-a") == enrichment.MAX_PENDING_ENRICHMENTS_PER_OWNER
    assert owners.count("patient-b") == 1
    release.set()
    await finish(dispatcher)
