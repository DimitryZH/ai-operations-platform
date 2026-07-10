import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from telegram_adapter.status_snapshot import (
    OpenClawStatusClient,
)


class HealthHandler(BaseHTTPRequestHandler):
    status_code = 200
    payload = {"ok": True, "status": "healthy"}

    def do_GET(self) -> None:
        if self.path != "/health":
            self.send_response(404)
            self.end_headers()
            return

        body = json.dumps(self.payload).encode("utf-8")
        self.send_response(self.status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        return


class OpenClawStatusClientTests(unittest.TestCase):
    def test_snapshot_reports_reachable_loopback_health(self) -> None:
        with health_server(status_code=200, payload={"ok": True}) as base_url:
            snapshot = OpenClawStatusClient(base_url=base_url).snapshot()

        self.assertEqual(snapshot.adapter_status, "ready")
        self.assertEqual(snapshot.openclaw_health, "healthy")
        self.assertEqual(snapshot.openclaw_status, "private runtime reachable")

    def test_snapshot_reports_unready_on_http_error(self) -> None:
        with health_server(status_code=503, payload={"ok": False}) as base_url:
            snapshot = OpenClawStatusClient(base_url=base_url).snapshot()

        self.assertEqual(snapshot.adapter_status, "ready")
        self.assertEqual(snapshot.openclaw_health, "http 503")
        self.assertEqual(snapshot.openclaw_status, "private runtime not ready")

    def test_snapshot_rejects_non_loopback_base_url(self) -> None:
        with self.assertRaises(ValueError):
            OpenClawStatusClient(base_url="https://example.com")

    def test_snapshot_rejects_non_http_scheme(self) -> None:
        with self.assertRaises(ValueError):
            OpenClawStatusClient(base_url="file:///tmp/status")


class health_server:
    def __init__(self, status_code: int, payload: dict[str, object]) -> None:
        self._status_code = status_code
        self._payload = payload
        self._server: ThreadingHTTPServer | None = None
        self._thread: threading.Thread | None = None

    def __enter__(self) -> str:
        handler = type(
            "ScopedHealthHandler",
            (HealthHandler,),
            {
                "status_code": self._status_code,
                "payload": self._payload,
            },
        )
        self._server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self._thread = threading.Thread(
            target=self._server.serve_forever,
            daemon=True,
        )
        self._thread.start()
        host, port = self._server.server_address
        return f"http://{host}:{port}"

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
        if self._thread is not None:
            self._thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
