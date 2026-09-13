# File Name: test_link_patient_caregiver_control.py
# Role: Regression coverage for patient link codes, participant authorization, caregiver
#   aliases, and unlink cleanup.

import sys
import unittest
from datetime import UTC, datetime, timedelta
from pathlib import Path

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from controls.link_patient_caregiver_control import LinkPatientCaregiver  # noqa: E402
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


# 클래스명: LinkPatientCaregiverTest
# 역할: 환자 코드 발급·소모와 연동별 환자 선택, 권한 및 별칭 관리를 검증하는 테스트 모음이다.
# 주요 책임:
# - 보호자가 저장한 별칭을 연동 목록에서도 유지하고 빈 별칭으로 지울 수 있는지 검증한다.
# - 연동에 참여하지 않은 다른 보호자의 별칭 변경을 404로 거절하는지 검증한다.
# 속성:
# - engine (Engine): 격리 인메모리 SQLite 엔진.
# - db (Session): 이 테스트의 DB 상태만 보관하는 SQLAlchemy 세션.
# - control (LinkPatientCaregiver): 운영 상태와 분리하여 검증할 유스케이스 control.
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


if __name__ == "__main__":
    unittest.main()
