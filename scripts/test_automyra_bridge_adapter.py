#!/usr/bin/env python3
import json
import os
import sys
import threading
import time
import unittest
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import importlib.util


os.environ["AUTOMYRA_BRIDGE_ADAPTER_TOKEN"] = "qa-token"
MODULE_PATH = Path(__file__).with_name("automyra-bridge-adapter.py")
spec = importlib.util.spec_from_file_location("automyra_bridge_adapter", MODULE_PATH)
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class AdapterHttpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), adapter.Handler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        time.sleep(0.05)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.thread.join(timeout=2)

    def request(self, method, path, body=None, headers=None):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=5)
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        merged = {"Content-Type": "application/json", "Authorization": "Bearer qa-token"}
        merged.update(headers or {})
        conn.request(method, path, payload, merged)
        response = conn.getresponse()
        data = response.read().decode("utf-8")
        conn.close()
        return response.status, json.loads(data)

    def test_health(self):
        status, payload = self.request("GET", "/health")
        self.assertEqual(200, status)
        self.assertEqual({"status": "ok"}, payload)

    def test_ready_reports_token_configured(self):
        status, payload = self.request("GET", "/ready")
        self.assertEqual(200, status)
        self.assertEqual("ready", payload["status"])
        self.assertTrue(payload["token_configured"])

    def test_requires_token(self):
        status, payload = self.request("POST", "/improve", {"action": "mention_response"}, {"Authorization": "Bearer wrong"})
        self.assertEqual(401, status)
        self.assertEqual("unauthorized", payload["error"])

    def test_invalid_json(self):
        conn = HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.request("POST", "/improve", b"{", {"Content-Type": "application/json", "Authorization": "Bearer qa-token"})
        response = conn.getresponse()
        payload = json.loads(response.read().decode("utf-8"))
        conn.close()
        self.assertEqual(400, response.status)
        self.assertEqual("invalid_json", payload["error"])

    def test_request_body_size_limit(self):
        original = adapter.MAX_BODY_BYTES
        adapter.MAX_BODY_BYTES = 10
        try:
            status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"body": "@automyra this is too large"}})
        finally:
            adapter.MAX_BODY_BYTES = original
        self.assertEqual(413, status)
        self.assertEqual("request_too_large", payload["error"])

    def test_task_improve_shape(self):
        original_url = adapter.DOWNSTREAM_URL
        adapter.DOWNSTREAM_URL = ""
        adapter.OPENAI_BASE_URL = ""
        try:
            status, payload = self.request("POST", "/improve", {"action": "task_improve", "task": {"title": "T", "notes": "N", "tags": "a,b"}})
        finally:
            adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(503, status)
        self.assertEqual("downstream_not_configured", payload["error"])

    def test_mention_response_returns_empty_when_no_downstream(self):
        original_url = adapter.DOWNSTREAM_URL
        adapter.DOWNSTREAM_URL = ""
        adapter.OPENAI_BASE_URL = ""
        try:
            status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"source": "task_hub_comment", "body": "@automyra create task review backups"}})
        finally:
            adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(503, status)
        self.assertEqual("downstream_not_configured", payload["error"])

    def test_openai_compatible_downstream_response_is_normalized(self):
        content = {"response": "I created the task.", "intent": "create_task", "confidence": 0.9, "tool_calls": [{"tool": "task.create", "input": {"task": {"title": "From brain"}}}]}
        openai_payload = {"choices": [{"message": {"content": json.dumps(content)}}]}
        with DownstreamServer(openai_payload) as downstream:
            original_base = adapter.OPENAI_BASE_URL
            original_key = adapter.OPENAI_API_KEY
            original_url = adapter.DOWNSTREAM_URL
            adapter.OPENAI_BASE_URL = downstream.base_url
            adapter.OPENAI_API_KEY = "mnfst_test"
            adapter.DOWNSTREAM_URL = ""
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"source": "task_hub_comment", "body": "@automyra create task from real brain"}}, {"X-Correlation-ID": "brain-corr"})
            finally:
                adapter.OPENAI_BASE_URL = original_base
                adapter.OPENAI_API_KEY = original_key
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual("I created the task.", payload["response"])
        self.assertEqual("task.create", payload["tool_calls"][0]["tool"])
        self.assertEqual("brain-corr", payload["correlation_id"])

    def test_openai_compatible_downstream_requires_key(self):
        original_base = adapter.OPENAI_BASE_URL
        original_key = adapter.OPENAI_API_KEY
        original_url = adapter.DOWNSTREAM_URL
        adapter.OPENAI_BASE_URL = "http://127.0.0.1:9"
        adapter.OPENAI_API_KEY = ""
        adapter.DOWNSTREAM_URL = ""
        try:
            status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"body": "@automyra help"}})
        finally:
            adapter.OPENAI_BASE_URL = original_base
            adapter.OPENAI_API_KEY = original_key
            adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(503, status)
        self.assertEqual("downstream_not_configured", payload["error"])

    def test_openai_compatible_plain_text_content_is_wrapped(self):
        openai_payload = {"choices": [{"message": {"content": "I reviewed the Redmica context and found no action needed."}}]}
        with DownstreamServer(openai_payload) as downstream:
            original_base = adapter.OPENAI_BASE_URL
            original_key = adapter.OPENAI_API_KEY
            original_url = adapter.DOWNSTREAM_URL
            adapter.OPENAI_BASE_URL = downstream.base_url
            adapter.OPENAI_API_KEY = "mnfst_test"
            adapter.DOWNSTREAM_URL = ""
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"source": "task_hub_comment", "body": "@automyra help"}})
            finally:
                adapter.OPENAI_BASE_URL = original_base
                adapter.OPENAI_API_KEY = original_key
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual("I reviewed the Redmica context and found no action needed.", payload["response"])
        self.assertNotIn("intent", payload)
        self.assertNotIn("proposals", payload)

    def test_openai_compatible_downstream_preserves_legacy_proposals(self):
        content = {"response": "I prepared the task.", "intent": "create_task", "confidence": 0.9, "proposals": [{"action_type": "create_task", "task": {"title": "Legacy brain task"}}]}
        openai_payload = {"choices": [{"message": {"content": json.dumps(content)}}]}
        with DownstreamServer(openai_payload) as downstream:
            original_base = adapter.OPENAI_BASE_URL
            original_key = adapter.OPENAI_API_KEY
            original_url = adapter.DOWNSTREAM_URL
            adapter.OPENAI_BASE_URL = downstream.base_url
            adapter.OPENAI_API_KEY = "mnfst_test"
            adapter.DOWNSTREAM_URL = ""
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"source": "task_hub_comment", "body": "@automyra create task from legacy proposal"}})
            finally:
                adapter.OPENAI_BASE_URL = original_base
                adapter.OPENAI_API_KEY = original_key
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual("create_task", payload["proposals"][0]["action_type"])
        self.assertEqual([], payload.get("tool_calls", []))

    def test_correlation_id_is_preserved(self):
        with DownstreamServer({"response": "got it"}) as downstream:
            original_url = adapter.DOWNSTREAM_URL
            adapter.DOWNSTREAM_URL = downstream.url
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"source": "task_hub_comment", "body": "@automyra help"}}, {"X-Correlation-ID": "corr-1"})
            finally:
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual("corr-1", payload["correlation_id"])

    def test_generic_downstream_plain_text_is_wrapped(self):
        with DownstreamServer("plain downstream answer", content_type="text/plain") as downstream:
            original_url = adapter.DOWNSTREAM_URL
            original_base = adapter.OPENAI_BASE_URL
            adapter.DOWNSTREAM_URL = downstream.url
            adapter.OPENAI_BASE_URL = ""
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"body": "@automyra help"}})
            finally:
                adapter.DOWNSTREAM_URL = original_url
                adapter.OPENAI_BASE_URL = original_base
        self.assertEqual(200, status)
        self.assertEqual({"response": "plain downstream answer"}, payload)

    def test_adapter_does_not_emit_local_proposals(self):
        with DownstreamServer({"response": "I can’t directly cancel this task from here.", "proposals": [], "tool_calls": []}) as downstream:
            original_url = adapter.DOWNSTREAM_URL
            adapter.DOWNSTREAM_URL = downstream.url
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"source": "task_hub_comment", "body": "@automyra cancel this task"}})
            finally:
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual([], payload["proposals"])
        self.assertEqual([], payload.get("tool_calls", []))

    def test_downstream_task_improve_response_is_normalized(self):
        with DownstreamServer({"task": {"title": "Downstream title", "notes": "Downstream notes"}}) as downstream:
            original_url = adapter.DOWNSTREAM_URL
            adapter.DOWNSTREAM_URL = downstream.url
            try:
                status, payload = self.request("POST", "/improve", {"action": "task_improve", "task": {"title": "Draft"}})
            finally:
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual("Downstream title", payload["task"]["title"])

    def test_invalid_downstream_response_fails_safely(self):
        with DownstreamServer({"wrong": "shape"}) as downstream:
            original_url = adapter.DOWNSTREAM_URL
            adapter.DOWNSTREAM_URL = downstream.url
            try:
                status, payload = self.request("POST", "/improve", {"action": "mention_response", "request": {"body": "@automyra help"}})
            finally:
                adapter.DOWNSTREAM_URL = original_url
        self.assertEqual(200, status)
        self.assertEqual({"wrong": "shape"}, payload)


class DownstreamHandler(BaseHTTPRequestHandler):
    response_payload = {}
    content_type = "application/json"

    def do_POST(self):
        if self.content_type == "application/json":
            body = json.dumps(self.response_payload).encode("utf-8")
        else:
            body = str(self.response_payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", self.content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args):
        pass


class DownstreamServer:
    def __init__(self, response_payload, content_type="application/json"):
        self.response_payload = response_payload
        self.content_type = content_type

    def __enter__(self):
        DownstreamHandler.response_payload = self.response_payload
        DownstreamHandler.content_type = self.content_type
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), DownstreamHandler)
        self.url = "http://127.0.0.1:%s/improve" % self.server.server_address[1]
        self.base_url = "http://127.0.0.1:%s" % self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, *_args):
        self.server.shutdown()
        self.thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
