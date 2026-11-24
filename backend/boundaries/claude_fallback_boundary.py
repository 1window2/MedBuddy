# File Name: claude_fallback_boundary.py
# Role: Answers a Gemini-shaped generate_content request through the Claude API, for use only after a Gemini outage.
"""Claude transport that mimics the small generate_content surface the AI boundaries use."""

import base64
import json
from types import SimpleNamespace
from typing import Any

from google.genai import types

# Server-side refusal fallback lets Anthropic re-run a declined request on another Claude model.
_REFUSAL_FALLBACK_BETA = "server-side-fallback-2026-07-01"
# Thinking is always on for the default model, so the cap covers thinking plus the JSON answer.
_MAX_TOKENS = 16_000
_IMAGE_MEDIA_TYPES = frozenset({"image/jpeg", "image/png", "image/webp", "image/gif"})
_JSON_ONLY_INSTRUCTION = (
    "Respond with exactly one JSON object and nothing else: no prose and no code fences."
)


# Class Name: ClaudeFallbackError
# Role:
# - Reports a Claude answer that cannot stand in for the Gemini answer.
# Responsibilities:
# - Carry a short reason without provider text or user data.
# Attributes:
# - None beyond the exception message.
class ClaudeFallbackError(RuntimeError):
    """Raised when the Claude request or its answer is unusable."""


# Function Name: to_claude_json_schema
# Description:
# - Convert a Gemini response schema (OpenAPI-style upper-case types) into the JSON Schema subset Claude structured outputs accept.
# - Keeps type, description, enum, properties, required, items and anyOf; drops numeric, length and count limits,
#   which the callers already validate after parsing; closes every object with additionalProperties false.
# Parameters:
# - schema (Any): Gemini schema node.
# Returns:
# - Equivalent Claude schema node; raises ClaudeFallbackError for a node that is not an object.
def to_claude_json_schema(schema: Any) -> dict[str, Any]:
    if not isinstance(schema, dict):
        raise ClaudeFallbackError("Response schema node is not an object.")
    converted: dict[str, Any] = {}
    schema_type = schema.get("type")
    if isinstance(schema_type, str):
        schema_type = schema_type.lower()
        converted["type"] = schema_type
    if isinstance(schema.get("description"), str):
        converted["description"] = schema["description"]
    if isinstance(schema.get("enum"), list):
        converted["enum"] = list(schema["enum"])
    if schema_type == "object":
        properties = schema.get("properties") or {}
        if not isinstance(properties, dict):
            raise ClaudeFallbackError("Response schema properties are not an object.")
        converted["properties"] = {
            str(name): to_claude_json_schema(child) for name, child in properties.items()
        }
        required = schema.get("required") or []
        converted["required"] = [name for name in required if name in properties]
        converted["additionalProperties"] = False
    if schema_type == "array" and "items" in schema:
        converted["items"] = to_claude_json_schema(schema["items"])
    if isinstance(schema.get("anyOf"), list):
        converted["anyOf"] = [to_claude_json_schema(child) for child in schema["anyOf"]]
    if schema.get("nullable") is True:
        return {"anyOf": [converted, {"type": "null"}]}
    return converted


# Function Name: to_claude_content
# Description:
# - Convert Gemini contents (one string, or a list of strings and text/inline-image Parts) into Claude content blocks.
# Parameters:
# - contents (Any): Contents exactly as the Gemini boundary passed them.
# Returns:
# - Claude user content blocks in the original order; raises ClaudeFallbackError for anything else.
def to_claude_content(contents: Any) -> list[dict[str, Any]]:
    items = [contents] if isinstance(contents, (str, types.Part)) else contents
    if not isinstance(items, (list, tuple)) or not items:
        raise ClaudeFallbackError("Unsupported request contents.")
    blocks: list[dict[str, Any]] = []
    for item in items:
        if isinstance(item, str):
            if item.strip():
                blocks.append({"type": "text", "text": item})
            continue
        if not isinstance(item, types.Part):
            raise ClaudeFallbackError("Unsupported request content part.")
        if item.text:
            blocks.append({"type": "text", "text": item.text})
            continue
        inline = item.inline_data
        if inline is None or not inline.data or inline.mime_type not in _IMAGE_MEDIA_TYPES:
            raise ClaudeFallbackError("Unsupported request content part.")
        blocks.append(
            {
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": inline.mime_type,
                    "data": base64.standard_b64encode(inline.data).decode("ascii"),
                },
            }
        )
    if not any(block["type"] == "text" for block in blocks):
        raise ClaudeFallbackError("Request contents have no instructions.")
    return blocks


# Function Name: _config_value
# Description:
# - Read one field from a GenerateContentConfig object or a plain config dictionary.
# Parameters:
# - config (Any): Gemini request config or None.
# - name (str): Field name.
# Returns:
# - Field value, or None when absent.
def _config_value(config: Any, name: str) -> Any:
    if config is None:
        return None
    if isinstance(config, dict):
        return config.get(name)
    return getattr(config, name, None)


# Function Name: _strip_code_fence
# Description:
# - Remove one surrounding Markdown code fence from a JSON answer requested without a schema.
# Parameters:
# - text (str): Claude answer text.
# Returns:
# - Text without the fence.
def _strip_code_fence(text: str) -> str:
    stripped = text.strip()
    if stripped.startswith("```") and stripped.endswith("```"):
        first_newline = stripped.find("\n")
        if first_newline != -1:
            return stripped[first_newline + 1 : -3].strip()
    return stripped


# Class Name: _ClaudeModels
# Role:
# - Implements generate_content for the Gemini-shaped client.
# Responsibilities:
# - Build one Claude Messages request per call and return an object with a text attribute.
# Attributes:
# - _owner (ClaudeGenerateContentClient): Client holding the SDK client, model and effort.
class _ClaudeModels:
    def __init__(self, owner: "ClaudeGenerateContentClient") -> None:
        self._owner = owner

    # Function Name: generate_content
    # Description:
    # - Send the Gemini-shaped request to Claude; JSON requests use structured outputs when a schema is given.
    # - The Gemini model name is ignored; sampling, thinking-level and media settings have no Claude counterpart here.
    # Parameters:
    # - model (str): Gemini model name chosen by the caller; unused.
    # - contents (Any): Gemini contents.
    # - config (Any): Gemini config object or dictionary.
    # Returns:
    # - Object whose text attribute holds the answer; raises ClaudeFallbackError for a stopped or empty answer.
    async def generate_content(
        self,
        *,
        model: str | None = None,
        contents: Any,
        config: Any = None,
    ) -> SimpleNamespace:
        del model
        owner = self._owner
        output_config: dict[str, Any] = {"effort": owner.effort}
        system_parts: list[str] = []
        system_instruction = _config_value(config, "system_instruction")
        if isinstance(system_instruction, str) and system_instruction.strip():
            system_parts.append(system_instruction.strip())
        wants_json = _config_value(config, "response_mime_type") == "application/json"
        response_schema = _config_value(config, "response_schema")
        uses_schema = wants_json and response_schema is not None
        if uses_schema:
            output_config["format"] = {
                "type": "json_schema",
                "schema": to_claude_json_schema(response_schema),
            }
        elif wants_json:
            system_parts.append(_JSON_ONLY_INSTRUCTION)

        request: dict[str, Any] = {
            "model": owner.model_name,
            "max_tokens": _MAX_TOKENS,
            "betas": [_REFUSAL_FALLBACK_BETA],
            "fallbacks": "default",
            "output_config": output_config,
            "messages": [{"role": "user", "content": to_claude_content(contents)}],
        }
        if system_parts:
            request["system"] = "\n\n".join(system_parts)

        response = await owner.anthropic_client.beta.messages.create(**request)
        if response.stop_reason != "end_turn":
            raise ClaudeFallbackError(f"Claude stopped with {response.stop_reason}.")
        text = "".join(
            block.text for block in response.content if getattr(block, "type", None) == "text"
        )
        if wants_json and not uses_schema:
            text = _strip_code_fence(text)
        if not text.strip():
            raise ClaudeFallbackError("Claude returned an empty answer.")
        if wants_json:
            try:
                json.loads(text)
            except json.JSONDecodeError as exc:
                raise ClaudeFallbackError("Claude returned invalid JSON.") from exc
        return SimpleNamespace(text=text)


# Class Name: ClaudeGenerateContentClient
# Role:
# - Stands in for genai.Client inside a separate copy of an AI boundary that runs only after a Gemini outage.
# Responsibilities:
# - Expose aio.models.generate_content with the call shape the boundaries use; nothing else.
# Attributes:
# - anthropic_client (Any): AsyncAnthropic client (or a test double with beta.messages.create).
# - model_name (str): Claude model identifier.
# - effort (str): Claude effort level.
# - aio (SimpleNamespace): Holds models, mirroring genai.Client.aio.
class ClaudeGenerateContentClient:
    def __init__(self, *, anthropic_client: Any, model_name: str, effort: str) -> None:
        self.anthropic_client = anthropic_client
        self.model_name = model_name
        self.effort = effort
        self.aio = SimpleNamespace(models=_ClaudeModels(self))
