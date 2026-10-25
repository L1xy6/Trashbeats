#!/usr/bin/env python3
"""Fetch the pinned official macOS editor and, optionally, export templates."""
import argparse
import hashlib
from pathlib import Path
import platform
import subprocess
import urllib.request
import zipfile

VERSION = "4.7.1-stable"
ASSETS = {
    "Godot_v4.7.1-stable_macos.universal.zip": "897cb7f9799796c717ae75f31446aed883dc92b1d6c3b33d893cc7843fff2fa9",
    "Godot_v4.7.1-stable_export_templates.tpz": "86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72",
}


def download(name, destination):
    digest = hashlib.sha256()
    request = urllib.request.Request(
        f"https://github.com/godotengine/godot/releases/download/{VERSION}/{name}",
        headers={"User-Agent": "Trashbeats-build"},
    )
    with urllib.request.urlopen(request, timeout=120) as response, destination.open("wb") as output:
        while chunk := response.read(4 * 1024 * 1024):
            output.write(chunk)
            digest.update(chunk)
    if digest.hexdigest() != ASSETS[name]:
        raise RuntimeError(f"Official asset checksum mismatch: {name}")
    print(f"Verified {name}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--editor-only", action="store_true")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("This setup uses macOS ditto to preserve executable permissions.")
    root = args.directory.resolve()
    root.mkdir(parents=True, exist_ok=True)
    name = "Godot_v4.7.1-stable_macos.universal.zip"
    archive = root / name
    download(name, archive)
    subprocess.run(["ditto", "-x", "-k", str(archive), str(root)], check=True)
    if not args.editor_only:
        name = "Godot_v4.7.1-stable_export_templates.tpz"
        archive = root / name
        download(name, archive)
        templates = Path.home() / "Library/Application Support/Godot/export_templates/4.7.1.stable"
        templates.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive) as source:
            # Read only these known members, never arbitrary archive paths.
            for member in ("macos.zip", "version.txt"):
                (templates / member).write_bytes(source.read("templates/" + member))
    executable = root / "Godot.app/Contents/MacOS/Godot"
    version = subprocess.check_output([str(executable), "--version"], text=True).strip()
    if version != "4.7.1.stable.official.a13da4feb":
        raise RuntimeError(f"Unexpected editor version: {version}")
    print(executable)


if __name__ == "__main__":
    main()
