# 파일명: application_clock.py
# 역할: 서버 실행 지역과 무관하게 MedBuddy의 날짜·시간 기준을 제공한다.

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from core.config import settings


# 함수이름: application_now
# 함수역할:
# - 환경설정에 지정된 서비스 시간대를 기준으로 현재 시각을 반환한다.
# 매개변수:
# - 없음.
# 반환값:
# - 시간대 정보가 포함된 현재 시각
def application_now() -> datetime:
    return datetime.now(ZoneInfo(settings.APPLICATION_TIME_ZONE))


# 함수이름: application_today
# 함수역할:
# - 복약 일정과 저장 일자 계산에 사용할 서비스 기준 오늘 날짜를 반환한다.
# 매개변수:
# - 없음.
# 반환값:
# - 서비스 시간대 기준 오늘 날짜
def application_today() -> date:
    return application_now().date()


# 함수이름: seconds_until_next_application_day
# 함수역할:
# - 서비스 시간대의 다음 자정까지 남은 초를 반환한다. 하루 단위 한도가 풀리는 시각을 Retry-After로 알릴 때 쓴다.
# 매개변수:
# - 없음.
# 반환값:
# - 1 이상의 남은 초
def seconds_until_next_application_day() -> int:
    now = application_now()
    midnight = datetime.combine(
        now.date() + timedelta(days=1), datetime.min.time(), tzinfo=now.tzinfo,
    )
    return max(1, int((midnight - now).total_seconds()))
