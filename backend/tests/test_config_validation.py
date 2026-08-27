# 파일명: test_config_validation.py
# 역할: 외부 API 주소와 제한 시간 환경설정이 서버 시작 전에 검증되는지 확인한다.

import unittest
from pathlib import Path
import sys

from pydantic import ValidationError

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from core.config import Settings


class ConfigValidationTest(unittest.TestCase):
    def test_http_public_data_endpoint_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                _env_file=None,
                GEMINI_API_KEY="test-gemini-key",
                PUBLIC_DATA_API_KEY="test-public-data-key",
                PILL_IMAGE_API_BASE_URL=(
                    "http://apis.data.go.kr/1471000/"
                    "MdcinGrnIdntfcInfoService03/getMdcinGrnIdntfcInfoList03"
                ),
            )

    def test_non_positive_timeout_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                _env_file=None,
                GEMINI_API_KEY="test-gemini-key",
                PUBLIC_DATA_API_KEY="test-public-data-key",
                PRESCRIPTION_OCR_TIMEOUT_SECONDS=0,
            )

    # 함수이름: test_invalid_application_time_zone_is_rejected
    # 함수역할:
    # - 존재하지 않는 시간대 이름이 서버 설정으로 사용되지 못하는지 검증한다.
    # 반환값:
    # - 없음
    def test_invalid_application_time_zone_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                _env_file=None,
                GEMINI_API_KEY="test-gemini-key",
                PUBLIC_DATA_API_KEY="test-public-data-key",
                APPLICATION_TIME_ZONE="Invalid/MedBuddy",
            )

    def test_trusted_hosts_are_normalized_without_wildcards(self) -> None:
        settings = Settings(
            _env_file=None,
            TRUSTED_HOSTS=" API.MEDBUDDY.PP.UA, localhost,localhost ",
        )

        self.assertEqual(
            settings.trusted_host_list,
            ["api.medbuddy.pp.ua", "localhost"],
        )

    def test_wildcard_trusted_host_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(_env_file=None, TRUSTED_HOSTS="*")

    def test_non_positive_chat_retention_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(_env_file=None, CHAT_MESSAGE_RETENTION_DAYS=0)


if __name__ == "__main__":
    unittest.main()
