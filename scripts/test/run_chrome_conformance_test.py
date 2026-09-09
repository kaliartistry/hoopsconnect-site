import importlib.util
import pathlib
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


if __name__ == "__main__":
    unittest.main()
