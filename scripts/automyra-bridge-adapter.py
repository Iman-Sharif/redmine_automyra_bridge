#!/usr/bin/env python3
"""Automyra Bridge adapter — pure contract passthrough.

This adapter is not the "brain". It passes Redmica requests to the Automyra
downstream (Manifest/OpenAI-compatible) and normalizes the response into the
Redmica tool-call contract. No Redmica business logic, identity rules, or
proposal heuristics belong here.

Provider policy:
    Use Manifest provider + ``auto`` model to align with OpenClaw WhatsApp
    unless explicitly overridden via ``AUTOMYRA_OPENAI_MODEL`` env var.

Runtime configuration:
    AUTOMYRA_BRIDGE_ADAPTER_HOST (default: 0.0.0.0) binds this adapter.
    AUTOMYRA_BRIDGE_ADAPTER_PORT (default: 4567) binds this adapter.
    AUTOMYRA_BRIDGE_ADAPTER_TOKEN (default: empty) is required in production.
    AUTOMYRA_BRIDGE_ADAPTER_ALLOW_INSECURE_TOKEN (default: unset) is for local development only.
    AUTOMYRA_BRIDGE_ADAPTER_MAX_BODY_BYTES (default: 1048576) limits Redmica request size.
    AUTOMYRA_DOWNSTREAM_URL (default: empty) enables the legacy raw JSON downstream.
    AUTOMYRA_DOWNSTREAM_TOKEN (default: empty) authenticates to AUTOMYRA_DOWNSTREAM_URL.
    AUTOMYRA_DOWNSTREAM_TIMEOUT (default: 15) is provider timeout in seconds.
    AUTOMYRA_OPENAI_BASE_URL (default: empty) selects an OpenAI-compatible provider endpoint.
    AUTOMYRA_OPENAI_API_KEY (default: empty) is required with AUTOMYRA_OPENAI_BASE_URL.
    AUTOMYRA_OPENAI_MODEL (default: manifest/auto) should only override Manifest auto intentionally.
    AUTOMYRA_OPENCLAW_GATEWAY_URL (default: http://172.22.0.1:18789) documents gateway location.

Provider error normalization:
    HTTP 401/403 -> provider_auth_failed
    HTTP 408 or timeout -> provider_timeout
    HTTP 429 -> rate_limited
    HTTP 502/503 or connection errors -> provider_unreachable
    Unparseable or unexpected model response -> invalid_model_response
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.request


HOST = os.environ.get("AUTOMYRA_BRIDGE_ADAPTER_HOST", "0.0.0.0")
PORT = int(os.environ.get("AUTOMYRA_BRIDGE_ADAPTER_PORT", "4567"))
TOKEN = os.environ.get("AUTOMYRA_BRIDGE_ADAPTER_TOKEN", "")
ALLOW_INSECURE_TOKEN = os.environ.get("AUTOMYRA_BRIDGE_ADAPTER_ALLOW_INSECURE_TOKEN") == "1"
STARTED_AT = time.time()
MAX_BODY_BYTES = int(os.environ.get("AUTOMYRA_BRIDGE_ADAPTER_MAX_BODY_BYTES", "1048576"))
DOWNSTREAM_URL = os.environ.get("AUTOMYRA_DOWNSTREAM_URL", "")
DOWNSTREAM_TOKEN = os.environ.get("AUTOMYRA_DOWNSTREAM_TOKEN", "")
DOWNSTREAM_TIMEOUT = float(os.environ.get("AUTOMYRA_DOWNSTREAM_TIMEOUT", "15"))
OPENAI_BASE_URL = os.environ.get("AUTOMYRA_OPENAI_BASE_URL", "").rstrip("/")
OPENAI_API_KEY = os.environ.get("AUTOMYRA_OPENAI_API_KEY", "")
OPENAI_MODEL = os.environ.get("AUTOMYRA_OPENAI_MODEL", "manifest/auto")

OPENCLAW_GATEWAY_URL = os.environ.get("AUTOMYRA_OPENCLAW_GATEWAY_URL", "http://172.22.0.1:18789")


class Handler(BaseHTTPRequestHandler):
    server_version = "AutomyraBridgeAdapter/2.0"

    def log_message(self, fmt, *args):
        log_event("http", remote=self.address_string(), message=fmt % args)

    def do_GET(self):
        if self.path == "/health":
            self.respond_json(200, {"status": "ok"})
            return
        if self.path == "/ready":
            self.respond_json(
                200 if TOKEN else 503,
                {
                    "status": "ready" if TOKEN else "not_ready",
                    "token_configured": bool(TOKEN),
                    "downstream_configured": bool(DOWNSTREAM_URL),
                    "openai_downstream_configured": bool(OPENAI_BASE_URL and OPENAI_API_KEY),
                    "uptime_seconds": int(time.time() - STARTED_AT),
                },
            )
            return
        self.respond_json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/improve":
            self.respond_json(404, {"error": "not_found"})
            return

        started = time.time()
        context = request_context(self)
        expected = "Bearer %s" % TOKEN
        if self.headers.get("Authorization") != expected:
            self.respond_json(401, error("unauthorized", "Invalid Automyra Bridge bearer token.", context))
            log_request(context, "unknown", 401, started, error_code="unauthorized")
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > MAX_BODY_BYTES:
                self.respond_json(413, error("request_too_large", "Request body exceeds Automyra Bridge adapter limit.", context))
                log_request(context, "unknown", 413, started, error_code="request_too_large")
                return
            body = self.rfile.read(length).decode("utf-8")
            payload = json.loads(body or "{}")
        except Exception:
            self.respond_json(400, error("invalid_json", "Request body must be valid JSON.", context))
            log_request(context, "unknown", 400, started, error_code="invalid_json")
            return

        if not isinstance(payload, dict):
            self.respond_json(400, error("invalid_request", "Request body must be a JSON object.", context))
            log_request(context, "unknown", 400, started, error_code="invalid_request")
            return

        action = str(payload.get("action") or "")

        if not DOWNSTREAM_URL and not OPENAI_BASE_URL:
            self.respond_json(503, error("downstream_not_configured", "Automyra downstream is not configured. Set AUTOMYRA_DOWNSTREAM_URL or AUTOMYRA_OPENAI_BASE_URL.", context))
            log_request(context, action, 503, started, error_code="downstream_not_configured")
            return

        result = downstream_response(payload, context)
        if isinstance(result, AdapterError):
            self.respond_json(result.status, error(result.code, result.message, context))
            log_request(context, action, result.status, started, error_code=result.code)
            return
        if result is not None:
            self.respond_json(200, with_context(result, context))
            log_request(context, action, 200, started)
            return

        self.respond_json(502, error("invalid_downstream_response", "Automyra downstream returned an empty or invalid response.", context))
        log_request(context, action, 502, started, error_code="invalid_downstream_response")

    def respond_json(self, status, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class AdapterError:
    def __init__(self, status, code, message):
        self.status = status
        self.code = code
        self.message = message


def request_context(handler):
    return {
        "correlation_id": handler.headers.get("X-Correlation-ID") or "",
        "idempotency_key": handler.headers.get("Idempotency-Key") or "",
    }


def with_context(payload, context):
    if context.get("correlation_id"):
        if is_bridge_contract(payload):
            payload.setdefault("metadata", {})["correlation_id"] = context["correlation_id"]
            return payload
        payload["correlation_id"] = context["correlation_id"]
    return payload


def is_bridge_contract(payload):
    return isinstance(payload, dict) and all(key in payload for key in ("response", "tool_calls", "proposals", "metadata"))


def error(code, message, context=None):
    payload = {"success": False, "error": code, "error_code": code, "message": message, "error_summary": message}
    return with_context(payload, context or {})


def provider_error(status, message=None):
    code = provider_error_code(status)
    return AdapterError(provider_http_status(code, status), code, message or provider_error_summary(code, status))


def provider_error_code(status):
    if status in (401, 403):
        return "provider_auth_failed"
    if status == 408:
        return "provider_timeout"
    if status == 429:
        return "rate_limited"
    if status in (502, 503):
        return "provider_unreachable"
    return "provider_unreachable"


def provider_http_status(code, original_status=None):
    if code == "provider_timeout":
        return 504
    if code == "rate_limited":
        return 429
    if original_status in (502, 503):
        return original_status
    return 502


def provider_error_summary(code, status=None):
    if code == "provider_auth_failed":
        return "Automyra provider authentication failed. Check configured provider credentials."
    if code == "provider_timeout":
        return "Automyra provider timed out before returning a response."
    if code == "rate_limited":
        return "Automyra provider rate limit was reached. Please retry later."
    if code == "invalid_model_response":
        return "Automyra provider returned an invalid model response."
    if code == "provider_unreachable":
        return "Automyra provider is unreachable%s." % (" (HTTP %s)" % status if status else "")
    return "Automyra provider request failed."


def downstream_response(payload, context):
    if OPENAI_BASE_URL:
        return openai_downstream_response(payload, context)

    if not DOWNSTREAM_URL:
        return None

    data = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(DOWNSTREAM_URL, data=data, headers={"Content-Type": "application/json"})
    if DOWNSTREAM_TOKEN:
        request.add_header("Authorization", "Bearer %s" % DOWNSTREAM_TOKEN)
    if context.get("correlation_id"):
        request.add_header("X-Correlation-ID", context["correlation_id"])
    if context.get("idempotency_key"):
        request.add_header("Idempotency-Key", context["idempotency_key"])

    try:
        with urllib.request.urlopen(request, timeout=DOWNSTREAM_TIMEOUT) as response:
            raw = response.read().decode("utf-8") or "{}"
    except urllib.error.HTTPError as exc:
        return provider_error(exc.code)
    except (TimeoutError, socket.timeout):
        return provider_error(408)
    except (urllib.error.URLError, ConnectionError, OSError):
        return provider_error(503)

    parsed = parse_downstream_body(raw)

    if not isinstance(parsed, dict):
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))
    return normalize_bridge_contract(parsed, provider="manifest", model="auto", raw_shape="direct_json")


def openai_downstream_response(payload, context):
    if not OPENAI_API_KEY:
        return AdapterError(503, "downstream_not_configured", "OpenAI-compatible Automyra downstream requires AUTOMYRA_OPENAI_API_KEY.")

    url = "%s/v1/chat/completions" % OPENAI_BASE_URL
    messages = [
        {
            "role": "system",
            "content": (
                "You are Automyra. Return a JSON object when possible. "
                "If you return plain text, the adapter will wrap it as {\"response\": text}."
            ),
        },
        {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
    ]
    request_payload = {"model": OPENAI_MODEL, "messages": messages, "temperature": 0.2, "response_format": {"type": "json_object"}}
    data = json.dumps(request_payload).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", "Authorization": "Bearer %s" % OPENAI_API_KEY})
    if context.get("correlation_id"):
        request.add_header("X-Correlation-ID", context["correlation_id"])
        request.add_header("X-Session-Key", context["correlation_id"])
    if context.get("idempotency_key"):
        request.add_header("Idempotency-Key", context["idempotency_key"])

    try:
        with urllib.request.urlopen(request, timeout=DOWNSTREAM_TIMEOUT) as response:
            outer = json.loads(response.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as exc:
        return provider_error(exc.code)
    except (TimeoutError, socket.timeout):
        return provider_error(408)
    except (urllib.error.URLError, ConnectionError, OSError):
        return provider_error(503)
    except (json.JSONDecodeError, ValueError):
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))

    normalized = normalize_openai_response(outer, action=str(payload.get("action") or ""))
    if isinstance(normalized, AdapterError):
        return normalized
    return normalized


def parse_downstream_body(body):
    try:
        return json.loads(body)
    except Exception:
        return wrap_plain_text(body)


def wrap_plain_text(text):
    return {"response": str(text or "").strip()}


def strip_json_fence(text):
    """Remove markdown JSON fences so providers may return ```json {...} ``` safely."""
    value = str(text or "").strip()
    if not value.startswith("```"):
        return value
    lines = value.splitlines()
    if lines and lines[0].strip().startswith("```"):
        lines = lines[1:]
    if lines and lines[-1].strip() == "```":
        lines = lines[:-1]
    return "\n".join(lines).strip()


def normalize_openai_response(payload, action=""):
    """Normalize Manifest/OpenAI-compatible chat completion variants to the bridge contract."""
    if not isinstance(payload, dict):
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))
    message = choices[0].get("message") if isinstance(choices[0], dict) else None
    if not isinstance(message, dict):
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))

    raw_shape = "chat_completion"
    content = message.get("content")
    response_text = content_to_text(content)
    if isinstance(content, list):
        raw_shape = "chat_completion_content_parts"

    # Manifest sometimes leaves content blank and places the assistant text in reasoning.
    if not response_text.strip():
        response_text = content_to_text(message.get("reasoning"))
        if response_text.strip():
            raw_shape = "chat_completion_reasoning"

    tool_calls = normalize_tool_calls(message.get("tool_calls"))
    if tool_calls and not response_text.strip():
        raw_shape = "chat_completion_tool_calls"

    parsed = None
    if response_text.strip():
        # Content may be a plain JSON object, or the same JSON wrapped in markdown fences.
        stripped_response = strip_json_fence(response_text)
        if stripped_response != response_text.strip():
            raw_shape = "chat_completion_fenced_json"
        try:
            parsed = json.loads(stripped_response)
        except Exception:
            parsed = wrap_plain_text(response_text)
    elif tool_calls:
        # Tool-call-only responses are successful even when there is no user-visible text.
        parsed = {"response": "", "tool_calls": tool_calls}
    else:
        parsed = wrap_plain_text("")

    if action == "governance_evaluate":
        governance_payload = normalize_governance_payload(parsed)
        if isinstance(governance_payload, AdapterError):
            return governance_payload
        return normalize_bridge_contract(governance_payload, provider="manifest", model=OPENAI_MODEL, raw_shape=raw_shape)

    if not isinstance(parsed, dict):
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))
    if tool_calls and not parsed.get("tool_calls"):
        parsed["tool_calls"] = tool_calls
    return normalize_bridge_contract(parsed, provider="manifest", model=OPENAI_MODEL, raw_shape=raw_shape)


def normalize_governance_payload(parsed):
    if isinstance(parsed, list):
        findings = parsed
    elif isinstance(parsed, dict) and isinstance(parsed.get("findings"), list):
        findings = parsed["findings"]
    else:
        return AdapterError(502, "invalid_model_response", provider_error_summary("invalid_model_response"))

    return {
        "response": json.dumps({"findings": findings}, ensure_ascii=False),
        "tool_calls": [],
        "proposals": [],
        "metadata": {"response_type": "governance_findings"},
    }


def content_to_text(content):
    """Convert strings and OpenAI-style content parts into one response string."""
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for part in content:
            if isinstance(part, str):
                parts.append(part)
            elif isinstance(part, dict):
                # Chat content arrays commonly use {type:"text", text:"..."}; tolerate content too.
                value = part.get("text") if "text" in part else part.get("content")
                if value is not None:
                    parts.append(content_to_text(value))
        return "".join(parts)
    return str(content)


def normalize_tool_calls(tool_calls):
    """Map OpenAI-native function tool calls into [{name, arguments}] bridge calls."""
    if not isinstance(tool_calls, list):
        return []
    normalized = []
    for call in tool_calls:
        if not isinstance(call, dict):
            continue
        function = call.get("function") if isinstance(call.get("function"), dict) else {}
        name = call.get("name") or function.get("name") or ""
        arguments = call.get("arguments") if "arguments" in call else function.get("arguments")
        if isinstance(arguments, str):
            try:
                arguments = json.loads(arguments or "{}")
            except Exception:
                arguments = {"raw": arguments}
        if arguments is None:
            arguments = {}
        normalized.append({"name": str(name), "arguments": arguments})
    return normalized


def normalize_bridge_contract(payload, provider="manifest", model="auto", raw_shape="unknown"):
    """Return the strict bridge contract for every successful adapter response."""
    response = content_to_text(payload.get("response", payload.get("content", ""))).strip()
    tool_calls = normalize_tool_calls(payload.get("tool_calls"))
    proposals = payload.get("proposals") if isinstance(payload.get("proposals"), list) else []
    metadata = payload.get("metadata") if isinstance(payload.get("metadata"), dict) else {}
    metadata.update({"provider": provider, "model": model or "auto", "raw_shape": raw_shape})
    return {"response": response, "tool_calls": tool_calls, "proposals": proposals, "metadata": metadata}


def log_event(event, **fields):
    fields = {key: value for key, value in fields.items() if value not in (None, "")}
    fields["event"] = event
    fields["ts"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    sys.stdout.write(json.dumps(fields, sort_keys=True) + "\n")
    sys.stdout.flush()


def log_request(context, action, status, started, error_code=""):
    log_event(
        "request",
        action=action,
        status=status,
        duration_ms=int((time.time() - started) * 1000),
        correlation_id=context.get("correlation_id"),
        idempotency_key_prefix=str(context.get("idempotency_key") or "")[:16],
        error_code=error_code,
    )


if __name__ == "__main__":
    if not TOKEN and not ALLOW_INSECURE_TOKEN:
        sys.stderr.write("AUTOMYRA_BRIDGE_ADAPTER_TOKEN is required. Set AUTOMYRA_BRIDGE_ADAPTER_ALLOW_INSECURE_TOKEN=1 only for development.\n")
        sys.exit(78)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print("Automyra Bridge adapter listening on %s:%s" % (HOST, PORT), flush=True)
    server.serve_forever()
