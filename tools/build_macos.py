#!/usr/bin/env python3
"""Export a Universal 2 application and create the redistributable ZIP on macOS."""
import argparse
import hashlib
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
NAME = "Trashbeats-0.1.0-preview.1-macos-universal.zip"


def engine(godot, *args):
    result = subprocess.run([str(godot), "--headless", "--path", str(ROOT), *args],
                            capture_output=True, text=True, timeout=600)
    print(result.stdout + result.stderr)
    if result.returncode or "SCRIPT ERROR:" in result.stdout + result.stderr or "ERROR:" in result.stdout + result.stderr:
        raise RuntimeError("Godot import/export failed; see output above.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Build on macOS so app permissions and signatures are preserved.")
    godot = args.godot.resolve()
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if version != "4.7.1.stable.official.a13da4feb":
        raise RuntimeError(f"Unexpected Godot version: {version}")
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="Trashbeats-MacPackage-") as temporary:
        package = Path(temporary) / "package"
        package.mkdir()
        app = package / "Trashbeats.app"
        engine(godot, "--editor", "--import", "--quit")
        engine(godot, "--export-release", "macOS", str(app))
        subprocess.run([sys.executable, str(ROOT / "tools/check_macos.py"), str(app)], check=True)
        for name in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
            shutil.copyfile(ROOT / name, package / name)
        shutil.copytree(ROOT / "licenses", package / "licenses")
        (package / "fonts").mkdir()
        shutil.copyfile(ROOT / "fonts/OFL.txt", package / "fonts/OFL.txt")
        shutil.copyfile(ROOT / "docs/MACOS.md", package / "START-HERE.txt")
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        (package / "BUILD-INFO.txt").write_text(
            f"TrashBeats 0.1.0 preview — macOS Universal 2\nSource commit: {commit}\n"
            f"Engine: {version}\nSigning: ad-hoc; not Apple-notarized\n"
            "Source and license: https://github.com/L1xy6/Trashbeats\n", encoding="utf-8")
        archive = destination / NAME
        if archive.exists():
            archive.unlink()  # Only this generated ZIP, never a directory.
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", str(package), str(archive)], check=True)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        (destination / "SHA256SUMS-macos.txt").write_text(f"{digest}  {NAME}\n", encoding="ascii")
        print(f"Created {archive} ({archive.stat().st_size} bytes)\nSHA256 {digest}")


if __name__ == "__main__":
    main()
