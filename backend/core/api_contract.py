# 파일명: api_contract.py
# 역할: 프론트엔드와 백엔드의 API 계약 버전을 요청마다 확인한다.

from collections.abc import Awaitable, Callable

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse


API_CONTRACT_HEADER = "X-MedBuddy-Api-Contract"


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
