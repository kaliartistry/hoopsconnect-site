import importlib.util
import io
import json
import pathlib
import socket
import subprocess
import unittest
from contextlib import redirect_stderr
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).parents[1] / "run_chrome_conformance.py"
SPEC = importlib.util.spec_from_file_location("run_chrome_conformance", MODULE_PATH)
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


CHALLENGE = "a" * 64


def rendered(status=None, body_state=None, challenge=None, script=""):
    body_attribute = (
        f' data-conformance="{body_state}"' if body_state is not None else ""
    )
    challenge_attribute = (
        f' data-dart-execution-challenge="{challenge}"'
        if challenge is not None
        else ""
    )
    status_text = status or "Running optimized Dart2JS conformance..."
    return (
        f"<!doctype html><html><body{body_attribute}{challenge_attribute}>"
        f'<main id="status">{status_text}</main><script>{script}</script>'
        "</body></html>"
    )


def evaluation(value=None, exception_details=None):
    result = {}
    if value is not None:
        result["result"] = {"type": "object", "value": value}
    if exception_details is not None:
        result["exceptionDetails"] = exception_details
    return {"id": 1, "result": result}


class _FakeClock:
    def __init__(self):
        self.now = 0.0

    def monotonic(self):
        return self.now

    def sleep(self, duration):
        self.now += duration


class _FakeWebSocket:
    def __init__(self, responses):
        self.responses = list(responses)
        self.commands = []

    def command(self, identifier, method, params=None, *, deadline=None):
        self.commands.append((identifier, method, params, deadline))
        response = self.responses[0]
        if len(self.responses) > 1:
            self.responses.pop(0)
        if isinstance(response, BaseException):
            raise response
        return response

    def close(self):
        pass


class _AdvancingConnection:
    def __init__(self, clock, chunks, recv_advances):
        self.clock = clock
        self.chunks = list(chunks)
        self.recv_advances = list(recv_advances)
        self.timeouts = []
        self.sent = []
        self.close = mock.Mock()

    def settimeout(self, timeout):
        if timeout <= 0:
            raise AssertionError("socket timeout must be strictly positive")
        self.timeouts.append(timeout)

    def sendall(self, payload):
        self.sent.append(payload)

    def recv(self, length):
        self.clock.now += self.recv_advances.pop(0)
        chunk = self.chunks.pop(0)
        if len(chunk) > length:
            self.chunks.insert(0, chunk[length:])
            self.recv_advances.insert(0, 0.0)
            return chunk[:length]
        return chunk


def server_frame(opcode, payload=b""):
    if len(payload) >= 126:
        raise ValueError("test frames must use the short payload form")
    return bytes([0x80 | opcode, len(payload)]) + payload


def transport_websocket(connection, clock, deadline=1.0):
    websocket = object.__new__(runner._WebSocket)
    websocket.connection = connection
    websocket.monotonic = clock.monotonic
    websocket.deadline = deadline
    return websocket


class RenderedDomValidationTest(unittest.TestCase):
    def test_accepts_exact_rendered_status_and_independent_pass_state(self):
        expected = runner.expected_status()
        self.assertEqual(
            runner.validate_rendered_dom(
                rendered(expected, "passed", CHALLENGE), CHALLENGE
            ),
            expected,
        )

    def test_static_script_marker_does_not_pass(self):
        static = rendered(script=f'const marker = "{runner.expected_status()}";')
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(static, CHALLENGE)

    def test_static_premarked_page_without_random_challenge_does_not_pass(self):
        static = rendered(runner.expected_status(), "passed")
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(static, CHALLENGE)

    def test_wrong_execution_challenge_does_not_pass(self):
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(
                rendered(runner.expected_status(), "passed", "b" * 64),
                CHALLENGE,
            )

    def test_status_without_independent_body_state_does_not_pass(self):
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(rendered(runner.expected_status()), CHALLENGE)

    def test_wrong_case_count_does_not_pass(self):
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(
                rendered(
                    runner.expected_status(runner.EXPECTED_CASES - 1),
                    "passed",
                    CHALLENGE,
                ),
                CHALLENGE,
            )

    def test_missing_javascript_does_not_pass(self):
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(rendered(), CHALLENGE)

    def test_javascript_failure_state_does_not_pass(self):
        with self.assertRaises(RuntimeError):
            runner.validate_rendered_dom(
                rendered("FAILED: simulated", "failed", CHALLENGE), CHALLENGE
            )


class ChromeProcessValidationTest(unittest.TestCase):
    def test_failed_process_does_not_pass(self):
        process = mock.Mock()
        process.wait.return_value = 1
        with self.assertRaises(RuntimeError):
            runner.require_successful_process(process, "simulated failure")

    def test_timeout_does_not_pass(self):
        process = mock.Mock()
        process.wait.side_effect = subprocess.TimeoutExpired("chrome", 20)
        with self.assertRaises(RuntimeError):
            runner.require_successful_process(process, "")


class RenderedDomPollingTest(unittest.TestCase):
    def _passed_value(self):
        return {
            "documentReady": True,
            "state": "passed",
            "status": runner.expected_status(),
            "html": rendered(runner.expected_status(), "passed", CHALLENGE),
        }

    def test_early_null_document_root_retries_without_failure(self):
        clock = _FakeClock()
        websocket = _FakeWebSocket(
            [
                evaluation(
                    {
                        "documentReady": False,
                        "state": None,
                        "status": None,
                        "html": None,
                    }
                ),
                evaluation(self._passed_value()),
            ]
        )

        html = runner._poll_rendered_dom(
            websocket,
            1.0,
            monotonic=clock.monotonic,
            sleep=clock.sleep,
        )

        self.assertIn('data-conformance="passed"', html)
        self.assertEqual(len(websocket.commands), 2)
        expression = websocket.commands[0][2]["expression"]
        self.assertIn("document.documentElement", expression)
        self.assertIn("root == null", expression)

    def test_transient_evaluation_exception_retries_with_diagnostics(self):
        clock = _FakeClock()
        exception_details = {
            "text": "Uncaught",
            "lineNumber": 0,
            "columnNumber": 53,
            "exception": {
                "className": "TypeError",
                "description": (
                    "TypeError: Cannot read properties of null "
                    "(reading 'outerHTML')"
                ),
            },
        }
        websocket = _FakeWebSocket(
            [
                evaluation(exception_details=exception_details),
                evaluation(self._passed_value()),
            ]
        )
        stderr = io.StringIO()

        with redirect_stderr(stderr):
            html = runner._poll_rendered_dom(
                websocket,
                1.0,
                monotonic=clock.monotonic,
                sleep=clock.sleep,
            )

        self.assertIn('data-conformance="passed"', html)
        self.assertIn("Cannot read properties of null", stderr.getvalue())
        self.assertIn("line=1 column=54", stderr.getvalue())

    def test_persistent_evaluation_exception_fails_with_last_diagnostics(self):
        clock = _FakeClock()
        websocket = _FakeWebSocket(
            [
                evaluation(
                    exception_details={
                        "text": "Uncaught",
                        "lineNumber": 2,
                        "columnNumber": 7,
                        "exception": {
                            "description": "TypeError: persistent simulated failure"
                        },
                    }
                )
            ]
        )
        stderr = io.StringIO()

        with redirect_stderr(stderr):
            with self.assertRaisesRegex(
                RuntimeError,
                "persistent simulated failure.*line=3 column=8",
            ):
                runner._poll_rendered_dom(
                    websocket,
                    0.11,
                    monotonic=clock.monotonic,
                    sleep=clock.sleep,
                )

        self.assertIn("persistent simulated failure", stderr.getvalue())
        self.assertGreaterEqual(len(websocket.commands), 2)

    def test_explicit_failed_body_state_is_immediately_fatal(self):
        clock = _FakeClock()
        websocket = _FakeWebSocket(
            [
                evaluation(
                    {
                        "documentReady": True,
                        "state": "failed",
                        "status": "FAILED: simulated Dart harness failure",
                        "html": rendered(
                            "FAILED: simulated Dart harness failure",
                            "failed",
                            CHALLENGE,
                        ),
                    }
                )
            ]
        )

        with self.assertRaisesRegex(RuntimeError, "simulated Dart harness failure"):
            runner._poll_rendered_dom(
                websocket,
                1.0,
                monotonic=clock.monotonic,
                sleep=clock.sleep,
            )
        self.assertEqual(len(websocket.commands), 1)

    def test_valid_pass_returned_after_deadline_is_rejected_and_socket_closes(self):
        clock = _FakeClock()
        websocket = _FakeWebSocket([evaluation(self._passed_value())])

        def late_command(identifier, method, params=None, *, deadline=None):
            clock.now = deadline + 0.01
            return evaluation(self._passed_value())

        websocket.command = late_command
        websocket.close = mock.Mock()

        with mock.patch.object(runner, "_WebSocket", return_value=websocket):
            with self.assertRaisesRegex(RuntimeError, "completion timed out"):
                runner._capture_rendered_dom(
                    "ws://127.0.0.1:9222/devtools/page/1",
                    1.0,
                    monotonic=clock.monotonic,
                    sleep=clock.sleep,
                )

        websocket.close.assert_called_once_with()

    def test_command_timeout_preserves_latest_evaluation_diagnostic(self):
        clock = _FakeClock()
        websocket = _FakeWebSocket(
            [
                evaluation(
                    exception_details={
                        "text": "Uncaught",
                        "exception": {
                            "description": "TypeError: retained diagnostic"
                        },
                    }
                ),
                runner._WebSocketDeadlineExceeded(
                    "Chrome DevTools Runtime.evaluate timed out"
                ),
            ]
        )

        with redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(
                RuntimeError,
                "completion timed out.*retained diagnostic",
            ):
                runner._poll_rendered_dom(
                    websocket,
                    1.0,
                    monotonic=clock.monotonic,
                    sleep=clock.sleep,
                )


class WebSocketCommandDeadlineTest(unittest.TestCase):
    def _capture_timeout(self, chunks, recv_advances):
        clock = _FakeClock()
        connection = _AdvancingConnection(clock, chunks, recv_advances)
        websocket = transport_websocket(connection, clock)

        with mock.patch.object(runner, "_WebSocket", return_value=websocket):
            with self.assertRaisesRegex(RuntimeError, "completion timed out"):
                runner._capture_rendered_dom(
                    "ws://127.0.0.1:9222/devtools/page/1",
                    1.0,
                    monotonic=clock.monotonic,
                    sleep=clock.sleep,
                )

        connection.close.assert_called_once_with()
        self.assertTrue(connection.timeouts)
        self.assertTrue(all(timeout > 0 for timeout in connection.timeouts))

    def test_partial_frame_reads_cannot_continue_across_deadline(self):
        self._capture_timeout([b"\x81", b"\x02"], [0.6, 0.5])

    def test_repeated_ping_frames_cannot_continue_across_deadline(self):
        ping = server_frame(0x9)
        self._capture_timeout(
            [ping, ping, ping, ping],
            [0.3, 0.3, 0.3, 0.3],
        )

    def test_unmatched_responses_cannot_continue_across_deadline(self):
        payload = json.dumps(
            {"id": 999, "result": {}}, separators=(",", ":")
        ).encode()
        frame = server_frame(0x1, payload)
        header, body = frame[:2], frame[2:]
        self._capture_timeout(
            [header, body, header, body, header, body],
            [0.0, 0.4, 0.0, 0.4, 0.0, 0.4],
        )


class RunChromeCleanupTest(unittest.TestCase):
    def test_capture_timeout_stops_chrome_and_cleans_profile(self):
        process = mock.Mock()
        profile = "/tmp/hoopsconnect-chrome-timeout-test"

        with (
            mock.patch.object(runner.tempfile, "mkdtemp", return_value=profile),
            mock.patch.object(runner.subprocess, "Popen", return_value=process),
            mock.patch.object(
                runner, "_wait_for_devtools", return_value=(9222, "/devtools/browser/1")
            ),
            mock.patch.object(
                runner,
                "_wait_for_page_target",
                return_value="ws://127.0.0.1:9222/devtools/page/1",
            ),
            mock.patch.object(
                runner,
                "_capture_rendered_dom",
                side_effect=RuntimeError(
                    "optimized Dart2JS JavaScript completion timed out"
                ),
            ),
            mock.patch.object(runner, "_stop_failed_process") as stop_process,
            mock.patch.object(runner, "_cleanup_profile") as cleanup_profile,
        ):
            with self.assertRaisesRegex(RuntimeError, "completion timed out"):
                runner.run_chrome("chrome", "harness.html", timeout_seconds=1)

        stop_process.assert_called_once_with(process)
        cleanup_profile.assert_called_once_with(profile)


class WebSocketUpgradeTest(unittest.TestCase):
    def _connection(self, chunks):
        connection = mock.Mock()
        connection.recv.side_effect = chunks
        return connection

    def test_failed_upgrade_eof_fails_immediately_and_closes(self):
        connection = self._connection([b""])
        with mock.patch.object(runner.socket, "create_connection", return_value=connection):
            with self.assertRaisesRegex(RuntimeError, "closed before headers completed"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 5)
        connection.close.assert_called_once_with()

    def test_partial_header_eof_fails_immediately_and_closes(self):
        connection = self._connection([b"HTTP/1.1 101 Switching", b""])
        with mock.patch.object(runner.socket, "create_connection", return_value=connection):
            with self.assertRaisesRegex(RuntimeError, "closed before headers completed"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 5)
        connection.close.assert_called_once_with()

    def test_overall_handshake_deadline_expires_despite_partial_progress(self):
        connection = self._connection([b"H", b"T"])
        with (
            mock.patch.object(runner.socket, "create_connection", return_value=connection),
            mock.patch.object(
                runner.time,
                "monotonic",
                side_effect=[10.0, 10.1, 10.25, 10.5, 11.0],
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "upgrade timed out"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 1)
        connection.close.assert_called_once_with()

    def test_connection_time_is_deducted_before_request_write(self):
        connection = self._connection([])
        with (
            mock.patch.object(runner.socket, "create_connection", return_value=connection),
            mock.patch.object(
                runner.time, "monotonic", side_effect=[10.0, 10.0, 11.0]
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "upgrade timed out"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 1)
        connection.sendall.assert_not_called()
        connection.close.assert_called_once_with()

    def test_request_write_uses_only_the_remaining_handshake_budget(self):
        connection = self._connection([])
        connection.sendall.side_effect = socket.timeout("simulated")
        with (
            mock.patch.object(runner.socket, "create_connection", return_value=connection),
            mock.patch.object(
                runner.time, "monotonic", side_effect=[10.0, 10.0, 10.8]
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "upgrade timed out"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 1)
        remaining_timeout = connection.settimeout.call_args_list[0].args[0]
        self.assertAlmostEqual(remaining_timeout, 0.2)
        connection.close.assert_called_once_with()

    def test_socket_timeout_is_reported_as_handshake_deadline_failure(self):
        connection = self._connection([socket.timeout("simulated")])
        with mock.patch.object(runner.socket, "create_connection", return_value=connection):
            with self.assertRaisesRegex(RuntimeError, "upgrade timed out"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 5)
        connection.close.assert_called_once_with()

    def test_rejected_upgrade_closes_the_socket(self):
        connection = self._connection([b"HTTP/1.1 403 Forbidden\r\n\r\n"])
        with mock.patch.object(runner.socket, "create_connection", return_value=connection):
            with self.assertRaisesRegex(RuntimeError, "rejected"):
                runner._WebSocket("ws://127.0.0.1:9222/devtools/page/1", 5)
        connection.close.assert_called_once_with()

    def test_fragmented_successful_header_completes_without_closing(self):
        connection = self._connection(
            [
                b"HTTP/1.1 101 Switch",
                b"ing Protocols\r\nUpgrade: websocket\r\n",
                b"Connection: Upgrade\r\n\r\n",
            ]
        )
        with mock.patch.object(runner.socket, "create_connection", return_value=connection):
            websocket = runner._WebSocket(
                "ws://127.0.0.1:9222/devtools/page/1?session=test", 5
            )
        connection.close.assert_not_called()
        connection.sendall.assert_called_once()
        self.assertEqual(connection.recv.call_count, 3)
        websocket.close()
        connection.close.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
