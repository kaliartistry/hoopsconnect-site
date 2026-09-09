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
_RENDERED_DOM_EXPRESSION = (
    "(() => {"
    "const root = typeof document === 'undefined' "
    "? null : document.documentElement;"
    "if (root == null) {"
    "return {documentReady:false,state:null,status:null,html:null};"
    "}"
    "return {documentReady:true,"
    "state:document.body?.dataset.conformance ?? null,"
    "status:document.querySelector('#status')?.textContent ?? null,"
    "html:root.outerHTML};"
    "})()"
)


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


class _WebSocketDeadlineExceeded(RuntimeError):
    pass


def _remaining_budget(deadline, monotonic, timeout_message):
    remaining = deadline - monotonic()
    if remaining <= 0:
        raise _WebSocketDeadlineExceeded(timeout_message)
    return remaining


class _WebSocket:
    def __init__(
        self,
        url,
        timeout_seconds=None,
        *,
        deadline=None,
        monotonic=None,
    ):
        self.monotonic = monotonic or time.monotonic
        if deadline is None:
            if timeout_seconds is None:
                raise ValueError("timeout_seconds or deadline is required")
            deadline = self.monotonic() + timeout_seconds
        self.deadline = deadline
        parsed = urlparse(url)
        timeout_message = "Chrome DevTools WebSocket upgrade timed out"
        try:
            remaining = _remaining_budget(
                self.deadline, self.monotonic, timeout_message
            )
            self.connection = socket.create_connection(
                (parsed.hostname, parsed.port), timeout=remaining
            )
        except TimeoutError as error:
            raise _WebSocketDeadlineExceeded(timeout_message) from error
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
            remaining = _remaining_budget(
                self.deadline, self.monotonic, timeout_message
            )
            self.connection.settimeout(remaining)
            try:
                self.connection.sendall(request_bytes)
            except TimeoutError as error:
                raise _WebSocketDeadlineExceeded(timeout_message) from error
            response = bytearray()
            while b"\r\n\r\n" not in response:
                remaining = _remaining_budget(
                    self.deadline, self.monotonic, timeout_message
                )
                self.connection.settimeout(remaining)
                try:
                    chunk = self.connection.recv(4096)
                except TimeoutError as error:
                    raise _WebSocketDeadlineExceeded(timeout_message) from error
                if not chunk:
                    raise RuntimeError(
                        "Chrome DevTools WebSocket upgrade closed before "
                        "headers completed"
                    )
                response.extend(chunk)
            _remaining_budget(self.deadline, self.monotonic, timeout_message)
            if b" 101 " not in bytes(response).split(b"\r\n", 1)[0]:
                raise RuntimeError(
                    "Chrome rejected the DevTools WebSocket upgrade"
                )
        except BaseException:
            self.connection.close()
            raise

    def close(self):
        self.connection.close()

    def _operation_deadline(self, deadline):
        return self.deadline if deadline is None else deadline

    def _set_io_timeout(self, deadline, operation):
        timeout_message = f"Chrome DevTools {operation} timed out"
        remaining = _remaining_budget(
            self._operation_deadline(deadline),
            self.monotonic,
            timeout_message,
        )
        self.connection.settimeout(remaining)

    def _require_operation_budget(self, deadline, operation):
        return _remaining_budget(
            self._operation_deadline(deadline),
            self.monotonic,
            f"Chrome DevTools {operation} timed out",
        )

    def _send_frame(
        self,
        opcode,
        payload=b"",
        *,
        deadline=None,
        operation="command",
    ):
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
        self._set_io_timeout(deadline, operation)
        try:
            self.connection.sendall(header)
        except TimeoutError as error:
            raise _WebSocketDeadlineExceeded(
                f"Chrome DevTools {operation} timed out"
            ) from error
        self._require_operation_budget(deadline, operation)

    def send_json(self, value, *, deadline=None, operation="command"):
        self._send_frame(
            0x1,
            json.dumps(value, separators=(",", ":")).encode(),
            deadline=deadline,
            operation=operation,
        )

    def _receive_exact(self, length, deadline, operation):
        chunks = bytearray()
        while len(chunks) < length:
            self._set_io_timeout(deadline, operation)
            try:
                chunk = self.connection.recv(length - len(chunks))
            except TimeoutError as error:
                raise _WebSocketDeadlineExceeded(
                    f"Chrome DevTools {operation} timed out"
                ) from error
            if not chunk:
                raise RuntimeError("Chrome DevTools socket closed unexpectedly")
            chunks.extend(chunk)
        return bytes(chunks)

    def receive_json(self, *, deadline=None, operation="command"):
        while True:
            operation_deadline = self._operation_deadline(deadline)
            first, second = self._receive_exact(
                2, operation_deadline, operation
            )
            opcode = first & 0x0F
            length = second & 0x7F
            if length == 126:
                length = struct.unpack(
                    "!H", self._receive_exact(2, operation_deadline, operation)
                )[0]
            elif length == 127:
                length = struct.unpack(
                    "!Q", self._receive_exact(8, operation_deadline, operation)
                )[0]
            mask = (
                self._receive_exact(4, operation_deadline, operation)
                if second & 0x80
                else None
            )
            payload = self._receive_exact(length, operation_deadline, operation)
            if mask:
                payload = bytes(
                    byte ^ mask[index % 4] for index, byte in enumerate(payload)
                )
            self._require_operation_budget(operation_deadline, operation)
            if opcode == 0x8:
                raise RuntimeError("Chrome DevTools socket closed unexpectedly")
            if opcode == 0x9:
                self._send_frame(
                    0xA,
                    payload,
                    deadline=operation_deadline,
                    operation=operation,
                )
                continue
            if opcode == 0x1:
                return json.loads(payload)

    def command(self, identifier, method, params=None, *, deadline=None):
        operation_deadline = self._operation_deadline(deadline)
        self.send_json(
            {"id": identifier, "method": method, "params": params or {}},
            deadline=operation_deadline,
            operation=method,
        )
        while True:
            message = self.receive_json(
                deadline=operation_deadline,
                operation=method,
            )
            self._require_operation_budget(operation_deadline, method)
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


def _format_evaluation_exception(details):
    if not isinstance(details, dict):
        return repr(details)
    parts = []
    text = details.get("text")
    if text:
        parts.append(str(text))
    exception = details.get("exception")
    if isinstance(exception, dict):
        description = exception.get("description") or exception.get("value")
        if description:
            parts.append(str(description))
    line = details.get("lineNumber")
    column = details.get("columnNumber")
    if isinstance(line, int) and isinstance(column, int):
        parts.append(f"line={line + 1} column={column + 1}")
    if not parts:
        parts.append(json.dumps(details, sort_keys=True, separators=(",", ":")))
    return "; ".join(parts)[:2000]


def _sleep_before_dom_retry(deadline, monotonic, sleep):
    remaining = deadline - monotonic()
    if remaining > 0:
        sleep(min(0.05, remaining))


def _completion_timeout(last_evaluation_error):
    message = "optimized Dart2JS JavaScript completion timed out"
    if last_evaluation_error is not None:
        message += f"; last evaluation error: {last_evaluation_error}"
    return RuntimeError(message)


def _poll_rendered_dom(
    websocket,
    deadline,
    monotonic=time.monotonic,
    sleep=time.sleep,
):
    identifier = 0
    last_evaluation_error = None
    last_reported_error = None
    while monotonic() < deadline:
        identifier += 1
        try:
            response = websocket.command(
                identifier,
                "Runtime.evaluate",
                {
                    "expression": _RENDERED_DOM_EXPRESSION,
                    "returnByValue": True,
                },
                deadline=deadline,
            )
        except _WebSocketDeadlineExceeded as error:
            raise _completion_timeout(last_evaluation_error) from error
        except RuntimeError as error:
            diagnostic = str(error)
            if not diagnostic.startswith("Chrome DevTools Runtime.evaluate failed:"):
                raise
            last_evaluation_error = diagnostic
        else:
            if monotonic() >= deadline:
                raise _completion_timeout(last_evaluation_error)
            evaluation = response.get("result")
            if not isinstance(evaluation, dict):
                raise RuntimeError(
                    "optimized Dart2JS Runtime.evaluate returned no result object"
                )
            exception_details = evaluation.get("exceptionDetails")
            if exception_details is not None:
                last_evaluation_error = _format_evaluation_exception(
                    exception_details
                )
            else:
                remote_result = evaluation.get("result")
                value = (
                    remote_result.get("value")
                    if isinstance(remote_result, dict)
                    else None
                )
                if not isinstance(value, dict):
                    raise RuntimeError(
                        "optimized Dart2JS Runtime.evaluate returned no value object"
                    )
                if not value.get("documentReady"):
                    _sleep_before_dom_retry(deadline, monotonic, sleep)
                    continue
                if value.get("state") == "failed":
                    raise RuntimeError(
                        "optimized Dart2JS JavaScript failed: "
                        f"{value.get('status')!r}"
                    )
                if value.get("state") == "passed":
                    rendered_html = value.get("html")
                    if not isinstance(rendered_html, str):
                        raise RuntimeError(
                            "optimized Dart2JS passed without rendered HTML"
                        )
                    if monotonic() >= deadline:
                        raise _completion_timeout(last_evaluation_error)
                    return rendered_html
                _sleep_before_dom_retry(deadline, monotonic, sleep)
                continue
        if last_evaluation_error != last_reported_error:
            print(
                "optimized Dart2JS Runtime.evaluate was transiently unavailable; "
                f"retrying: {last_evaluation_error}",
                file=sys.stderr,
            )
            last_reported_error = last_evaluation_error
        _sleep_before_dom_retry(deadline, monotonic, sleep)
    raise _completion_timeout(last_evaluation_error)


def _capture_rendered_dom(
    websocket_url,
    deadline,
    monotonic=time.monotonic,
    sleep=time.sleep,
):
    websocket = _WebSocket(
        websocket_url,
        deadline=deadline,
        monotonic=monotonic,
    )
    try:
        return _poll_rendered_dom(
            websocket,
            deadline,
            monotonic=monotonic,
            sleep=sleep,
        )
    finally:
        websocket.close()


def _request_browser_close(port, browser_path):
    websocket = _WebSocket(f"ws://127.0.0.1:{port}{browser_path}", 2)
    try:
        websocket.send_json(
            {"id": 1, "method": "Browser.close", "params": {}},
            operation="Browser.close",
        )
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
