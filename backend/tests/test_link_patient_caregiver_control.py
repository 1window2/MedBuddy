# File Name: test_link_patient_caregiver_control.py
# Role: Regression coverage for patient link codes, participant authorization, caregiver
#   aliases, and unlink cleanup.

import sys
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
from core.config import settings  # noqa: E402
from core.database import Base  # noqa: E402
from entities.caregiver_notification_entity import _CaregiverNotification  # noqa: E402
from entities.patient_caregiver_link_entity import (  # noqa: E402
    _PatientCaregiverLink,
    _PatientLinkCode,
)
from entities.patient_hash_entity import (  # noqa: E402
    DEFAULT_PATIENT_HASH,
    PATIENT_LINK_CODE_LENGTH,
)


# Function Name: utc_now
# Description:
# - Returns the current UTC instant without timezone metadata to match stored link-code
#   timestamps.
# Parameters:
# - None.
# Returns:
# - datetime: Current UTC datetime stored without timezone metadata.
def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


# Class Name: LinkPatientCaregiverTest
# Role: Tests patient-code issuance, link authorization, participant aliases, and account link limits.
# Responsibilities:
# - Verify alias privacy, code consumption and invalidation, and account locking around registration and unlinking.
# Attributes:
# - engine (Engine): isolated SQLite engine. db (Session): test session. control (LinkPatientCaregiver): link control under test.
class LinkPatientCaregiverTest(unittest.TestCase):
    # Function Name: setUp
    # Description:
    # - Creates an isolated account/link database and patient-caregiver linking control.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
        )
        Base.metadata.create_all(bind=self.engine)
        session_factory = sessionmaker(
            autocommit=False,
            autoflush=False,
            bind=self.engine,
        )
        self.db = session_factory()
        self.control = LinkPatientCaregiver(self.db)

    # Function Name: tearDown
    # Description:
    # - Closes the link-test session and disposes its database engine.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    # Function Name: test_patient_code_creation_persists_share_code
    # Description:
    # - Persists an unused code of the required length with the correct patient and a UTC
    #   expiry roughly fifteen minutes ahead.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_patient_code_creation_persists_share_code(self) -> None:
        response = self.control.generatePatientHash("patient-a")

        self.assertTrue(response["success"])
        data = response["data"]
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(len(data["patient_code"]), PATIENT_LINK_CODE_LENGTH)
        expires_at = datetime.fromisoformat(data["expires_at"])
        self.assertEqual(expires_at.tzinfo, UTC)
        remaining = expires_at - datetime.now(UTC)
        self.assertGreater(remaining, timedelta(minutes=14))
        self.assertLessEqual(remaining, timedelta(minutes=15))

        link_code = (
            self.db.query(_PatientLinkCode)
            .filter(_PatientLinkCode.patient_code == data["patient_code"])
            .first()
        )
        self.assertIsNotNone(link_code)
        self.assertFalse(link_code.used)

    # Function Name: test_diagram_patient_code_wrapper_delegates_to_code_creation
    # Description:
    # - Requires the UML wrapper to return the same successful patient-code contract as the
    #   underlying creation operation.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_diagram_patient_code_wrapper_delegates_to_code_creation(self) -> None:
        response = self.control.generatePatientHash("patient-a")

        self.assertTrue(response["success"])
        data = response["data"]
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(len(data["patient_code"]), PATIENT_LINK_CODE_LENGTH)

    # Function Name: test_register_patient_code_creates_scoped_link
    # Description:
    # - Creates an active patient-caregiver link visible to both participants and consumes
    #   the code for that caregiver.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_register_patient_code_creates_scoped_link(self) -> None:
        code_response = self.control.generatePatientHash("patient-a")
        patient_code = code_response["data"]["patient_code"]

        link_response = self.control.requestPatientCaregiverLink("guardian-a", patient_code)

        self.assertTrue(link_response["success"])
        link_data = link_response["data"]
        self.assertEqual(link_data["patient_hash"], "patient-a")
        self.assertEqual(link_data["guardian_hash"], "guardian-a")
        self.assertTrue(link_data["linked"])
        self.assertEqual(
            self.control.getLinkedPatientHash("guardian-a"),
            "patient-a",
        )

        patient_links = self.control.requestLinkScreen("patient-a")
        guardian_links = self.control.requestLinkScreen("guardian-a")
        self.assertEqual(len(patient_links["data"]), 1)
        self.assertEqual(len(guardian_links["data"]), 1)

        used_code = (
            self.db.query(_PatientLinkCode)
            .filter(_PatientLinkCode.patient_code == patient_code)
            .first()
        )
        self.assertTrue(used_code.used)
        self.assertEqual(used_code.caregiver_hash, "guardian-a")

    # Function Name: test_linked_patient_hash_honors_requested_patient
    # Description:
    # - Resolves the explicitly requested linked patient when a caregiver has multiple
    #   links.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_linked_patient_hash_honors_requested_patient(self) -> None:
        patient_a_code = self.control.generatePatientHash("patient-a")
        patient_b_code = self.control.generatePatientHash("patient-b")
        self.control.requestPatientCaregiverLink(
            "guardian-a",
            patient_a_code["data"]["patient_code"],
        )
        self.control.requestPatientCaregiverLink(
            "guardian-a",
            patient_b_code["data"]["patient_code"],
        )

        linked_patient_hash = self.control.getLinkedPatientHash(
            "guardian-a",
            "patient-b",
        )

        self.assertEqual(linked_patient_hash, "patient-b")

    # Function Name: test_linked_patient_hash_honors_requested_default_patient
    # Description:
    # - Honors an explicitly requested default patient instead of selecting another linked
    #   patient.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_linked_patient_hash_honors_requested_default_patient(self) -> None:
        patient_a_code = self.control.generatePatientHash("patient-a")
        default_patient_code = self.control.generatePatientHash(DEFAULT_PATIENT_HASH)
        self.control.requestPatientCaregiverLink(
            "guardian-a",
            patient_a_code["data"]["patient_code"],
        )
        self.control.requestPatientCaregiverLink(
            "guardian-a",
            default_patient_code["data"]["patient_code"],
        )

        linked_patient_hash = self.control.getLinkedPatientHash(
            "guardian-a",
            DEFAULT_PATIENT_HASH,
        )

        self.assertEqual(linked_patient_hash, DEFAULT_PATIENT_HASH)

    # Function Name: test_patient_code_cannot_be_registered_twice
    # Description:
    # - Rejects reuse of an already consumed patient code with a not-found or conflict
    #   response.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_patient_code_cannot_be_registered_twice(self) -> None:
        code_response = self.control.generatePatientHash("patient-a")
        patient_code = code_response["data"]["patient_code"]

        self.control.requestPatientCaregiverLink("guardian-a", patient_code)

        with self.assertRaises(HTTPException) as context:
            self.control.requestPatientCaregiverLink("guardian-b", patient_code)

        self.assertIn(context.exception.status_code, {404, 409})

    # Function Name: test_invalid_or_expired_patient_code_is_rejected
    # Description:
    # - Rejects invalid or expired patient codes with HTTP 404.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_invalid_or_expired_patient_code_is_rejected(self) -> None:
        expired_code = _PatientLinkCode(
            patient_hash="patient-a",
            patient_code="EXPIRED1",
            expires_at=utc_now() - timedelta(minutes=1),
        )
        self.db.add(expired_code)
        self.db.commit()

        with self.assertRaises(HTTPException) as context:
            self.control.requestPatientCaregiverLink("guardian-a", "EXPIRED1")

        self.assertEqual(context.exception.status_code, 404)

    # Function Name: test_unlink_requires_participating_user_hash
    # Description:
    # - Rejects unlink attempts by outsiders and makes a participant's successful unlink
    #   remove subsequent linked-patient access.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlink_requires_participating_user_hash(self) -> None:
        code_response = self.control.generatePatientHash("patient-a")
        link_response = self.control.requestPatientCaregiverLink(
            "guardian-a",
            code_response["data"]["patient_code"],
        )
        link_id = link_response["data"]["id"]

        with self.assertRaises(HTTPException) as context:
            self.control.requestUnlink(link_id, "stranger")
        self.assertEqual(context.exception.status_code, 404)

        unlink_response = self.control.requestUnlink(link_id, "guardian-a")

        self.assertTrue(unlink_response["success"])
        self.assertFalse(unlink_response["data"]["linked"])
        link_row = self.db.get(_PatientCaregiverLink, link_id)
        self.assertFalse(link_row.linked)

        with self.assertRaises(HTTPException) as missing_context:
            self.control.getLinkedPatientHash("guardian-a")
        self.assertEqual(missing_context.exception.status_code, 404)

    # Function Name: test_unlink_revokes_caregiver_notification_setting
    # Description:
    # - Removes caregiver notification settings when the associated patient link is revoked.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlink_revokes_caregiver_notification_setting(self) -> None:
        code_response = self.control.generatePatientHash("patient-a")
        link_response = self.control.requestPatientCaregiverLink(
            "guardian-a",
            code_response["data"]["patient_code"],
        )
        setting = _CaregiverNotification(
            caregiver_hash="guardian-a",
            patient_hash="patient-a",
            enabled=True,
            alert_option="enable",
        )
        self.db.add(setting)
        self.db.commit()

        self.control.requestUnlink(
            link_response["data"]["id"],
            "guardian-a",
        )

        self.assertEqual(self.db.query(_CaregiverNotification).count(), 0)

    # 함수이름: test_caregiver_patient_alias_is_shared_by_link_lookup
    # 함수역할:
    # - 보호자가 저장한 별칭을 연동 목록에서도 유지하고 빈 별칭으로 지울 수 있는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_caregiver_patient_alias_is_shared_by_link_lookup(self) -> None:
        """보호자가 저장한 별칭이 서버 연동 조회에서도 유지되는지 검증한다."""
        code_response = self.control.generatePatientHash("patient-a")
        link_response = self.control.requestPatientCaregiverLink(
            "guardian-a",
            code_response["data"]["patient_code"],
        )
        self.assertIsNone(link_response["data"]["patient_alias"])

        alias_response = self.control.updatePatientAlias(
            link_response["data"]["id"],
            "guardian-a",
            "  어머니  ",
        )
        links_response = self.control.requestLinkScreen("guardian-a")

        self.assertEqual(alias_response["data"]["patient_alias"], "어머니")
        self.assertEqual(links_response["data"][0]["patient_alias"], "어머니")

        cleared_response = self.control.updatePatientAlias(
            link_response["data"]["id"],
            "guardian-a",
            "",
        )
        self.assertEqual(cleared_response["data"]["patient_alias"], "")

    # 함수이름: test_patient_alias_update_rejects_another_caregiver
    # 함수역할:
    # - 연동에 참여하지 않은 다른 보호자의 별칭 변경을 404로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_patient_alias_update_rejects_another_caregiver(self) -> None:
        """다른 보호자가 환자 별칭을 변경하지 못하는지 검증한다."""
        code_response = self.control.generatePatientHash("patient-a")
        link_response = self.control.requestPatientCaregiverLink(
            "guardian-a",
            code_response["data"]["patient_code"],
        )

        with self.assertRaises(HTTPException) as context:
            self.control.updatePatientAlias(
                link_response["data"]["id"],
                "guardian-b",
                "잘못된 별칭",
            )

        self.assertEqual(context.exception.status_code, 404)


    # Function Name: test_patient_caregiver_alias_is_independent_and_persistent
    # Description:
    # - Persist each participant's independent alias across reads and allow clearing it.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_patient_caregiver_alias_is_independent_and_persistent(self) -> None:
        code = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        link = self.control.requestPatientCaregiverLink("guardian-a", code)["data"]
        self.assertIsNone(link["caregiver_alias"])
        self.control.updatePatientAlias(link["id"], "guardian-a", "어머니")
        result = self.control.update_caregiver_alias(link["id"], "patient-a", "  우리  딸  ")["data"]
        self.assertEqual(result["caregiver_alias"], "우리 딸")
        # 보호자가 환자에게 붙인 별칭은 환자에게 돌려주지 않는다.
        self.assertIsNone(result["patient_alias"])
        listed = self.control.requestLinkScreen("patient-a")["data"][0]
        self.assertEqual(listed["caregiver_alias"], "우리 딸")
        self.assertIsNone(listed["patient_alias"])
        # 환자가 보호자에게 붙인 별칭도 보호자에게 돌려주지 않는다.
        guardian_view = self.control.requestLinkScreen("guardian-a")["data"][0]
        self.assertEqual(guardian_view["patient_alias"], "어머니")
        self.assertIsNone(guardian_view["caregiver_alias"])
        saved = self.control.updatePatientAlias(link["id"], "guardian-a", "어머니")["data"]
        self.assertIsNone(saved["caregiver_alias"])
        result = self.control.update_caregiver_alias(link["id"], "patient-a", "  ")["data"]
        self.assertEqual(result["caregiver_alias"], "")
        self.assertIsNone(result["patient_alias"])
        self.assertEqual(
            self.control.requestLinkScreen("guardian-a")["data"][0]["patient_alias"],
            "어머니",
        )

    # Function Name: test_unlink_response_hides_the_other_participants_alias
    # Description:
    # - Expose only the unlinking participant's own alias in the unlink response.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlink_response_hides_the_other_participants_alias(self) -> None:
        code = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        link = self.control.requestPatientCaregiverLink("guardian-a", code)["data"]
        self.control.updatePatientAlias(link["id"], "guardian-a", "어머니")
        self.control.update_caregiver_alias(link["id"], "patient-a", "딸")
        removed = self.control.requestUnlink(link["id"], "patient-a")["data"]
        self.assertEqual(removed["caregiver_alias"], "딸")
        self.assertIsNone(removed["patient_alias"])

    # Function Name: test_link_is_refused_once_an_account_holds_the_maximum
    # Description:
    # - Reject links above either account limit with HTTP 409 without consuming the code, and allow linking again after a link is removed.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_link_is_refused_once_an_account_holds_the_maximum(self) -> None:
        with patch.object(settings, "PATIENT_CAREGIVER_LINK_MAX_PER_ACCOUNT", 2):
            links = [
                self.control.requestPatientCaregiverLink(
                    guardian,
                    self.control.generatePatientHash("patient-a")["data"]["patient_code"],
                )["data"]
                for guardian in ("guardian-a", "guardian-b")
            ]
            code = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
            with self.assertRaises(HTTPException) as refused:
                self.control.requestPatientCaregiverLink("guardian-c", code)
            # 한 보호자가 맡는 환자 수도 같은 한도를 따른다.
            self.control.requestPatientCaregiverLink(
                "guardian-a",
                self.control.generatePatientHash("patient-b")["data"]["patient_code"],
            )
            with self.assertRaises(HTTPException) as caregiver_refused:
                self.control.requestPatientCaregiverLink(
                    "guardian-a",
                    self.control.generatePatientHash("patient-c")["data"]["patient_code"],
                )
            # 거절된 요청은 코드를 쓰지 않는다.
            self.assertFalse(
                self.db.query(_PatientLinkCode).filter_by(patient_code=code).one().used
            )
            self.control.requestUnlink(links[1]["id"], "patient-a")
            # 해제는 남은 코드를 막으므로 새 코드로 연동한다.
            accepted = self.control.requestPatientCaregiverLink(
                "guardian-c",
                self.control.generatePatientHash("patient-a")["data"]["patient_code"],
            )

        self.assertEqual(refused.exception.status_code, 409)
        self.assertEqual(caregiver_refused.exception.status_code, 409)
        self.assertTrue(accepted["success"])

    # Function Name: test_registration_counts_links_under_both_account_locks
    # Description:
    # - Count active links and reread the code only after locking both participant accounts.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_registration_counts_links_under_both_account_locks(self) -> None:
        import controls.link_patient_caregiver_control as module

        events: list[object] = []
        real_lock = module.lock_account_operations
        real_count = self.control.link_repository.list_active_for_patient

        # Function Name: recording_lock
        # Description:
        # - Records the accounts locked before invoking the real account-operation lock.
        # Parameters:
        # - db: Session; link operation session.
        # - user_hashes: Iterable[str]; accounts whose lock ordering is checked.
        # Returns:
        # - None.
        def recording_lock(db, user_hashes):
            events.append(("lock", frozenset(user_hashes)))
            real_lock(db, user_hashes)

        # Function Name: recording_count
        # Description:
        # - Records when link counting occurs and delegates to the real patient-link count.
        # Parameters:
        # - patient_hash: str; patient whose active links are counted.
        # Returns:
        # - int; current link count.
        def recording_count(patient_hash):
            events.append("count")
            return real_count(patient_hash)

        code = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        with patch.object(module, "lock_account_operations", recording_lock), patch.object(
            self.control.link_repository, "list_active_for_patient", recording_count
        ):
            self.control.requestPatientCaregiverLink("guardian-a", code)

        self.assertEqual(events[0], ("lock", frozenset({"patient-a", "guardian-a"})))
        self.assertIn("count", events[1:])

    # Function Name: test_unlink_runs_under_both_account_locks
    # Description:
    # - Reread and remove the link under both account locks, returning HTTP 404 when another request already removed it.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlink_runs_under_both_account_locks(self) -> None:
        import controls.link_patient_caregiver_control as module

        code = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        link = self.control.requestPatientCaregiverLink("guardian-a", code)["data"]
        locks: list[frozenset[str]] = []
        real_lock = module.lock_account_operations

        # Function Name: recording_lock
        # Description:
        # - Records each account set before invoking the real lock during unlink.
        # Parameters:
        # - db: Session; unlink session.
        # - user_hashes: Iterable[str]; linked participant accounts.
        # Returns:
        # - None.
        def recording_lock(db, user_hashes):
            locks.append(frozenset(user_hashes))
            real_lock(db, user_hashes)

        with patch.object(module, "lock_account_operations", recording_lock):
            self.control.requestUnlink(link["id"], "guardian-a")
            with self.assertRaises(HTTPException) as gone:
                self.control.requestUnlink(link["id"], "patient-a")

        self.assertEqual(locks, [frozenset({"patient-a", "guardian-a"})])
        self.assertEqual(gone.exception.status_code, 404)

    # Function Name: test_unlink_invalidates_codes_issued_before_it
    # Description:
    # - Invalidate codes issued before unlinking while allowing a freshly issued code to establish a new link.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_unlink_invalidates_codes_issued_before_it(self) -> None:
        earlier = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        redeemed = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        spare = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        link = self.control.requestPatientCaregiverLink("guardian-a", redeemed)["data"]
        self.control.requestUnlink(link["id"], "patient-a")

        with self.assertRaises(HTTPException) as refused:
            self.control.requestPatientCaregiverLink("guardian-a", earlier)
        # 해제된 사람이 다른 계정으로 남은 코드를 써도 연동되지 않는다.
        with self.assertRaises(HTTPException) as other_account:
            self.control.requestPatientCaregiverLink("guardian-a-second", spare)
        self.assertEqual(other_account.exception.status_code, 404)
        fresh = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        relinked = self.control.requestPatientCaregiverLink("guardian-a", fresh)

        self.assertEqual(refused.exception.status_code, 404)
        self.assertTrue(relinked["success"])

    # 함수이름: test_caregiver_alias_rejects_nonowners_and_inactive_links
    # 함수역할: 다른 환자, 상대 보호자, 없는 연결 및 해제된 연결의 별칭 변경을 차단한다.
    # 매개변수: 없음. 반환값: 없음.
    def test_caregiver_alias_rejects_nonowners_and_inactive_links(self) -> None:
        code = self.control.generatePatientHash("patient-a")["data"]["patient_code"]
        link = self.control.requestPatientCaregiverLink("guardian-a", code)["data"]
        for user in ("patient-b", "guardian-a"):
            with self.subTest(user=user), self.assertRaises(HTTPException) as error:
                self.control.update_caregiver_alias(link["id"], user, "별칭")
            self.assertEqual(error.exception.status_code, 404)
        with self.assertRaises(HTTPException) as error:
            self.control.update_caregiver_alias(link["id"] + 1000, "patient-a", "별칭")
        self.assertEqual(error.exception.status_code, 404)
        self.control.requestUnlink(link["id"], "patient-a")
        with self.assertRaises(HTTPException) as error:
            self.control.update_caregiver_alias(link["id"], "patient-a", "별칭")
        self.assertEqual(error.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
