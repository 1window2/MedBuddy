# File Name: fakes.py
# Role: Shared test doubles for NEW backend tests, one per external collaborator, so each file
#   no longer carries its own partial copy.
#
# Usage:
#   from support.fakes import FakeGeminiClient, FakeRedis, RecordingPushBoundary
#
#   FakeGeminiClient('{"a": 1}', {"b": 2}, TimeoutError())
#       Stands in for google.genai.Client where production awaits
#       client.aio.models.generate_content(...). Scripted answers are used in order and the
#       last one repeats. Read .calls / .call_count / .closed / .aio.closed afterwards.
#   RecordingPushBoundary(invalid_tokens=("dead",), retryable=1, raises=None, on_send=None)
#       Implements PushNotificationBoundary.send_notification. Reports only the invalid tokens
#       that are in the batch it was given. Read .calls afterwards.
#   FakeRedis()
#       Async Redis double holding real values: get / set / setex / delete / eval / ping /
#       aclose. eval implements the atomic INCR+EXPIRE counter of core/request_rate_limits.py,
#       so it returns 1, 2, 3 ... per key. Read .calls["get"], .values, .ttl_seconds, .closed;
#       set .fail_with to an exception to simulate an outage and back to None to recover.
#
# The doubles record what they were asked and never reach the network. Keep them faithful to
# the real collaborator: when production starts calling a new method, add it here once.

import inspect
import json
from collections import Counter
from collections.abc import Callable

from boundaries.push_notification_boundary import PushDeliveryResult


# Function Name: _is_exception_class
# Description:
# - Tells an exception class apart from the other callables a Gemini script may contain.
# Parameters:
# - value (object): Scripted answer.
# Returns:
# - True when value is a BaseException subclass.
def _is_exception_class(value: object) -> bool:
    return isinstance(value, type) and issubclass(value, BaseException)


# Class Name: FakeGeminiResponse
# Role: Response object returned by FakeGeminiClient.
# Attributes:
# - text (str | None): Body production reads from the SDK response; None models a blank answer.
class FakeGeminiResponse:
    # Function Name: __init__
    # Description:
    # - Stores the response text.
    # Parameters:
    # - text (str | None): Text exposed as response.text.
    # Returns:
    # - None.
    def __init__(self, text: str | None) -> None:
        self.text = text


# Class Name: _FakeGeminiAsyncModels
# Role: The `client.aio.models` namespace of FakeGeminiClient.
# Attributes:
# - _client (FakeGeminiClient): Owner that records calls and holds the scripted answers.
class _FakeGeminiAsyncModels:
    # Function Name: __init__
    # Description:
    # - Keeps the owning client.
    # Parameters:
    # - client (FakeGeminiClient): Owner of the call ledger and the script.
    # Returns:
    # - None.
    def __init__(self, client: "FakeGeminiClient") -> None:
        self._client = client

    # Function Name: generate_content
    # Description:
    # - Records the request keyword arguments and returns or raises the next scripted answer.
    # Parameters:
    # - **request (object): SDK keyword arguments such as model, contents and config.
    # Returns:
    # - FakeGeminiResponse for a text answer; raises the scripted exception otherwise.
    async def generate_content(self, **request: object) -> FakeGeminiResponse:
        return await self._client._respond(request)


# Class Name: _FakeGeminiAio
# Role: The `client.aio` namespace of FakeGeminiClient.
# Attributes:
# - models (_FakeGeminiAsyncModels): Async model interface.
# - closed (bool): Whether aclose() was awaited.
class _FakeGeminiAio:
    # Function Name: __init__
    # Description:
    # - Builds the async model namespace for the owning client.
    # Parameters:
    # - client (FakeGeminiClient): Owner of the call ledger and the script.
    # Returns:
    # - None.
    def __init__(self, client: "FakeGeminiClient") -> None:
        self.models = _FakeGeminiAsyncModels(client)
        self.closed = False

    # Function Name: aclose
    # Description:
    # - Records that the async transport was closed.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def aclose(self) -> None:
        self.closed = True


# Class Name: FakeGeminiClient
# Role: Scripted, recording replacement for google.genai.Client.
# Responsibilities:
# - Answer client.aio.models.generate_content from a script, in order; the last entry repeats.
# - Record every request and both close calls.
# Attributes:
# - calls (list[dict[str, object]]): Keyword arguments of each generate_content call, in order.
# - aio (_FakeGeminiAio): Async namespace; aio.closed tells whether aclose() was awaited.
# - closed (bool): Whether close() was called.
# - client_options (dict[str, object]): Constructor keywords such as api_key, kept so the class
#   can be patched in for genai.Client.
# Note: A script entry is a str (response text), a dict or list (JSON-encoded text), None
#   (blank text), an exception instance or class (raised), or a callable taking the request
#   dict and returning any of these; an async callable is awaited, which lets a test block or
#   delay the answer. With no script the answer is "{}".
class FakeGeminiClient:
    # Function Name: __init__
    # Description:
    # - Stores the scripted answers and starts with an empty call ledger.
    # Parameters:
    # - *responses (object): Scripted answers as described in the class note.
    # - **client_options (object): SDK constructor keywords; recorded and otherwise ignored.
    # Returns:
    # - None.
    def __init__(self, *responses: object, **client_options: object) -> None:
        self._responses: list[object] = list(responses) if responses else ["{}"]
        self.client_options = client_options
        self.calls: list[dict[str, object]] = []
        self.aio = _FakeGeminiAio(self)
        self.closed = False

    # Function Name: call_count
    # Description:
    # - Counts the generate_content calls received so far.
    # Parameters:
    # - None.
    # Returns:
    # - Number of recorded calls.
    @property
    def call_count(self) -> int:
        return len(self.calls)

    # Function Name: close
    # Description:
    # - Records that the synchronous transport was closed.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    def close(self) -> None:
        self.closed = True

    # Function Name: _respond
    # Description:
    # - Records one request, takes the next scripted answer (keeping the last one for later
    #   calls) and turns it into a response or an exception.
    # Parameters:
    # - request (dict[str, object]): Keyword arguments of the generate_content call.
    # Returns:
    # - FakeGeminiResponse; raises when the scripted answer is an exception.
    async def _respond(self, request: dict[str, object]) -> FakeGeminiResponse:
        self.calls.append(request)
        answer = (
            self._responses.pop(0) if len(self._responses) > 1 else self._responses[0]
        )
        if callable(answer) and not _is_exception_class(answer):
            answer = answer(request)
            if inspect.isawaitable(answer):
                answer = await answer
        if _is_exception_class(answer) or isinstance(answer, BaseException):
            raise answer
        if isinstance(answer, (dict, list)):
            return FakeGeminiResponse(json.dumps(answer, ensure_ascii=False))
        return FakeGeminiResponse(answer)


# Class Name: RecordingPushBoundary
# Role: Recording replacement for the Firebase push boundary.
# Responsibilities:
# - Record each push request without contacting Firebase.
# - Classify the batch like the real boundary: listed invalid tokens that are in the batch are
#   permanent failures, up to `retryable` of the rest are transient failures, the rest succeed.
# Attributes:
# - calls (list[dict[str, object]]): One dict per request with tokens, title, body and data.
# - invalid_tokens (tuple[str, ...]): Tokens reported as permanently invalid when targeted.
# - retryable (int): Transient failures reported per request.
# - raises (BaseException | type[BaseException] | None): Raised by every send when set.
# - on_send (Callable | None): Called with the recorded request before the result is built,
#   for assertions about the state at send time (for example `not db.in_transaction()`).
class RecordingPushBoundary:
    # Function Name: __init__
    # Description:
    # - Stores the configured outcome and starts with an empty call ledger.
    # Parameters:
    # - invalid_tokens (tuple[str, ...]): Tokens to report as permanently invalid.
    # - retryable (int): Transient failure count per request.
    # - raises (BaseException | type[BaseException] | None): Exception raised by each send.
    # - on_send (Callable[[dict[str, object]], None] | None): Hook run at send time.
    # Returns:
    # - None.
    def __init__(
        self,
        invalid_tokens: tuple[str, ...] = (),
        retryable: int = 0,
        raises: BaseException | type[BaseException] | None = None,
        on_send: Callable[[dict[str, object]], None] | None = None,
    ) -> None:
        self.invalid_tokens = tuple(invalid_tokens)
        self.retryable = retryable
        self.raises = raises
        self.on_send = on_send
        self.calls: list[dict[str, object]] = []

    # Function Name: send_notification
    # Description:
    # - Records the request, runs the on_send hook, then raises the configured exception or
    #   returns the configured delivery classification for this batch.
    # Parameters:
    # - tokens (list[str]): Destination device tokens.
    # - title (str): Notification title.
    # - body (str): Notification body.
    # - data (dict[str, str]): Routing data.
    # Returns:
    # - PushDeliveryResult whose three counts add up to the number of tokens.
    def send_notification(
        self,
        *,
        tokens: list[str],
        title: str,
        body: str,
        data: dict[str, str],
    ) -> PushDeliveryResult:
        call: dict[str, object] = {
            "tokens": list(tokens),
            "title": title,
            "body": body,
            "data": dict(data),
        }
        self.calls.append(call)
        if self.on_send is not None:
            self.on_send(call)
        if self.raises is not None:
            raise self.raises
        invalid = tuple(token for token in tokens if token in self.invalid_tokens)
        retryable = min(self.retryable, len(tokens) - len(invalid))
        return PushDeliveryResult(
            success_count=len(tokens) - len(invalid) - retryable,
            invalid_tokens=invalid,
            retryable_failure_count=retryable,
        )


# Class Name: FakeRedis
# Role: In-memory replacement for redis.asyncio.Redis (decode_responses=True) that keeps real
#   values and counts commands.
# Responsibilities:
# - Serve the commands production uses: get, set, setex, delete, eval, ping and aclose.
# - Count every command, also while failing, so a test can assert "no Redis call was made".
# Attributes:
# - values (dict[str, str]): Stored strings by key.
# - ttl_seconds (dict[str, int]): Last expiry requested for a key; recorded, never enforced.
# - calls (Counter[str]): Number of calls per command name.
# - fail_with (BaseException | None): When set, every command except aclose raises it.
# - closed (bool): Whether aclose() was awaited.
class FakeRedis:
    # Function Name: __init__
    # Description:
    # - Starts empty and available.
    # Parameters:
    # - fail_with (BaseException | None): Exception every command raises until it is cleared.
    # Returns:
    # - None.
    def __init__(self, fail_with: BaseException | None = None) -> None:
        self.values: dict[str, str] = {}
        self.ttl_seconds: dict[str, int] = {}
        self.calls: Counter[str] = Counter()
        self.fail_with = fail_with
        self.closed = False

    # Function Name: _begin
    # Description:
    # - Counts one command and raises the configured outage, if any.
    # Parameters:
    # - command (str): Command name used as the counter key.
    # Returns:
    # - None.
    def _begin(self, command: str) -> None:
        self.calls[command] += 1
        if self.fail_with is not None:
            raise self.fail_with

    # Function Name: get
    # Description:
    # - Reads one stored string.
    # Parameters:
    # - key (str): Redis key.
    # Returns:
    # - Stored value, or None when the key is absent.
    async def get(self, key: str) -> str | None:
        self._begin("get")
        return self.values.get(key)

    # Function Name: set
    # Description:
    # - Stores one value as a string, replacing any previous value and expiry.
    # Parameters:
    # - key (str): Redis key.
    # - value (object): Value to store.
    # - ex (int | None): Expiry in seconds to record.
    # Returns:
    # - True.
    async def set(self, key: str, value: object, ex: int | None = None) -> bool:
        self._begin("set")
        self._store(key, value, ex)
        return True

    # Function Name: setex
    # Description:
    # - Stores one value with an expiry, in the redis-py argument order.
    # Parameters:
    # - key (str): Redis key.
    # - seconds (int): Expiry in seconds to record.
    # - value (object): Value to store.
    # Returns:
    # - True.
    async def setex(self, key: str, seconds: int, value: object) -> bool:
        self._begin("setex")
        self._store(key, value, seconds)
        return True

    # Function Name: delete
    # Description:
    # - Removes the given keys and their recorded expiries.
    # Parameters:
    # - *keys (str): Redis keys.
    # Returns:
    # - Number of keys that existed.
    async def delete(self, *keys: str) -> int:
        self._begin("delete")
        removed = 0
        for key in keys:
            if key in self.values:
                removed += 1
            self.values.pop(key, None)
            self.ttl_seconds.pop(key, None)
        return removed

    # Function Name: eval
    # Description:
    # - Runs the one script production sends, the atomic counter of
    #   core/request_rate_limits.py: increment KEYS[1] and, on the first increment, record
    #   ARGV[1] as its expiry. The script text itself is not interpreted.
    # Parameters:
    # - script (str): Lua source; ignored.
    # - number_of_keys (int): Must be 1.
    # - *keys_and_args (object): The counter key followed by the expiry in seconds.
    # Returns:
    # - The counter value after the increment (1, 2, 3 ... per key).
    async def eval(
        self,
        script: str,
        number_of_keys: int,
        *keys_and_args: object,
    ) -> int:
        self._begin("eval")
        if number_of_keys != 1 or not keys_and_args:
            raise NotImplementedError(
                "FakeRedis.eval only implements the single-key counter script."
            )
        key = str(keys_and_args[0])
        count = int(self.values.get(key, "0")) + 1
        self.values[key] = str(count)
        if count == 1 and len(keys_and_args) > 1:
            self.ttl_seconds[key] = int(keys_and_args[1])
        return count

    # Function Name: ping
    # Description:
    # - Answers the readiness ping.
    # Parameters:
    # - None.
    # Returns:
    # - True.
    async def ping(self) -> bool:
        self._begin("ping")
        return True

    # Function Name: aclose
    # Description:
    # - Records that the client was closed; never fails, like closing a broken connection.
    # Parameters:
    # - None.
    # Returns:
    # - None.
    async def aclose(self) -> None:
        self.calls["aclose"] += 1
        self.closed = True

    # Function Name: _store
    # Description:
    # - Writes one string value and records or clears its expiry.
    # Parameters:
    # - key (str): Redis key.
    # - value (object): Value to store as text.
    # - seconds (int | None): Expiry to record; None clears a previous one.
    # Returns:
    # - None.
    def _store(self, key: str, value: object, seconds: int | None) -> None:
        self.values[key] = str(value)
        if seconds is None:
            self.ttl_seconds.pop(key, None)
        else:
            self.ttl_seconds[key] = int(seconds)
