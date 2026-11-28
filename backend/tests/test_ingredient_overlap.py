# File Name: test_ingredient_overlap.py
# Role: Verifies the ingredient-code parser, the active-medicine selection of the ingredient-overlap
#   check, its same-product, saved and batch overlaps, the request limits and the owner scope of
#   its route.

import logging
from datetime import timedelta

import pytest
from pydantic import ValidationError
from sqlalchemy.orm import Session

from api.router import check_ingredient_overlap
from controls.authorization_control import AuthorizationControl
from controls.check_ingredient_overlap_control import CheckIngredientOverlap
from core.application_clock import application_today
from entities.authenticated_principal_entity import AuthenticatedPrincipal
from entities.medication_detail_entity import _DrugApprovalInfo
from entities.patient_caregiver_link_entity import _PatientCaregiverLink
from schemas.ingredient_overlap import IngredientOverlapRequest
from services.medication_ingredients import parse_ingredient_codes
from support.db import seed_account, seed_medication

TYLENOL = "200000001"
GEVORIN = "200000002"
PANCOLD = "200000003"
FAMOTIDINE = "200000004"
UNKNOWN = "200000099"

_CATALOG = {
    TYLENOL: ("타이레놀정500밀리그램", "[M040702]아세트아미노펜"),
    GEVORIN: (
        "게보린정",
        "[M040702]아세트아미노펜|[M223303]카페인무수물|[M089001]이소프로필안티피린",
    ),
    PANCOLD: ("판콜에이내복액", "[M040702]아세트아미노펜|[M111111]클로르페니라민"),
    FAMOTIDINE: ("파모티딘정", "[M555555]파모티딘"),
}


# Function Name: _seed_catalog
# Description: Adds the approval rows used by the overlap tests.
# Parameters: db (Session) is the test session.
# Returns: None.
def _seed_catalog(db: Session) -> None:
    for item_seq, (item_name, main_ingredient) in _CATALOG.items():
        db.add(
            _DrugApprovalInfo(
                item_seq=item_seq,
                item_name=item_name,
                normalized_item_name=item_name,
                main_ingredient=main_ingredient,
                raw_json="{}",
            )
        )
    db.commit()


# Function Name: _check
# Description: Runs the overlap control for one owner.
# Parameters: db (Session) is the test session; item_seqs are the requested products; owner is the patient hash.
# Returns: dict mapping each requested item_seq to its overlaps as plain dictionaries.
def _check(db: Session, *item_seqs: str, owner: str = "patient-a") -> dict[str, list[dict]]:
    response = CheckIngredientOverlap(db).request_ingredient_overlap(owner, list(item_seqs))
    payload = response.model_dump(by_alias=True)
    assert payload["success"] is True
    return {item["item_seq"]: item["overlaps"] for item in payload["items"]}


# Function Name: _principal
# Description: Builds a verified Firebase principal.
# Parameters: subject (str) is the external user id.
# Returns: AuthenticatedPrincipal.
def _principal(subject: str) -> AuthenticatedPrincipal:
    return AuthenticatedPrincipal.from_verified_claims(
        {
            "uid": subject,
            "iss": "https://securetoken.google.com/medbuddy-test",
            "email": f"{subject}@example.com",
            "email_verified": True,
        }
    )


# Function Name: test_parser_reads_a_combination_in_code_order
# Description: Splits a combination product into its codes and names.
# Parameters: None. Returns: None.
def test_parser_reads_a_combination_in_code_order() -> None:
    assert parse_ingredient_codes(
        "[M040702]아세트아미노펜|[M223303]카페인무수물"
    ) == {"M040702": "아세트아미노펜", "M223303": "카페인무수물"}
    assert list(parse_ingredient_codes(_CATALOG[GEVORIN][1])) == [
        "M040702",
        "M223303",
        "M089001",
    ]


# Function Name: test_parser_keeps_the_first_non_empty_name_of_a_duplicate_code
# Description: A repeated code keeps one entry, named by its first non-empty name.
# Parameters: None. Returns: None.
def test_parser_keeps_the_first_non_empty_name_of_a_duplicate_code() -> None:
    assert parse_ingredient_codes("[M1]|[M1]아세트아미노펜|[M1]다른이름") == {
        "M1": "아세트아미노펜",
    }
    assert parse_ingredient_codes("[M1]") == {"M1": ""}


# Function Name: test_parser_ignores_empty_text_and_parts_without_a_code
# Description: Empty values, legacy plain text and uncoded parts give no codes.
# Parameters: None. Returns: None.
def test_parser_ignores_empty_text_and_parts_without_a_code() -> None:
    assert parse_ingredient_codes(None) == {}
    assert parse_ingredient_codes("") == {}
    assert parse_ingredient_codes("   ") == {}
    assert parse_ingredient_codes("아세트아미노펜") == {}
    assert parse_ingredient_codes("아세트아미노펜|[M2]카페인") == {"M2": "카페인"}
    assert parse_ingredient_codes("[m2]lowercase|[2]digits") == {}


# Function Name: test_parser_keeps_a_bar_inside_a_name
# Description: Splits only where the next part starts with a code.
# Parameters: None. Returns: None.
def test_parser_keeps_a_bar_inside_a_name() -> None:
    assert parse_ingredient_codes("[M3]성분A|성분B|[M4]성분C") == {
        "M3": "성분A|성분B",
        "M4": "성분C",
    }


# Function Name: test_same_product_in_the_list_is_reported_once
# Description: A saved row of the same product number is one same_product entry, not one per ingredient.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_same_product_in_the_list_is_reported_once(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    seed_medication(fk_db, item_seq=GEVORIN, item_name="게보린정")

    overlaps = _check(fk_db, GEVORIN)[GEVORIN]

    assert overlaps == [
        {
            "ingredient_code": "M040702",
            "ingredient_name": "아세트아미노펜",
            "with": {
                "item_seq": GEVORIN,
                "item_name": "게보린정",
                "source": "saved",
                "same_product": True,
            },
        }
    ]


# Function Name: test_other_saved_product_is_reported_per_shared_ingredient
# Description: Another active saved product is named with each shared ingredient and the saved name.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_other_saved_product_is_reported_per_shared_ingredient(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    seed_medication(fk_db, item_seq=TYLENOL, item_name="타이레놀정500")
    seed_medication(fk_db, item_seq=FAMOTIDINE, item_name="파모티딘정")

    result = _check(fk_db, GEVORIN, FAMOTIDINE, UNKNOWN)

    assert result[GEVORIN] == [
        {
            "ingredient_code": "M040702",
            "ingredient_name": "아세트아미노펜",
            "with": {
                "item_seq": TYLENOL,
                "item_name": "타이레놀정500",
                "source": "saved",
                "same_product": False,
            },
        }
    ]
    assert [entry["with"]["same_product"] for entry in result[FAMOTIDINE]] == [True]
    assert result[UNKNOWN] == []


# Function Name: test_products_on_the_same_screen_overlap_as_batch
# Description: Two requested products that share an ingredient name each other as batch with the catalog name.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_products_on_the_same_screen_overlap_as_batch(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    seed_account(fk_db, "patient-a")

    result = _check(fk_db, GEVORIN, PANCOLD, FAMOTIDINE, GEVORIN)

    assert list(result) == [GEVORIN, PANCOLD, FAMOTIDINE]
    assert result[GEVORIN] == [
        {
            "ingredient_code": "M040702",
            "ingredient_name": "아세트아미노펜",
            "with": {
                "item_seq": PANCOLD,
                "item_name": "판콜에이내복액",
                "source": "batch",
                "same_product": False,
            },
        }
    ]
    assert [entry["with"]["item_seq"] for entry in result[PANCOLD]] == [GEVORIN]
    assert result[FAMOTIDINE] == []


# Function Name: test_batch_partner_already_saved_is_reported_only_as_saved
# Description: A requested product that is also an active saved product is named once, as saved.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_batch_partner_already_saved_is_reported_only_as_saved(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    seed_medication(fk_db, item_seq=TYLENOL, item_name="타이레놀정500")

    result = _check(fk_db, GEVORIN, TYLENOL)

    assert [
        (entry["with"]["item_seq"], entry["with"]["source"]) for entry in result[GEVORIN]
    ] == [(TYLENOL, "saved")]


# Function Name: test_stop_dated_today_ends_the_course_but_a_future_stop_does_not
# Description: A stop dated today leaves no dose day from today; a stop dated tomorrow keeps today.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_stop_dated_today_ends_the_course_but_a_future_stop_does_not(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    today = application_today()
    seed_medication(fk_db, item_seq=TYLENOL, stopped_on=today)

    assert _check(fk_db, GEVORIN)[GEVORIN] == []

    seed_medication(fk_db, item_seq=PANCOLD, stopped_on=today + timedelta(days=1))

    assert [entry["with"]["item_seq"] for entry in _check(fk_db, GEVORIN)[GEVORIN]] == [
        PANCOLD,
    ]


# Function Name: test_scheduled_replacement_pair_counts_once
# Description: A course changed from a future date keeps both rows active; the replacement is named once.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_scheduled_replacement_pair_counts_once(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    today = application_today()
    effective = today + timedelta(days=3)
    original = seed_medication(fk_db, item_seq=TYLENOL, item_name="타이레놀정500(이전)")
    replacement = seed_medication(
        fk_db,
        item_seq=TYLENOL,
        item_name="타이레놀정500(변경)",
        regimen_effective_from=effective,
    )
    original.stopped_on = effective
    original.superseded_by_id = replacement.id
    fk_db.commit()

    overlaps = _check(fk_db, GEVORIN)[GEVORIN]

    assert [entry["with"]["item_name"] for entry in overlaps] == ["타이레놀정500(변경)"]
    assert [entry["with"]["same_product"] for entry in _check(fk_db, TYLENOL)[TYLENOL]] == [
        True,
    ]


# Function Name: test_as_needed_without_duration_stays_active
# Description: An as-needed medicine saved long ago without a duration still counts.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_as_needed_without_duration_stays_active(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    seed_medication(
        fk_db,
        item_seq=TYLENOL,
        created_date=application_today() - timedelta(days=200),
        prescription_date=application_today() - timedelta(days=200),
        total_days="",
        daily_frequency="필요시",
        dosing_mode="as_needed",
    )

    assert [entry["with"]["item_seq"] for entry in _check(fk_db, GEVORIN)[GEVORIN]] == [
        TYLENOL,
    ]


# Function Name: test_ended_course_and_other_owner_are_ignored
# Description: A finished course and another owner's medicine never count.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_ended_course_and_other_owner_are_ignored(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    past = application_today() - timedelta(days=30)
    seed_medication(
        fk_db, item_seq=TYLENOL, created_date=past, prescription_date=past, total_days="7 days",
    )
    seed_medication(fk_db, patient_hash="patient-b", item_seq=PANCOLD)
    seed_medication(fk_db, item_seq=None, item_name="아세트아미노펜 직접 입력")

    assert _check(fk_db, GEVORIN)[GEVORIN] == []


# Function Name: test_overlaps_per_item_are_capped_at_ten
# Description: Names at most ten other products for one checked product.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_overlaps_per_item_are_capped_at_ten(fk_db: Session) -> None:
    _seed_catalog(fk_db)
    for index in range(12):
        item_seq = f"30000000{index:02d}"
        fk_db.add(
            _DrugApprovalInfo(
                item_seq=item_seq,
                item_name=f"아세트아미노펜제{index}",
                normalized_item_name=f"아세트아미노펜제{index}",
                main_ingredient="[M040702]아세트아미노펜",
                raw_json="{}",
            )
        )
        fk_db.commit()
        seed_medication(fk_db, item_seq=item_seq, item_name=f"아세트아미노펜제{index}")

    assert len(_check(fk_db, TYLENOL)[TYLENOL]) == 10


# Function Name: test_cap_counts_products_not_shared_ingredients
# Description: A combination product sharing two ingredients with each of twelve saved combinations names ten
#   products and keeps both ingredients of each, so no product is cut for having several shared ingredients.
# Parameters: fk_db (Session) is the test session. Returns: None.
def test_cap_counts_products_not_shared_ingredients(fk_db: Session) -> None:
    combination = "[M040702]아세트아미노펜|[M040535]카페인무수물"
    for index in range(13):
        item_seq = f"31000000{index:02d}"
        fk_db.add(
            _DrugApprovalInfo(
                item_seq=item_seq,
                item_name=f"복합감기약{index}",
                normalized_item_name=f"복합감기약{index}",
                main_ingredient=combination,
                raw_json="{}",
            )
        )
        fk_db.commit()
        if index:
            seed_medication(fk_db, item_seq=item_seq, item_name=f"복합감기약{index}")

    overlaps = _check(fk_db, "3100000000")["3100000000"]

    partners = {overlap["with"]["item_seq"] for overlap in overlaps}
    assert len(partners) == 10
    assert len(overlaps) == 20


# Function Name: test_request_accepts_only_numeric_product_numbers_and_known_fields
# Description: Enforces 1 to 50 product numbers of 1 to 32 digits and rejects extra fields.
# Parameters: None. Returns: None.
def test_request_accepts_only_numeric_product_numbers_and_known_fields() -> None:
    assert IngredientOverlapRequest(item_seqs=[TYLENOL]).patient_hash is None
    IngredientOverlapRequest(item_seqs=["1" * 32] * 50)
    for invalid in (
        {"item_seqs": []},
        {"item_seqs": [TYLENOL] * 51},
        {"item_seqs": [""]},
        {"item_seqs": ["1" * 33]},
        {"item_seqs": ["20000000A"]},
        {"item_seqs": [TYLENOL], "item_names": ["타이레놀"]},
    ):
        with pytest.raises(ValidationError):
            IngredientOverlapRequest(**invalid)


# Function Name: test_route_resolves_a_caregiver_to_the_callers_own_account
# Description: A linked caregiver who names the patient still gets the check against their own list, and nothing names the products in the log.
# Parameters: fk_db (Session) is the test session; caplog captures log records. Returns: None.
@pytest.mark.anyio
async def test_route_resolves_a_caregiver_to_the_callers_own_account(
    fk_db: Session,
    caplog: pytest.LogCaptureFixture,
) -> None:
    _seed_catalog(fk_db)
    caregiver = _principal("caregiver")
    seed_account(fk_db, caregiver.user_hash, "patient-linked")
    fk_db.add(
        _PatientCaregiverLink(
            patient_hash="patient-linked",
            caregiver_hash=caregiver.user_hash,
            linked=True,
        )
    )
    fk_db.commit()
    seed_medication(fk_db, patient_hash="patient-linked", item_seq=TYLENOL)
    seed_medication(fk_db, patient_hash=caregiver.user_hash, item_seq=FAMOTIDINE)

    with caplog.at_level(logging.DEBUG):
        response = await check_ingredient_overlap(
            request=IngredientOverlapRequest(
                patient_hash="patient-linked",
                item_seqs=[GEVORIN, FAMOTIDINE],
            ),
            principal=caregiver,
            authorization=AuthorizationControl(fk_db),
            check_ingredient_overlap_control=CheckIngredientOverlap(fk_db),
        )

    items = {item.item_seq: item.overlaps for item in response.items}
    assert items[GEVORIN] == []
    assert [overlap.with_.same_product for overlap in items[FAMOTIDINE]] == [True]
    assert all(
        TYLENOL not in record.getMessage() and GEVORIN not in record.getMessage()
        for record in caplog.records
    )
