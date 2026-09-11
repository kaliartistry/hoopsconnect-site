#!/usr/bin/env python3

import argparse
import contextlib
import http.server
import json
import mimetypes
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import unquote, urlparse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from run_chrome_conformance import (  # noqa: E402
    _WebSocket,
    _cleanup_profile,
    _request_browser_close,
    _stop_failed_process,
    _wait_for_devtools,
    _wait_for_page_target,
)


def parse_headers(config_path):
    config = json.loads(config_path.read_text(encoding="utf-8"))
    for entry in config.get("hosting", {}).get("headers", []):
        if entry.get("source") == "**":
            return {header["key"]: header["value"] for header in entry["headers"]}
    raise RuntimeError(f"{config_path} has no Hosting ** header set")


def validate_build(build_dir, headers, *, require_bundled_renderer=True):
    required = [
        "index.html",
        "flutter_bootstrap.js",
        "main.dart.js",
        "manifest.json",
        "flutter_service_worker.js",
        "canvaskit/canvaskit.js",
        "canvaskit/canvaskit.wasm",
    ]
    missing = [name for name in required if not (build_dir / name).is_file()]
    if missing:
        raise RuntimeError(f"web build is incomplete: {', '.join(missing)}")

    csp = headers.get("Content-Security-Policy", "")
    if "https://www.gstatic.com/firebasejs/" not in csp:
        raise RuntimeError("candidate CSP does not permit the exact FlutterFire SDK path")
    if "https://www.gstatic.com/flutter-canvaskit" in csp:
        raise RuntimeError("candidate CSP must not depend on remote CanvasKit")
    if "script-src *" in csp or "connect-src *" in csp:
        raise RuntimeError("candidate CSP contains a broad wildcard")

    manifest = json.loads((build_dir / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("display") != "standalone" or not manifest.get("start_url"):
        raise RuntimeError("manifest is not installable as a standalone PWA")
    for icon in manifest.get("icons", []):
        if not (build_dir / icon["src"]).is_file():
            raise RuntimeError(f"manifest icon is missing: {icon['src']}")

    bootstrap = (build_dir / "flutter_bootstrap.js").read_text(encoding="utf-8")
    if require_bundled_renderer and "canvasKitBaseUrl: 'canvaskit/'" not in bootstrap:
        raise RuntimeError("release bootstrap is not pinned to bundled CanvasKit")
    worker = (build_dir / "flutter_service_worker.js").read_text(encoding="utf-8")
    if "self.registration.unregister()" not in worker:
        raise RuntimeError("Flutter 3.41 update worker does not unregister stale caches")
    if "caches.open(" in worker:
        raise RuntimeError("Flutter 3.41 build unexpectedly enables a persistent app cache")
    for forbidden in ["publicData/", "gameStats/", "memberships/", "users/"]:
        if forbidden in worker:
            raise RuntimeError(f"service worker persistently caches private path {forbidden}")


class HostingHandler(http.server.BaseHTTPRequestHandler):
    build_dir = None
    response_headers = None

    def do_GET(self):
        requested = unquote(urlparse(self.path).path).lstrip("/")
        candidate = (self.build_dir / requested).resolve()
        if self.build_dir not in candidate.parents and candidate != self.build_dir:
            self.send_error(404)
            return
        if not candidate.is_file():
            candidate = self.build_dir / "index.html"
        data = candidate.read_bytes()
        content_type = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
        if candidate.suffix == ".wasm":
            content_type = "application/wasm"
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        for key, value in self.response_headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, _format, *_args):
        return


@contextlib.contextmanager
def serve(build_dir, headers):
    handler = type(
        "ConfiguredHostingHandler",
        (HostingHandler,),
        {"build_dir": build_dir, "response_headers": headers},
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_address[1]
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def find_chrome(explicit=None):
    candidates = [
        explicit,
        shutil.which("google-chrome"),
        shutil.which("google-chrome-stable"),
        shutil.which("chromium"),
        shutil.which("chromium-browser"),
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    ]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).is_file():
            return candidate
    raise RuntimeError("Chrome or Chromium is required for the web boot smoke test")


def evaluate(websocket, identifier, expression, deadline):
    response = websocket.command(
        identifier,
        "Runtime.evaluate",
        {"expression": expression, "returnByValue": True, "awaitPromise": True},
        deadline=deadline,
    )
    result = response.get("result", {})
    if result.get("exceptionDetails"):
        raise RuntimeError(f"browser evaluation failed: {result['exceptionDetails']}")
    return result.get("result", {}).get("value")


BOOT_STATE = r"""
(() => ({
  readyState: document.readyState,
  title: document.title,
  flutterRoot: Boolean(
    document.querySelector('flutter-view') ||
    document.querySelector('flt-glass-pane')
  ),
  manifest: document.querySelector('link[rel="manifest"]')?.href || null,
  resources: performance.getEntriesByType('resource').map((entry) => entry.name),
}))()
"""


def wait_for_flutter_frame(websocket, deadline, first_identifier):
    identifier = first_identifier
    last = None
    while time.monotonic() < deadline:
        identifier += 1
        last = evaluate(websocket, identifier, BOOT_STATE, deadline)
        if last and last.get("flutterRoot"):
            resources = last.get("resources", [])
            if any("/flutter-canvaskit/" in resource for resource in resources):
                raise RuntimeError("browser requested remote CanvasKit")
            if not any("/canvaskit/" in resource for resource in resources):
                raise RuntimeError("Flutter rendered without the bundled CanvasKit evidence")
            return identifier, last
        time.sleep(0.1)
    raise RuntimeError(f"Flutter did not render a first frame; last browser state: {last}")


def run_browser(chrome, page_url, timeout_seconds):
    profile = tempfile.mkdtemp(prefix="hoopsconnect-web-smoke-")
    process = None
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as stderr_file:
        try:
            process = subprocess.Popen(
                [
                    chrome,
                    "--headless=new",
                    "--disable-default-apps",
                    "--disable-extensions",
                    "--disable-sync",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--no-sandbox",
                    "--remote-allow-origins=*",
                    "--remote-debugging-port=0",
                    f"--user-data-dir={profile}",
                    page_url,
                ],
                stdout=subprocess.DEVNULL,
                stderr=stderr_file,
                text=True,
            )
            deadline = time.monotonic() + timeout_seconds
            port, browser_path = _wait_for_devtools(profile, process, deadline)
            page_socket = _wait_for_page_target(port, page_url, deadline)
            websocket = _WebSocket(page_socket, deadline=deadline)
            try:
                websocket.command(1, "Runtime.enable", deadline=deadline)
                identifier, first = wait_for_flutter_frame(websocket, deadline, 1)
                if not first.get("title", "").endswith("HoopsConnect") or not first.get("manifest"):
                    raise RuntimeError(f"PWA metadata did not survive boot: {first}")

                identifier += 1
                websocket.command(
                    identifier,
                    "Page.reload",
                    {"ignoreCache": True},
                    deadline=deadline,
                )
                identifier, second = wait_for_flutter_frame(websocket, deadline, identifier)
                identifier += 1
                registrations = evaluate(
                    websocket,
                    identifier,
                    "navigator.serviceWorker.getRegistrations().then((items) => items.length)",
                    deadline,
                )
                if registrations != 0:
                    raise RuntimeError(
                        "Flutter 3.41 stale app-shell worker remained registered after update boot"
                    )
                print(
                    "HOOPSCONNECT_WEB_BOOT_OK "
                    "fresh=true update=true staleWorker=false "
                    f"resources={len(second.get('resources', []))}"
                )
            finally:
                websocket.close()
            _request_browser_close(port, browser_path)
            process.wait(timeout=5)
        except Exception:
            if process is not None:
                _stop_failed_process(process)
            stderr_file.seek(0)
            stderr_text = stderr_file.read().strip()
            if stderr_text:
                print(stderr_text[-4000:], file=sys.stderr)
            raise
        finally:
            _cleanup_profile(profile)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-dir", default="build/web")
    parser.add_argument("--config", default="firebase.qa.json")
    parser.add_argument("--chrome")
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument(
        "--reproduce-legacy-renderer",
        action="store_true",
        help="Run the pre-fix generated bootstrap to reproduce F-01.",
    )
    args = parser.parse_args()

    build_dir = pathlib.Path(args.build_dir).resolve()
    headers = parse_headers(pathlib.Path(args.config).resolve())
    validate_build(
        build_dir,
        headers,
        require_bundled_renderer=not args.reproduce_legacy_renderer,
    )
    with serve(build_dir, headers) as port:
        run_browser(find_chrome(args.chrome), f"http://127.0.0.1:{port}/", args.timeout)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"WEB_BOOT_SMOKE_FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
