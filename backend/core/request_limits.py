# File Name: request_limits.py
# Role: Rejects oversized HTTP request bodies before multipart or JSON parsing.

from collections.abc import Mapping

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class _RequestBodyTooLarge(Exception):
    """Internal control-flow signal raised while receiving a request body."""


# Class Name: RequestBodyLimitMiddleware
# Role: Enforces path-specific and default request-body limits before parsing.
# Responsibilities:
#   - Reject declared oversized requests before reading their body.
#   - Count chunked request bytes while Starlette consumes the ASGI stream.
#   - Return a generic 413 response without exposing request contents.
class RequestBodyLimitMiddleware:
    """Applies request byte limits before Starlette buffers multipart or JSON data."""

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

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        """Delegates bounded requests and rejects bodies that exceed their path limit."""

        if scope["type"] != "http" or scope.get("method") not in {
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
