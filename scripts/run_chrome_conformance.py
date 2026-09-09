#!/usr/bin/env python3

import os
import pathlib
import re
import signal
import subprocess
import sys


if len(sys.argv) != 3:
    raise SystemExit("usage: run_chrome_conformance.py CHROME HARNESS_HTML")

chrome = sys.argv[1]
harness = pathlib.Path(sys.argv[2]).resolve()
profile = harness.parent / "chrome-profile"
marker = "HOOPSCONNECT_DART2JS_OK"
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
        f"--user-data-dir={profile}",
        "--virtual-time-budget=5000",
        "--dump-dom",
        harness.as_uri(),
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    start_new_session=True,
)

try:
    stdout, stderr = process.communicate(timeout=12)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    stdout, stderr = process.communicate(timeout=5)

if marker not in stdout:
    sys.stderr.write(stdout)
    sys.stderr.write(stderr)
    raise SystemExit("optimized Dart2JS conformance marker was not rendered")

match = re.search(r"HOOPSCONNECT_DART2JS_OK[^<]*", stdout)
print(match.group(0) if match else marker)
