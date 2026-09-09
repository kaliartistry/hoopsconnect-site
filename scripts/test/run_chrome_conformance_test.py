import importlib.util
import pathlib
import socket
import subprocess
import unittest
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
            mock.patch.object(runner.time, "monotonic", side_effect=[10.0, 11.0]),
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
            mock.patch.object(runner.time, "monotonic", side_effect=[10.0, 10.8]),
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
