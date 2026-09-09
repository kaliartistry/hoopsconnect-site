#!/usr/bin/env python3

from html.parser import HTMLParser
import base64
import json
import os
import pathlib
import secrets
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
from urllib import request
from urllib.parse import urlencode, urlparse


EXPECTED_CASES = 61


def expected_status(case_count=EXPECTED_CASES):
    return (
        f"HOOPSCONNECT_DART2JS_OK cases={case_count} "
        "numeric=2 unicode=17-distinct immutable=true"
    )


class _RenderedStateParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.body_state = None
        self.dart_execution_challenge = None
        self.status_depth = 0
        self.status_text = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "body":
            self.body_state = attributes.get("data-conformance")
            self.dart_execution_challenge = attributes.get(
                "data-dart-execution-challenge"
            )
        if self.status_depth:
            self.status_depth += 1
        elif attributes.get("id") == "status":
            self.status_depth = 1

    def handle_endtag(self, _tag):
        if self.status_depth:
            self.status_depth -= 1

    def handle_data(self, data):
        if self.status_depth:
            self.status_text.append(data)


def validate_rendered_dom(
    rendered_html, expected_challenge, case_count=EXPECTED_CASES
):
    parser = _RenderedStateParser()
    parser.feed(rendered_html)
    parser.close()
    rendered_status = "".join(parser.status_text).strip()
    required_status = expected_status(case_count)
    if parser.body_state != "passed":
        raise RuntimeError(
            f"optimized Dart2JS body state was {parser.body_state!r}, not 'passed'"
        )
    if rendered_status != required_status:
        raise RuntimeError(
            f"optimized Dart2JS rendered status was {rendered_status!r}, "
            f"not {required_status!r}"
        )
    if parser.dart_execution_challenge != expected_challenge:
        raise RuntimeError(
            "optimized Dart2JS execution challenge was "
            f"{parser.dart_execution_challenge!r}, not {expected_challenge!r}"
        )
    return required_status


def _receive_exact(connection, length):
    chunks = bytearray()
    while len(chunks) < length:
        chunk = connection.recv(length - len(chunks))
        if not chunk:
            raise RuntimeError("Chrome DevTools socket closed unexpectedly")
        chunks.extend(chunk)
    return bytes(chunks)


class _WebSocket:
    def __init__(self, url, timeout_seconds):
        parsed = urlparse(url)
        handshake_deadline = time.monotonic() + timeout_seconds
        try:
            self.connection = socket.create_connection(
                (parsed.hostname, parsed.port), timeout=timeout_seconds
            )
        except TimeoutError as error:
            raise RuntimeError(
                "Chrome DevTools WebSocket upgrade timed out"
            ) from error
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        target = parsed.path + (f"?{parsed.query}" if parsed.query else "")
        request_bytes = (
            f"GET {target} HTTP/1.1\r\n"
            f"Host: {parsed.hostname}:{parsed.port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode("ascii")
        try:
            remaining = handshake_deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(
                    "Chrome DevTools WebSocket upgrade timed out"
                )
            self.connection.settimeout(remaining)
            self.connection.sendall(request_bytes)
            response = bytearray()
            while b"\r\n\r\n" not in response:
                remaining = handshake_deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError(
                        "Chrome DevTools WebSocket upgrade timed out"
                    )
                self.connection.settimeout(remaining)
                try:
                    chunk = self.connection.recv(4096)
                except TimeoutError as error:
                    raise RuntimeError(
                        "Chrome DevTools WebSocket upgrade timed out"
                    ) from error
                if not chunk:
                    raise RuntimeError(
                        "Chrome DevTools WebSocket upgrade closed before "
                        "headers completed"
                    )
                response.extend(chunk)
            if b" 101 " not in bytes(response).split(b"\r\n", 1)[0]:
                raise RuntimeError(
                    "Chrome rejected the DevTools WebSocket upgrade"
                )
        except TimeoutError as error:
            self.connection.close()
            raise RuntimeError(
                "Chrome DevTools WebSocket upgrade timed out"
            ) from error
        except BaseException:
            self.connection.close()
            raise

    def close(self):
        self.connection.close()

    def _send_frame(self, opcode, payload=b""):
        header = bytearray([0x80 | opcode])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        mask = os.urandom(4)
        header.extend(mask)
        header.extend(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.connection.sendall(header)

    def send_json(self, value):
        self._send_frame(0x1, json.dumps(value, separators=(",", ":")).encode())

    def receive_json(self):
        while True:
            first, second = _receive_exact(self.connection, 2)
            opcode = first & 0x0F
            length = second & 0x7F
            if length == 126:
                length = struct.unpack("!H", _receive_exact(self.connection, 2))[0]
            elif length == 127:
                length = struct.unpack("!Q", _receive_exact(self.connection, 8))[0]
            mask = _receive_exact(self.connection, 4) if second & 0x80 else None
            payload = _receive_exact(self.connection, length)
            if mask:
                payload = bytes(
                    byte ^ mask[index % 4] for index, byte in enumerate(payload)
                )
            if opcode == 0x8:
                raise RuntimeError("Chrome DevTools socket closed unexpectedly")
            if opcode == 0x9:
                self._send_frame(0xA, payload)
                continue
            if opcode == 0x1:
                return json.loads(payload)

    def command(self, identifier, method, params=None):
        self.send_json(
            {"id": identifier, "method": method, "params": params or {}}
        )
        while True:
            message = self.receive_json()
            if message.get("id") == identifier:
                if "error" in message:
                    raise RuntimeError(
                        f"Chrome DevTools {method} failed: {message['error']}"
                    )
                return message


def _wait_for_devtools(profile, process, deadline):
    active_port = pathlib.Path(profile) / "DevToolsActivePort"
    while time.monotonic() < deadline:
        if active_port.exists():
            lines = active_port.read_text(encoding="utf-8").splitlines()
            if len(lines) >= 2:
                return int(lines[0]), lines[1]
        if process.poll() is not None:
            raise RuntimeError(
                f"optimized Dart2JS Chrome process exited early with {process.returncode}"
            )
        time.sleep(0.05)
    raise RuntimeError("optimized Dart2JS Chrome DevTools startup timed out")


def _wait_for_page_target(port, harness_url, deadline):
    while time.monotonic() < deadline:
        try:
            with request.urlopen(
                f"http://127.0.0.1:{port}/json/list", timeout=0.5
            ) as response:
                targets = json.load(response)
            for target in targets:
                if target.get("type") == "page" and target.get("url") == harness_url:
                    return target["webSocketDebuggerUrl"]
        except (OSError, ValueError):
            pass
        time.sleep(0.05)
    raise RuntimeError("optimized Dart2JS Chrome page startup timed out")


def _capture_rendered_dom(websocket_url, deadline):
    websocket = _WebSocket(websocket_url, max(1, deadline - time.monotonic()))
    try:
        identifier = 0
        while time.monotonic() < deadline:
            identifier += 1
            response = websocket.command(
                identifier,
                "Runtime.evaluate",
                {
                    "expression": (
                        "({state:document.body?.dataset.conformance ?? null,"
                        "status:document.querySelector('#status')?.textContent ?? null,"
                        "html:document.documentElement.outerHTML})"
                    ),
                    "returnByValue": True,
                },
            )
            evaluation = response["result"]
            if "exceptionDetails" in evaluation:
                raise RuntimeError("optimized Dart2JS JavaScript evaluation failed")
            value = evaluation["result"].get("value", {})
            if value.get("state") == "failed":
                raise RuntimeError(
                    f"optimized Dart2JS JavaScript failed: {value.get('status')!r}"
                )
            if value.get("state") == "passed":
                return value["html"]
            time.sleep(0.05)
    finally:
        websocket.close()
    raise RuntimeError("optimized Dart2JS JavaScript completion timed out")


def _request_browser_close(port, browser_path):
    websocket = _WebSocket(f"ws://127.0.0.1:{port}{browser_path}", 2)
    try:
        websocket.send_json({"id": 1, "method": "Browser.close", "params": {}})
    finally:
        websocket.close()


def require_successful_process(process, stderr, timeout_seconds=8):
    try:
        returncode = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("optimized Dart2JS Chrome process exit timed out") from error
    if returncode != 0:
        raise RuntimeError(
            "optimized Dart2JS Chrome process failed "
            f"with exit {returncode}: {stderr.strip()}"
        )


def _stop_failed_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)


def _cleanup_profile(profile):
    for _ in range(20):
        try:
            shutil.rmtree(profile)
            return
        except OSError:
            time.sleep(0.05)


def run_chrome(chrome, harness, case_count=EXPECTED_CASES, timeout_seconds=20):
    execution_challenge = secrets.token_hex(32)
    harness_url = (
        f"{pathlib.Path(harness).resolve().as_uri()}?"
        f"{urlencode({'execution_challenge': execution_challenge})}"
    )
    profile = tempfile.mkdtemp(prefix="hoopsconnect-chrome-")
    process = None
    stderr_text = ""
    with tempfile.TemporaryFile(mode="w+", encoding="utf-8") as stderr_file:
        try:
            process = subprocess.Popen(
                [
                    chrome,
                    "--headless=new",
                    "--disable-background-networking",
                    "--disable-default-apps",
                    "--disable-extensions",
                    "--disable-gpu",
                    "--disable-sync",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--no-sandbox",
                    "--remote-allow-origins=*",
                    "--remote-debugging-port=0",
                    f"--user-data-dir={profile}",
                    harness_url,
                ],
                stdout=subprocess.DEVNULL,
                stderr=stderr_file,
                text=True,
            )
            deadline = time.monotonic() + timeout_seconds
            port, browser_path = _wait_for_devtools(profile, process, deadline)
            page_url = _wait_for_page_target(port, harness_url, deadline)
            rendered_html = _capture_rendered_dom(page_url, deadline)
            status = validate_rendered_dom(
                rendered_html, execution_challenge, case_count
            )
            _request_browser_close(port, browser_path)
            stderr_file.seek(0)
            stderr_text = stderr_file.read()
            require_successful_process(process, stderr_text)
            return status
        finally:
            if process is not None:
                _stop_failed_process(process)
            _cleanup_profile(profile)


def main(argv):
    if len(argv) != 3:
        raise SystemExit("usage: run_chrome_conformance.py CHROME HARNESS_HTML")
    try:
        status = run_chrome(argv[1], argv[2])
    except RuntimeError as error:
        raise SystemExit(str(error)) from error
    print(status)


if __name__ == "__main__":
    main(sys.argv)
