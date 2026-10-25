#!/usr/bin/env python3
"""Validate a real exported macOS app and run a bounded headless startup."""
import argparse
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile


def check(app):
    app = app.resolve()
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "io.github.l1xy6.trashbeats"
    assert info["CFBundleShortVersionString"] == "0.1.0"
    assert info.get("NSMicrophoneUsageDescription"), "Microphone purpose missing"
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    assert executable.is_file() and os.access(executable, os.X_OK), "Not executable"
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    assert set(architectures) == {"arm64", "x86_64"}, architectures
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
    signature = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True)
    entitlements = plistlib.loads(signature.stdout)
    assert entitlements.get("com.apple.security.device.audio-input") is True
    assert not entitlements.get("com.apple.security.get-task-allow", False)
    assert list((app / "Contents/Resources").glob("*.pck")), "Project resources missing"
    with tempfile.TemporaryDirectory(prefix="Trashbeats-MacStartup-") as temporary:
        env = os.environ.copy()
        env["HOME"] = temporary
        env.pop("TRASHBEATS_TIANQIN_APP_ID", None)
        env.pop("TRASHBEATS_TIANQIN_APP_KEY", None)
        result = subprocess.run(
            [str(executable), "--headless", "--audio-driver", "Dummy", "--quit-after", "120",
             "--log-file", str(Path(temporary) / "startup.log")],
            cwd=temporary, env=env, capture_output=True, text=True, timeout=90,
        )
        output = result.stdout + result.stderr
        print(output)
        assert result.returncode == 0, f"Startup exit {result.returncode}"
        assert "Godot Engine v4.7.1.stable.official.a13da4feb" in output
        assert "SCRIPT ERROR:" not in output and "ERROR:" not in output, "Startup error"
    print(f"MACOS PACKAGE CHECK: passed; host={platform.machine()}, universal={architectures}")
    print("Headless/Dummy audio only; no physical microphone, speakers, GPU UI or Gatekeeper interaction was tested.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Run this check on macOS.")
    check(args.app)
