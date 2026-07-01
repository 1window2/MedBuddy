# 파일명: test_patient_guardian_link_control.py
# 역할: 환자-보호자 연동 코드 생성, 등록, 해제 control을 검증한다.

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

from controls.patient_guardian_link_control import PatientGuardianLinkControl  # noqa: E402
from core.database import Base  # noqa: E402
from entities.patient_guardian_link_entity import (  # noqa: E402
    _PatientGuardianLink,
    _PatientLinkCode,
)
from entities.patient_hash_entity import (  # noqa: E402
    DEFAULT_PATIENT_HASH,
    PATIENT_LINK_CODE_LENGTH,
)


def utc_now() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


class PatientGuardianLinkControlTest(unittest.TestCase):
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
        self.control = PatientGuardianLinkControl(self.db)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_patient_code_creation_persists_share_code(self) -> None:
        response = self.control.request_patient_code("patient-a")

        self.assertTrue(response["success"])
        data = response["data"]
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(len(data["patient_code"]), PATIENT_LINK_CODE_LENGTH)

        link_code = (
            self.db.query(_PatientLinkCode)
            .filter(_PatientLinkCode.patient_code == data["patient_code"])
            .first()
        )
        self.assertIsNotNone(link_code)
        self.assertFalse(link_code.used)

    def test_diagram_patient_code_wrapper_delegates_to_code_creation(self) -> None:
        response = self.control.createPatientCode("patient-a")

        self.assertTrue(response["success"])
        data = response["data"]
        self.assertEqual(data["patient_hash"], "patient-a")
        self.assertEqual(len(data["patient_code"]), PATIENT_LINK_CODE_LENGTH)

    def test_register_patient_code_creates_scoped_link(self) -> None:
        code_response = self.control.request_patient_code("patient-a")
        patient_code = code_response["data"]["patient_code"]

        link_response = self.control.register_patient_code("guardian-a", patient_code)

        self.assertTrue(link_response["success"])
        link_data = link_response["data"]
        self.assertEqual(link_data["patient_hash"], "patient-a")
        self.assertEqual(link_data["guardian_hash"], "guardian-a")
        self.assertTrue(link_data["linked"])
        self.assertEqual(
            self.control.get_linked_patient_hash("guardian-a"),
            "patient-a",
        )

        patient_links = self.control.request_link_page("patient-a")
        guardian_links = self.control.request_link_page("guardian-a")
        self.assertEqual(len(patient_links["data"]), 1)
        self.assertEqual(len(guardian_links["data"]), 1)

        used_code = (
            self.db.query(_PatientLinkCode)
            .filter(_PatientLinkCode.patient_code == patient_code)
            .first()
        )
        self.assertTrue(used_code.used)
        self.assertEqual(used_code.guardian_hash, "guardian-a")

    def test_linked_patient_hash_honors_requested_patient(self) -> None:
        patient_a_code = self.control.request_patient_code("patient-a")
        patient_b_code = self.control.request_patient_code("patient-b")
        self.control.register_patient_code(
            "guardian-a",
            patient_a_code["data"]["patient_code"],
        )
        self.control.register_patient_code(
            "guardian-a",
            patient_b_code["data"]["patient_code"],
        )

        linked_patient_hash = self.control.get_linked_patient_hash(
            "guardian-a",
            "patient-b",
        )

        self.assertEqual(linked_patient_hash, "patient-b")

    def test_linked_patient_hash_honors_requested_default_patient(self) -> None:
        patient_a_code = self.control.request_patient_code("patient-a")
        default_patient_code = self.control.request_patient_code(DEFAULT_PATIENT_HASH)
        self.control.register_patient_code(
            "guardian-a",
            patient_a_code["data"]["patient_code"],
        )
        self.control.register_patient_code(
            "guardian-a",
            default_patient_code["data"]["patient_code"],
        )

        linked_patient_hash = self.control.get_linked_patient_hash(
            "guardian-a",
            DEFAULT_PATIENT_HASH,
        )

        self.assertEqual(linked_patient_hash, DEFAULT_PATIENT_HASH)

    def test_patient_code_cannot_be_registered_twice(self) -> None:
        code_response = self.control.request_patient_code("patient-a")
        patient_code = code_response["data"]["patient_code"]

        self.control.register_patient_code("guardian-a", patient_code)

        with self.assertRaises(HTTPException) as context:
            self.control.register_patient_code("guardian-b", patient_code)

        self.assertIn(context.exception.status_code, {404, 409})

    def test_invalid_or_expired_patient_code_is_rejected(self) -> None:
        expired_code = _PatientLinkCode(
            patient_hash="patient-a",
            patient_code="EXPIRED1",
            expires_at=utc_now() - timedelta(minutes=1),
        )
        self.db.add(expired_code)
        self.db.commit()

        with self.assertRaises(HTTPException) as context:
            self.control.register_patient_code("guardian-a", "EXPIRED1")

        self.assertEqual(context.exception.status_code, 404)

    def test_unlink_requires_participating_user_hash(self) -> None:
        code_response = self.control.request_patient_code("patient-a")
        link_response = self.control.register_patient_code(
            "guardian-a",
            code_response["data"]["patient_code"],
        )
        link_id = link_response["data"]["id"]

        with self.assertRaises(HTTPException) as context:
            self.control.request_unlink(link_id, "stranger")
        self.assertEqual(context.exception.status_code, 404)

        unlink_response = self.control.deletePatientGuardianLink(link_id, "guardian-a")

        self.assertTrue(unlink_response["success"])
        self.assertFalse(unlink_response["data"]["linked"])
        link_row = self.db.get(_PatientGuardianLink, link_id)
        self.assertFalse(link_row.linked)

        with self.assertRaises(HTTPException) as missing_context:
            self.control.get_linked_patient_hash("guardian-a")
        self.assertEqual(missing_context.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
