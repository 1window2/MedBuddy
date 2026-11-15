# File Name: test_exact_medication_catalog.py
# Role: Verifies exact read-only catalog mapping and authenticated HTTP boundaries.

import json
from collections.abc import Iterator
from datetime import datetime
from unittest.mock import Mock
from urllib.parse import quote

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import event
from sqlalchemy.orm import Session

from api import dependencies
from api.router import router
from boundaries.medication_summary_boundary import (
    FAILED_SUMMARY_TEXT,
    MISSING_DETAIL_TEXT,
    MedicationSummaryGenerator,
)
from boundaries.public_drug_api_boundary import (
    PillImageAPI,
    PublicDrugLargeAPI,
    PublicDrugSmallAPI,
)
from controls.check_catalog_medication_detail_control import CheckCatalogMedicationDetail
from controls.check_medication_detail_control import CheckMedicationDetail
from core.config import settings
from core.database import get_db
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.medication_detail_entity import (
    _DrugApprovalInfo,
    _DrugBasicInfo,
    normalize_catalog_item_name,
)
from services.local_medication_catalog import LocalMedicationCatalog
from services.medication_name_matching import MedicationNameMatcher
from schemas.medication import SavedMedicationCreate, _MAX_DETAIL_TEXT_LENGTH

BASE = "/api/v1/medication"
ITEM_SEQ = "202001476"
IMAGE = "https://nedrug.mfds.go.kr/pill.png"


def basic(item_seq: str | None = ITEM_SEQ, **values: object) -> _DrugBasicInfo:
    fields = dict(
        item_seq=item_seq, item_name="Confirmed tablet 50mg", entp_name="Trusted maker",
        normalized_item_name=normalize_catalog_item_name("Confirmed tablet 50mg"),
        efficacy="Stored efficacy", use_method="Stored usage", warning_message="Stored warning",
        interaction="Stored interaction", side_effect="Stored side effect",
        deposit_method="Stored storage", ai_guide="Stored guide", raw_json="{}",
    )
    fields.update(values)
    return _DrugBasicInfo(**fields)


def approval(item_seq: str = ITEM_SEQ, **values: object) -> _DrugApprovalInfo:
    fields = dict(
        item_seq=item_seq, item_name="Confirmed tablet 50mg", entp_name="Trusted maker",
        normalized_item_name=normalize_catalog_item_name("Confirmed tablet 50mg"),
        efficacy_doc="Raw efficacy", use_method_doc="Raw usage", warning_doc="Raw warning",
        raw_json="{}",
    )
    fields.update(values)
    return _DrugApprovalInfo(**fields)


@pytest.fixture(autouse=True)
def forbid_slow_lookup(monkeypatch: pytest.MonkeyPatch) -> None:
    def forbidden(*args: object, **kwargs: object) -> None:
        pytest.fail("Exact catalog lookup must not use AI, external APIs, name search or writes.")

    for cls, methods in (
        (CheckMedicationDetail, ("__init__",)),
        (MedicationSummaryGenerator, ("__init__", "summarize_advanced_item")),
        (PublicDrugSmallAPI, ("__init__", "searchMedication", "fetchPage")),
        (PublicDrugLargeAPI, ("__init__", "searchMedication", "fetchPage")),
        (PillImageAPI, ("__init__", "searchMedicationImage")),
        (MedicationNameMatcher, ("rank_candidates",)),
        (LocalMedicationCatalog, (
            "fetch_drug_info", "_search_catalog", "_search_basic", "_search_approval",
            "_build_approval_detail", "_save_approval_summary",
        )),
    ):
        for method in methods:
            monkeypatch.setattr(cls, method, forbidden)


@pytest.fixture
def app(fk_db: Session) -> FastAPI:
    application = FastAPI()
    application.include_router(router, prefix=BASE)
    principal = AuthenticatedPrincipal(subject="test", issuer="test", user_hash="patient-a")

    def database() -> Iterator[Session]:
        yield fk_db

    application.dependency_overrides[get_db] = database
    application.dependency_overrides[dependencies.get_authenticated_principal] = lambda: principal
    application.dependency_overrides[dependencies.get_registered_principal] = lambda: principal
    application.dependency_overrides[dependencies.verify_app_check_token] = lambda: None
    return application


def test_basic_exact_identity_complete_fields_and_precedence(fk_db: Session) -> None:
    fk_db.add_all([
        basic("202001475", entp_name="Other maker"),
        basic(raw_json=json.dumps({
            "itemSeq": ITEM_SEQ, "itemImage": IMAGE, "atpnQesitm": "Stored precaution",
            "itemName": "Do not replace the row name", "entpName": "Do not replace maker",
        })),
        approval(summary_efficacy="Do not prefer approval over basic"),
    ])
    fk_db.commit()

    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)

    assert result is not None
    assert result.getMedicationDetail() == {
        "item_seq": ITEM_SEQ, "item_name": "Confirmed tablet 50mg",
        "manufacturer": "Trusted maker", "efficacy": "Stored efficacy",
        "use_method": "Stored usage", "warning_message": "Stored warning",
        "precaution": "Stored precaution", "interaction": "Stored interaction",
        "side_effect": "Stored side effect", "storage_method": "Stored storage",
        "dosage_per_time": "", "daily_frequency": "", "total_days": "",
        "image_url": IMAGE, "source": "Local DB (basic catalog)", "ai_guide": "Stored guide",
    }


def test_approval_match_does_not_borrow_same_name_basic(fk_db: Session) -> None:
    fk_db.add_all([basic("202001475"), approval()])
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert result.item_seq == ITEM_SEQ
    assert result.efficacy == "Raw efficacy"


@pytest.mark.parametrize("factory", [basic, approval])
def test_raw_payload_preserves_fields_missing_from_columns(fk_db: Session, factory) -> None:
    row = factory(entp_name=None, raw_json=json.dumps({
        "itemSeq": ITEM_SEQ, "entpName": "Raw maker", "efcyQesitm": "Raw effect",
        "useMethodQesitm": "Raw usage", "atpnWarnQesitm": "Raw warning",
        "atpnQesitm": "Raw precaution", "intrcQesitm": "Raw interaction",
        "seQesitm": "Raw side effect", "depositMethodQesitm": "Raw storage",
    }))
    if isinstance(row, _DrugBasicInfo):
        row.efficacy = row.use_method = row.warning_message = " "
        row.interaction = row.side_effect = row.deposit_method = None
    else:
        row.efficacy_doc = row.use_method_doc = row.warning_doc = " "
    fk_db.add(row)
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert result.manufacturer == "Raw maker"
    assert result.efficacy == "Raw effect"
    assert result.usage_method == "Raw usage"
    assert result.warning == "Raw warning"
    assert result.precaution == "Raw precaution"
    assert result.interaction == "Raw interaction"
    assert result.side_effect == "Raw side effect"
    assert result.storage_method == "Raw storage"


def test_old_partial_approval_summary_uses_raw_missing_fields_without_refresh(fk_db: Session) -> None:
    row = approval(
        summary_efficacy="Stored summary", summary_use_method=MISSING_DETAIL_TEXT,
        summary_warning_message=FAILED_SUMMARY_TEXT, ai_guide="Stored guide",
        updated_at=datetime(2000, 1, 1),
        raw_json=json.dumps({
            "ITEM_SEQ": ITEM_SEQ, "ITEM_IMAGE": IMAGE, "atpnQesitm": "Precaution",
            "intrcQesitm": "Interaction", "seQesitm": "Side effect", "STORAGE_METHOD": "Storage",
        }),
    )
    fk_db.add(row)
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert result.efficacy == "Stored summary"
    assert result.usage_method == "Raw usage"
    assert result.warning == "Raw warning"
    assert result.item_seq == ITEM_SEQ
    assert result.item_name == row.item_name
    assert result.manufacturer == row.entp_name
    assert result.image_url == IMAGE
    assert result.precaution == "Precaution"
    assert result.interaction == "Interaction"
    assert result.side_effect == "Side effect"
    assert result.storage_method == "Storage"
    assert result.ai_guide == "Stored guide"
    assert result.source == "Local DB (approval catalog; stored summary)"
    fk_db.expire_all()
    assert row.updated_at == datetime(2000, 1, 1)
    assert row.summary_use_method == MISSING_DETAIL_TEXT
    assert row.summary_warning_message == FAILED_SUMMARY_TEXT


def test_complete_approval_summary_is_reused(fk_db: Session) -> None:
    fk_db.add(approval(
        summary_efficacy="Summary efficacy", summary_use_method="Summary usage",
        summary_warning_message="Summary warning",
    ))
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert (result.efficacy, result.usage_method, result.warning) == (
        "Summary efficacy", "Summary usage", "Summary warning",
    )


@pytest.mark.parametrize("factory", [basic, approval])
@pytest.mark.parametrize("length", [_MAX_DETAIL_TEXT_LENGTH, _MAX_DETAIL_TEXT_LENGTH + 1])
def test_catalog_details_fit_save_limits_without_partial_warnings(fk_db: Session, factory, length: int) -> None:
    row = factory(ai_guide="G" * (_MAX_DETAIL_TEXT_LENGTH + 1))
    if isinstance(row, _DrugBasicInfo):
        row.warning_message = "W" * length
    else:
        row.warning_doc = "<DOC><PARAGRAPH>" + "W" * length + "</PARAGRAPH></DOC>"
    fk_db.add(row)
    fk_db.commit()
    detail = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert detail.warning == ("W" * length if length <= _MAX_DETAIL_TEXT_LENGTH else MISSING_DETAIL_TEXT)
    assert detail.ai_guide is None
    SavedMedicationCreate(**detail.getMedicationDetail())


def test_raw_approval_aliases_become_readable_without_invention(fk_db: Session) -> None:
    document = '<DOC><SECTION title="Usage"><ARTICLE>Take only as prescribed.</ARTICLE></SECTION></DOC>'
    fk_db.add(approval(
        efficacy_doc=None, use_method_doc=None, warning_doc=None,
        raw_json=json.dumps({
            "prdlst_Stdr_code": ITEM_SEQ, "efcyQesitm": "Raw efficacy alias",
            "useMethodQesitm": document, "atpnWarnQesitm": "Raw warning alias",
            "itemImage": IMAGE,
        }),
    ))
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert result.efficacy == "Raw efficacy alias"
    assert result.usage_method == "Usage\n\nTake only as prescribed."
    assert result.warning == "Raw warning alias"
    assert result.image_url == IMAGE
    assert result.ai_guide is None
    assert result.source == "Local DB (approval catalog)"


def test_http_stored_xml_is_readable_and_document_links_are_not_guidance(
    app: FastAPI, fk_db: Session,
) -> None:
    fk_db.add(approval(
        efficacy_doc='<?xml version="1.0"?><DOC type="EE"><SECTION title="Source heading">'
        '<ARTICLE title="1. Source group"><PARAGRAPH tagName="p"><![CDATA[First <b>source</b> text.]]>'
        '</PARAGRAPH><PARAGRAPH>Second source paragraph.</PARAGRAPH></ARTICLE></SECTION></DOC>',
        use_method_doc="https://nedrug.mfds.go.kr/doc.pdf",
        warning_doc='<!DOCTYPE DOC [<!ENTITY x SYSTEM "https://example.com/doc">]><DOC>&x;</DOC>',
    ))
    fk_db.commit()
    with TestClient(app) as client:
        response = client.get(f"{BASE}/catalog/{ITEM_SEQ}")
    assert response.status_code == 200
    result = response.json()["data"]
    assert result["efficacy"] == (
        "Source heading\n\n1. Source group\n\nFirst source text.\n\nSecond source paragraph."
    )
    assert result["use_method"] == result["warning_message"] == MISSING_DETAIL_TEXT


@pytest.mark.parametrize("factory", [basic, approval])
@pytest.mark.parametrize("payload", ["broken-json", "[]", "null", "42"])
def test_unusable_payload_keeps_column_details(fk_db: Session, factory, payload: str) -> None:
    fk_db.add(factory(raw_json=payload))
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert result.item_seq == ITEM_SEQ and result.manufacturer == "Trusted maker"
    assert result.warning in {"Stored warning", "Raw warning"}
    assert result.image_url == ""


@pytest.mark.parametrize("factory", [basic, approval])
def test_payload_of_different_product_cannot_supply_image_or_safety(fk_db: Session, factory) -> None:
    fk_db.add(factory(raw_json=json.dumps({
        "ITEM_SEQ": "999999999", "ITEM_NAME": "Wrong product", "ITEM_IMAGE": IMAGE,
        "atpnQesitm": "Wrong precaution", "EE_DOC_DATA": "Wrong efficacy",
    })))
    fk_db.commit()
    result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    assert result.item_seq == ITEM_SEQ and result.item_name == "Confirmed tablet 50mg"
    assert result.image_url == "" and result.precaution == ""
    assert result.efficacy in {"Stored efficacy", "Raw efficacy"}


@pytest.mark.parametrize("factory", [basic, approval])
def test_image_survives_missing_guidance_and_unsafe_urls_are_filtered(fk_db: Session, factory) -> None:
    row = factory(raw_json=json.dumps({"itemImage": IMAGE}))
    if isinstance(row, _DrugBasicInfo):
        row.efficacy = row.use_method = row.warning_message = None
    else:
        row.efficacy_doc = row.use_method_doc = row.warning_doc = None
    fk_db.add(row)
    fk_db.commit()
    control = CheckCatalogMedicationDetail(fk_db)
    result = control.get_detail(ITEM_SEQ)
    assert result.efficacy == result.usage_method == result.warning == MISSING_DETAIL_TEXT
    assert result.image_url == IMAGE
    row.raw_json = json.dumps({"itemImage": "http://127.0.0.1/private"})
    fk_db.commit()
    assert control.get_detail(ITEM_SEQ).image_url == ""


@pytest.mark.parametrize("kind, expected_queries", [("basic", 1), ("approval", 2), ("missing", 2)])
def test_bounded_indexed_reads_never_flush_commit_or_write(
    fk_db: Session, monkeypatch: pytest.MonkeyPatch, kind: str, expected_queries: int,
) -> None:
    if kind != "missing":
        fk_db.add(basic() if kind == "basic" else approval())
        fk_db.commit()
    fk_db.autoflush = True
    pending = basic("999")
    fk_db.add(pending)
    statements: list[tuple[str, object]] = []

    def record(connection, cursor, statement, parameters, context, executemany):
        statements.append((statement, parameters))

    engine = fk_db.get_bind()
    event.listen(engine, "before_cursor_execute", record)
    monkeypatch.setattr(fk_db, "flush", Mock(side_effect=AssertionError("Unexpected flush")))
    monkeypatch.setattr(fk_db, "commit", Mock(side_effect=AssertionError("Unexpected commit")))
    try:
        result = CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ)
    finally:
        event.remove(engine, "before_cursor_execute", record)
    assert (result is None) == (kind == "missing")
    assert pending in fk_db.new
    assert len(statements) == expected_queries
    for sql, parameters in statements:
        assert sql.startswith("SELECT ") and " LIKE " not in sql.upper()
        assert ".item_seq = ?" in sql and "LIMIT" in sql
        assert parameters[0] == ITEM_SEQ


def test_missing_never_falls_back_to_a_name_or_neighbor_id(fk_db: Session) -> None:
    fk_db.add_all([basic("202001475"), approval("0202001476"), basic(None)])
    fk_db.commit()
    assert CheckCatalogMedicationDetail(fk_db).get_detail(ITEM_SEQ) is None


def test_http_success_null_and_existing_care_paths(app: FastAPI, fk_db: Session) -> None:
    fk_db.add(basic())
    fk_db.commit()
    with TestClient(app) as client:
        response = client.get(f"{BASE}/catalog/{ITEM_SEQ}")
        assert response.status_code == 200
        assert response.json()["success"] is True
        data = response.json()["data"]
        assert data["item_seq"] == ITEM_SEQ
        assert data["use_method"] == "Stored usage"
        assert data["warning_message"] == "Stored warning"
        assert "usage_method" not in data and "warning" not in data
        missing = client.get(f"{BASE}/catalog/999999999")
        assert missing.status_code == 200 and missing.json() == {"success": True, "data": None}
        assert client.post(f"{BASE}/catalog/{ITEM_SEQ}").status_code == 405
    paths = app.openapi()["paths"]
    assert f"{BASE}/care/history" in paths
    assert f"{BASE}/care/history/{{medication_id}}/{{schedule_date}}/{{slot_key}}" in paths
    assert f"{BASE}/care/medications/{{medication_id}}/change" in paths
    assert f"{BASE}/care/catalog/{{item_seq}}" not in paths


@pytest.mark.parametrize("item_seq", ["0", "1", "0" * 31 + "1", "9" * 32])
def test_http_accepts_bounded_digit_strings_without_normalizing(
    app: FastAPI, fk_db: Session, item_seq: str,
) -> None:
    fk_db.add(basic(item_seq))
    fk_db.commit()
    with TestClient(app) as client:
        response = client.get(f"{BASE}/catalog/{item_seq}")
    assert response.status_code == 200 and response.json()["data"]["item_seq"] == item_seq


@pytest.mark.parametrize("item_seq", [
    "9" * 33, "-1", "+1", "1.0", " 123", "123 ", "123\n", "1e9", "abc", "12_3",
    "\uff11\uff12\uff13", "\u0661\u0662", "1' OR '1'='1", "%",
])
def test_http_rejects_invalid_ids_before_lookup(
    app: FastAPI, monkeypatch: pytest.MonkeyPatch, item_seq: str,
) -> None:
    lookup = Mock(side_effect=AssertionError("Invalid IDs must not reach catalog reads"))
    monkeypatch.setattr(CheckCatalogMedicationDetail, "get_detail", lookup)
    with TestClient(app) as client:
        response = client.get(f"{BASE}/catalog/{quote(item_seq, safe='')}")
    assert response.status_code == 422
    lookup.assert_not_called()


def test_missing_path_id_is_not_a_catalog_request(app: FastAPI) -> None:
    with TestClient(app) as client:
        assert client.get(f"{BASE}/catalog/").status_code == 404


def test_database_failure_is_not_reported_as_missing(app: FastAPI, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(CheckCatalogMedicationDetail, "get_detail", Mock(side_effect=RuntimeError("DB failed")))
    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get(f"{BASE}/catalog/{ITEM_SEQ}")
    assert response.status_code == 500


@pytest.mark.parametrize("item_seq", ["", "abc", "9" * 33, "123\n"])
def test_control_rejects_invalid_ids_without_queries(item_seq: str) -> None:
    db = Mock()
    with pytest.raises(ValueError, match="ASCII digits"):
        CheckCatalogMedicationDetail(db).get_detail(item_seq)
    db.query.assert_not_called()


def test_http_requires_real_bearer_authentication(app: FastAPI, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "AUTH_MODE", "firebase")
    del app.dependency_overrides[dependencies.get_authenticated_principal]
    lookup = Mock(side_effect=AssertionError("Unauthenticated lookup"))
    monkeypatch.setattr(CheckCatalogMedicationDetail, "get_detail", lookup)
    with TestClient(app) as client:
        response = client.get(f"{BASE}/catalog/{ITEM_SEQ}")
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"
    lookup.assert_not_called()


@pytest.mark.parametrize("guard, status", [
    (dependencies.verify_app_check_token, 403),
    (dependencies.get_registered_principal, 403),
    (dependencies.get_registered_principal, 409),
])
def test_parent_authorization_guards_run_before_catalog_lookup(
    app: FastAPI, monkeypatch: pytest.MonkeyPatch, guard, status: int,
) -> None:
    def reject() -> None:
        raise HTTPException(status_code=status, detail="Guard rejected request")

    app.dependency_overrides[guard] = reject
    lookup = Mock(side_effect=AssertionError("Authorization must run before lookup"))
    monkeypatch.setattr(CheckCatalogMedicationDetail, "get_detail", lookup)
    with TestClient(app) as client:
        response = client.get(f"{BASE}/catalog/{ITEM_SEQ}")
    assert response.status_code == status
    lookup.assert_not_called()
