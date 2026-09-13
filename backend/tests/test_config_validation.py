# 파일명: test_config_validation.py
# 역할: 서버 설정의 HTTPS, 양수 제한, 시간대 및 신뢰 호스트 검증을 수행한다.

import unittest
from pathlib import Path
import sys

from pydantic import ValidationError

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from core.config import Settings


# 클래스명: ConfigValidationTest
# 역할: 외부 통신과 보관 정책의 잘못된 설정을 거절하는 구성 검증 테스트 모음이다.
# 주요 책임:
# - 공공 데이터 API 주소가 HTTP이면 ValidationError로 거절하는지 검증한다.
# - 존재하지 않는 시간대 이름이 서버 설정으로 사용되지 못하는지 검증한다.
# - 0 이하 채팅 보관 기간을 ValidationError로 거절하는지 검증한다.
class ConfigValidationTest(unittest.TestCase):
    # 함수이름: test_http_public_data_endpoint_is_rejected
    # 함수역할:
    # - 공공 데이터 API 주소가 HTTP이면 ValidationError로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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

    # 함수이름: test_non_positive_timeout_is_rejected
    # 함수역할:
    # - 0 이하 요청 제한 시간을 서버 설정으로 허용하지 않는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
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
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_invalid_application_time_zone_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(
                _env_file=None,
                GEMINI_API_KEY="test-gemini-key",
                PUBLIC_DATA_API_KEY="test-public-data-key",
                APPLICATION_TIME_ZONE="Invalid/MedBuddy",
            )

    # Function Name: test_trusted_hosts_are_normalized_without_wildcards
    # Description:
    # - Normalizes explicit trusted hosts into the expected hostname list without
    #   introducing wildcards.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_trusted_hosts_are_normalized_without_wildcards(self) -> None:
        settings = Settings(
            _env_file=None,
            TRUSTED_HOSTS=" API.MEDBUDDY.PP.UA, localhost,localhost ",
        )

        self.assertEqual(
            settings.trusted_host_list,
            ["api.medbuddy.pp.ua", "localhost"],
        )

    # Function Name: test_wildcard_trusted_host_is_rejected
    # Description:
    # - Rejects wildcard trusted hosts instead of permitting arbitrary Host headers.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def test_wildcard_trusted_host_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(_env_file=None, TRUSTED_HOSTS="*")

    # 함수이름: test_non_positive_chat_retention_is_rejected
    # 함수역할:
    # - 0 이하 채팅 보관 기간을 ValidationError로 거절하는지 검증한다.
    # 매개변수:
    # - 없음.
    # 반환값:
    # - 없음 (None).
    def test_non_positive_chat_retention_is_rejected(self) -> None:
        with self.assertRaises(ValidationError):
            Settings(_env_file=None, CHAT_MESSAGE_RETENTION_DAYS=0)


if __name__ == "__main__":
    unittest.main()
