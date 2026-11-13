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
# 채팅 스트림의 종료 코드를 읽고 그에 맞춰 재연결을 조절하는 클라이언트가 보내는 기능 이름.
CHAT_CLOSE_CODES_FEATURE = "chat-close-codes"

# 요청 밖(작업자, 스크립트)에서는 항상 복용하는 날 기준으로 계산한다.
_client_schedules_by_dose_days: ContextVar[bool] = ContextVar(
    "client_schedules_by_dose_days", default=True,
)


# Function Name: record_client_features
# Description: Stores this connection's dose-day capability in request context so synchronous worker paths inherit it; undeclared clients retain legacy daily-within-course schedules.
# Parameters: connection (HTTPConnection) supplies HTTP/WebSocket feature headers.
# Returns: None; updates the request-local capability rather than a process-wide flag.
async def record_client_features(connection: HTTPConnection) -> None:
    _client_schedules_by_dose_days.set(
        client_declares_feature(connection, DOSE_DAYS_FEATURE)
    )


# Function Name: client_declares_feature
# Description: Splits the declared header into trimmed lowercase feature names and checks membership.
# Parameters: connection (HTTPConnection) supplies the header; feature (str) is the already-normalized capability to test.
# Returns: bool; a missing header does not declare nonempty features.
def client_declares_feature(connection: HTTPConnection, feature: str) -> bool:
    return feature in {
        declared.strip().lower()
        for declared in connection.headers.get(CLIENT_FEATURES_HEADER, "").split(",")
    }


# Function Name: client_schedules_by_dose_days
# Description: Reads whether this context should filter schedules to actual dose days rather than all active course days.
# Parameters: None.
# Returns: bool from the request ContextVar, whose default is True outside a context that sets it.
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
