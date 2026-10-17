#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null || { echo "Set GODOT to your Godot 4.7.1 executable." >&2; exit 1; }
mkdir -p "$ROOT/build/web"
"$GODOT" --headless --path "$ROOT" --editor --import
"$GODOT" --headless --path "$ROOT" --export-release Web "$ROOT/build/web/index.html"
echo "Experimental Web build. See docs/BUILDING.md for platform limitations."
echo "Serve locally: python3 -m http.server 8080 --directory \"$ROOT/build/web\""
