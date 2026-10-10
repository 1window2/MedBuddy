# 파일명: api_contract.py
# 역할: 프론트엔드와 백엔드의 API 계약 버전을 요청마다 확인한다.

from collections.abc import Awaitable, Callable
from contextvars import ContextVar

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import HTTPConnection
from starlette.responses import JSONResponse


API_CONTRACT_HEADER = "X-MedBuddy-Api-Contract"
# 쉼표로 구분한 클라이언트 기능 목록. 계약 버전을 올리지 않고 추가된 동작을 그 동작을 아는
# 클라이언트에게만 적용할 때 쓴다.
CLIENT_FEATURES_HEADER = "X-MedBuddy-Client-Features"
# 매일 복용하지 않는 약을 복용하는 날에만 일정에 받는 클라이언트가 보내는 기능 이름.
DOSE_DAYS_FEATURE = "dose-days"

# 요청 밖(작업자, 스크립트)에서는 항상 복용하는 날 기준으로 계산한다.
_client_schedules_by_dose_days: ContextVar[bool] = ContextVar(
    "client_schedules_by_dose_days", default=True,
)


# 함수이름: record_client_features
# 함수역할:
# - 요청 헤더의 클라이언트 기능 목록을 읽어 이 요청의 일정 조회 방식을 정한다.
# - 0.2.1 이하 앱은 오늘 일정에 약이 없는 시간대의 알림을 서버에서 꺼 버리므로, 기능을 알리지
#   않은 클라이언트에게는 예전처럼 복용 기간 안의 약을 매일 돌려준다.
# - 스레드풀로 넘어가는 동기 경로에도 값이 전달되도록 비동기 의존성으로 둔다.
# 매개변수:
# - connection (HTTPConnection): HTTP 요청 또는 WebSocket 연결.
# 반환값:
# - 없음.
async def record_client_features(connection: HTTPConnection) -> None:
    features = {
        feature.strip().lower()
        for feature in connection.headers.get(CLIENT_FEATURES_HEADER, "").split(",")
    }
    _client_schedules_by_dose_days.set(DOSE_DAYS_FEATURE in features)


# 함수이름: client_schedules_by_dose_days
# 함수역할:
# - 현재 요청의 클라이언트가 복용하는 날에만 약을 받는지 알려 준다.
# 매개변수:
# - 없음.
# 반환값:
# - 복용하는 날 기준이면 True. 요청 밖에서는 항상 True.
def client_schedules_by_dose_days() -> bool:
    return _client_schedules_by_dose_days.get()


# 클래스명: ApiContractMiddleware
# 역할:
# - MedBuddy API 요청과 응답에 계약 버전 협상 규칙을 적용한다.
# 주요 책임:
# - 새 클라이언트가 보낸 계약 버전이 서버와 다르면 명확한 오류를 반환한다.
# - 모든 API 응답에 서버 계약 버전을 표시한다.
# - 계약 헤더가 없는 구형 클라이언트는 베타 호환을 위해 계속 허용한다.
# 속성:
# - contract_version (str): 응답에 표시하고 클라이언트와 비교할 서버 계약 버전.
class ApiContractMiddleware(BaseHTTPMiddleware):
    # 함수이름: __init__
    # 함수역할:
    # - 하위 애플리케이션을 연결하고 요청마다 비교할 API 계약 버전을 보관한다.
    # 매개변수:
    # - app (object): 미들웨어가 감쌀 하위 ASGI 애플리케이션.
    # - contract_version (str): 서버가 지원하는 API 계약 버전.
    # 반환값:
    # - 없음.
    def __init__(self, app: object, contract_version: str) -> None:
        super().__init__(app)
        self.contract_version = contract_version

    # 함수이름: dispatch
    # 함수역할:
    # - 버전이 다른 /api/v1 요청은 426으로 거부하고, 모든 응답에 서버 계약 버전 헤더를 추가한다.
    # 매개변수:
    # - request (Request): 클라이언트 계약 헤더를 확인할 HTTP 요청.
    # - call_next (Callable[[Request], Awaitable[Response]]): 다음 요청 처리기로 전달하는 비동기 콜백.
    # 반환값:
    # - 계약 불일치 오류 응답 또는 하위 처리 결과; 계약 헤더가 없는 기존 요청은 허용한다.
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        requested_version = request.headers.get(API_CONTRACT_HEADER, "").strip()
        if (
            request.url.path.startswith("/api/v1/")
            and requested_version
            and requested_version != self.contract_version
        ):
            response = JSONResponse(
                status_code=426,
                content={
                    "detail": "MedBuddy API contract version is incompatible.",
                    "expected_contract": self.contract_version,
                },
            )
        else:
            response = await call_next(request)
        response.headers[API_CONTRACT_HEADER] = self.contract_version
        return response
