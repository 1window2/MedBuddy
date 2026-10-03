# File Name: request_limits.py
# Role: Rejects oversized HTTP request bodies before multipart or JSON parsing.

from collections.abc import Mapping

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send


# Class Name: _RequestBodyTooLarge
# Role:
# - Signals that a streamed request has exceeded its byte budget.
# Responsibilities:
# - Unwind downstream body reads so middleware can emit a generic HTTP 413 response.
class _RequestBodyTooLarge(Exception):
    """Internal control-flow signal raised while receiving a request body."""


# Class Name: RequestBodyLimitMiddleware
# Role:
# - Enforces path-specific and default request-body limits before parsing.
# Responsibilities:
# - Reject declared oversized requests before reading their body.
# - Count chunked request bytes while Starlette consumes the ASGI stream.
# - Return a generic 413 response without exposing request contents.
# Attributes:
# - app (ASGIApp): Downstream application.
# - limits (dict[str, int]): Exact-path byte limits.
# - default_limit (int | None): Fallback budget; None leaves unmatched paths unrestricted.
class RequestBodyLimitMiddleware:
    """Applies request byte limits before Starlette buffers multipart or JSON data."""

    # Function Name: __init__
    # Description:
    # - Validate positive byte budgets and retain a copy of path-specific limits for the wrapped application.
    # Parameters:
    # - app (ASGIApp): Downstream ASGI application wrapped by this middleware.
    # - limits (Mapping[str, int]): Exact request paths mapped to maximum body bytes.
    # - default_limit (int | None): Fallback maximum bytes for unmatched paths, or None for no fallback limit.
    # Returns:
    # - None; invalid limits raise ValueError.
    def __init__(
        self,
        app: ASGIApp,
        *,
        limits: Mapping[str, int],
        default_limit: int | None = None,
    ) -> None:
        if any(limit <= 0 for limit in limits.values()):
            raise ValueError("Request body limits must be positive.")
        if default_limit is not None and default_limit <= 0:
            raise ValueError("The default request body limit must be positive.")
        self.app = app
        self.limits = dict(limits)
        self.default_limit = default_limit

    # Function Name: __call__
    # Description:
    # - For body-bearing HTTP methods, reject excessive Content-Length or count streamed chunks before delegating body parsing.
    # Parameters:
    # - scope (Scope): ASGI connection metadata, including request path and headers.
    # - receive (Receive): ASGI callable that reads the next inbound message.
    # - send (Send): ASGI callable that emits outbound response messages.
    # Returns:
    # - None; delegates the request or sends HTTP 413 when the byte budget is exceeded.
    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        """Delegates bounded requests and rejects bodies that exceed their path limit."""

        if scope["type"] != "http" or scope.get("method") not in {
            "DELETE",
            "POST",
            "PUT",
            "PATCH",
        }:
            await self.app(scope, receive, send)
            return

        limit = self.limits.get(scope.get("path", ""), self.default_limit)
        if limit is None:
            await self.app(scope, receive, send)
            return

        content_length = self._content_length(scope)
        if content_length is not None and content_length > limit:
            await self._send_rejection(scope, receive, send)
            return

        received_bytes = 0

        # Function Name: limited_receive
        # Description:
        # - Read one ASGI message and add request-body chunk bytes to this request's running total.
        # Parameters:
        # - None.
        # Returns:
        # - The received message; raises _RequestBodyTooLarge once the enclosing request's limit is exceeded.
        async def limited_receive() -> Message:
            nonlocal received_bytes
            message = await receive()
            if message["type"] == "http.request":
                received_bytes += len(message.get("body", b""))
                if received_bytes > limit:
                    raise _RequestBodyTooLarge
            return message

        try:
            await self.app(scope, limited_receive, send)
        except _RequestBodyTooLarge:
            await self._send_rejection(scope, receive, send)

    # Function Name: _content_length
    # Description:
    # - Read the first Content-Length header without treating missing, malformed or negative values as a valid size.
    # Parameters:
    # - scope (Scope): ASGI connection metadata, including request path and headers.
    # Returns:
    # - Nonnegative declared byte length, or None if unavailable or invalid.
    @staticmethod
    def _content_length(scope: Scope) -> int | None:
        for name, value in scope.get("headers", ()):
            if name.lower() != b"content-length":
                continue
            try:
                parsed = int(value)
            except (TypeError, ValueError):
                return None
            return parsed if parsed >= 0 else None
        return None

    # Function Name: _send_rejection
    # Description:
    # - Send a generic JSON HTTP 413 response without including request contents.
    # Parameters:
    # - scope (Scope): ASGI connection metadata, including request path and headers.
    # - receive (Receive): ASGI callable that reads the next inbound message.
    # - send (Send): ASGI callable that emits outbound response messages.
    # Returns:
    # - None; the rejection is written through the ASGI send callback.
    @staticmethod
    async def _send_rejection(
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        response = JSONResponse(
            status_code=413,
            content={"detail": "The uploaded request is too large."},
        )
        await response(scope, receive, send)
