#!/usr/bin/env python3
"""Check source files before publication; uses only Python's standard library.

By default, inspect tracked and unignored untracked working files. Use --staged
to inspect the complete Git index (the content that the next commit records).
Before Git initialization, a limited .gitignore-aware file walk is available.
This is a practical guard, not proof that every possible credential is absent.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
from urllib.parse import unquote


FORBIDDEN_SUFFIXES = {
    ".bak", ".exe", ".pck", ".zip", ".7z", ".rar", ".tar", ".gz",
    ".tgz", ".bz2", ".xz", ".tpz", ".pyc", ".pyo",
}
SECRET_NAME = re.compile(
    r"secret|password|passwd|token|(?:^|[_-])(?:api|app|private|access|client)[_-]?key$",
    re.I,
)
ASSIGNMENT = re.compile(
    r'''(?m)^\s*(?:(?:export|const|var|let|static|final)\s+)*["']?'''
    r'''(?P<name>[A-Za-z_][A-Za-z0-9_.-]*)["']?\s*'''
    r'''(?::\s*(?:String|str|string))?\s*(?:=|:)\s*'''
    r'''(?P<quote>["'])(?P<value>[^\r\n"']+)(?P=quote)'''
)
BARE_ASSIGNMENT = re.compile(
    r"(?m)^\s*(?:export\s+)?(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*"
    r"(?P<value>[A-Za-z0-9_+/=-]{12,})\s*$"
)
TOKEN = re.compile(
    r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}"
    r"|sk-(?:proj-)?[A-Za-z0-9_-]{24,})\b"
)
PRIVATE_KEY = re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----")
PLACEHOLDER = re.compile(
    r"example|placeholder|your[_ -]|replace[_ -]|changeme|dummy|<|>"
    r"|^test[_ -]|^\$|^\{", re.I,
)
LINK_START = re.compile(r"!?\[(?:\\.|[^\]\\])*\]\(")
REFERENCE = re.compile(r"(?m)^\s{0,3}\[[^\]]+\]:\s*(<[^>]+>|\S+)")
HTML_LINK = re.compile(r'''<(?:img|a)\b[^>]*?\b(?:src|href)=["']([^"']+)["']''', re.I)


def credential_present(text: str) -> bool:
    if TOKEN.search(text) or PRIVATE_KEY.search(text):
        return True
    for expression in (ASSIGNMENT, BARE_ASSIGNMENT):
        for match in expression.finditer(text):
            value = match["value"]
            if (SECRET_NAME.search(match["name"]) and len(value) >= 12
                    and not PLACEHOLDER.search(value)):
                return True
    return False


def without_code(text: str) -> str:
    lines: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker:
            if fence is None:
                fence = marker[1]
            elif marker[1][0] == fence[0] and len(marker[1]) >= len(fence):
                fence = None
            continue
        if fence is None:
            lines.append(line)
    return re.sub(r"(`+).*?\1", "", "\n".join(lines))


def markdown_destinations(text: str) -> list[str]:
    text = without_code(text)
    destinations: list[str] = []
    for start in LINK_START.finditer(text):
        cursor = start.end()
        while cursor < len(text) and text[cursor].isspace():
            cursor += 1
        if cursor < len(text) and text[cursor] == "<":
            end = text.find(">", cursor + 1)
            if end >= 0:
                destinations.append(text[cursor + 1:end])
            continue
        result: list[str] = []
        depth = 0
        while cursor < len(text):
            char = text[cursor]
            if char == "\\" and cursor + 1 < len(text):
                cursor += 1
                result.append(text[cursor])
            elif char == "(":
                depth += 1
                result.append(char)
            elif char == ")":
                if depth == 0:
                    break
                depth -= 1
                result.append(char)
            elif char.isspace() and depth == 0:
                break
            else:
                result.append(char)
            cursor += 1
        destinations.append("".join(result))
    destinations.extend(match[1].strip("<>") for match in REFERENCE.finditer(text))
    destinations.extend(match[1] for match in HTML_LINK.finditer(text))
    return destinations


def invalid_link(source: str, destination: str, available: set[str]) -> bool:
    if not destination or destination.startswith(("#", "//")):
        return False
    if re.match(r"^[A-Za-z]:[\\/]", destination):
        return True
    if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", destination):
        return False
    destination = unquote(destination.split("#", 1)[0].split("?", 1)[0])
    if not destination:
        return False
    parts = [] if destination.startswith("/") else list(PurePosixPath(source).parent.parts)
    for part in destination.replace("\\", "/").split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if not parts:
                return True
            parts.pop()
        else:
            parts.append(part)
    target = "/".join(parts)
    return bool(target) and target not in available and not any(
        name.startswith(target + "/") for name in available
    )


def fallback_ignored(name: str, patterns: list[str]) -> bool:
    """Support this repository's basic ignore rules before git init."""
    ignored = False
    parts = PurePosixPath(name).parts
    for raw in patterns:
        rule = raw.strip()
        if not rule or rule.startswith("#"):
            continue
        negate = rule.startswith("!")
        rule = rule.lstrip("!").rstrip("/")
        if "/" not in rule:
            matches = any(fnmatch.fnmatchcase(part, rule) for part in parts)
        else:
            matches = fnmatch.fnmatchcase(name, rule.lstrip("/")) or name.startswith(rule + "/")
        if matches:
            ignored = not negate
    return ignored


def git_output(git: str, root: Path, *args: str) -> bytes:
    result = subprocess.run([git, "-C", str(root), *args], capture_output=True)
    if result.returncode:
        raise RuntimeError("Git could not read the publication file list or index.")
    return result.stdout


def candidate_files(root: Path, git: str | None, staged: bool) -> tuple[list[str], str]:
    if git:
        probe = subprocess.run(
            [git, "-C", str(root), "rev-parse", "--show-toplevel"], capture_output=True,
        )
        if probe.returncode == 0 and Path(os.fsdecode(probe.stdout).strip()).resolve() == root:
            arguments = ["ls-files", "-z", "--cached"]
            if not staged:
                arguments.extend(["--others", "--exclude-standard"])
            names = sorted(set(os.fsdecode(name) for name in git_output(git, root, *arguments).split(b"\0") if name))
            return names, "Git index" if staged else "tracked and unignored working files"
    if staged:
        raise RuntimeError("--staged needs Git and an initialized repository at this project root.")
    patterns = (root / ".gitignore").read_text(encoding="utf-8").splitlines() if (root / ".gitignore").exists() else []
    names = []
    for path in root.rglob("*"):
        name = path.relative_to(root).as_posix()
        if ".git" in path.relative_to(root).parts or fallback_ignored(name, patterns):
            continue
        if path.is_file() or path.is_symlink():
            names.append(name)
    return sorted(names), "working files (.gitignore fallback; initialize Git for an index check)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="validate the entire Git index, including staged bytes")
    parser.add_argument("--git", help="path to Git when it is not on PATH")
    parser.add_argument("--max-bytes", type=int, default=10 * 1024 * 1024, help="maximum source-file size (default 10 MiB)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    git = args.git or shutil.which("git")
    failures: set[tuple[str, str]] = set()
    try:
        names, mode = candidate_files(root, git, args.staged)
        available = set(names)
        for name in names:
            path = root / name
            parts = PurePosixPath(name).parts
            filename = PurePosixPath(name).name.lower()
            if (".godot" in parts or ".import" in parts or "__pycache__" in parts
                    or filename == "export_credentials.cfg"
                    or (filename.startswith(".env") and filename != ".env.example")
                    or filename.endswith(".local.cfg")
                    or PurePosixPath(name).suffix.lower() in FORBIDDEN_SUFFIXES):
                failures.add((name, "generated, backup, executable, or archive file"))
            if args.staged:
                data = git_output(git, root, "show", ":" + name)
            else:
                if not path.is_file():
                    failures.add((name, "tracked file is missing"))
                    continue
                if not path.resolve().is_relative_to(root):
                    failures.add((name, "file resolves outside the repository"))
                    continue
                data = path.read_bytes()
            if len(data) > args.max_bytes:
                failures.add((name, "exceeds source-file size limit"))
            try:
                text = data.decode("utf-8-sig")
            except UnicodeDecodeError:
                continue
            if credential_present(text):
                failures.add((name, "possible embedded credential"))
            if path.suffix.lower() in (".md", ".markdown"):
                if any(invalid_link(name, link, available) for link in markdown_destinations(text)):
                    failures.add((name, "broken or nonportable local link/image"))
    except (OSError, RuntimeError, ValueError):
        print("FAIL: publication check could not read the file set. Check Git availability and file permissions.")
        return 2
    if failures:
        for name, reason in sorted(failures):
            print(f"FAIL [{reason}]: {name}")
        print(f"Publication check failed: {len(failures)} finding(s), {len(names)} files checked ({mode}).")
        return 1
    print(f"Publication check passed: {len(names)} files checked ({mode}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
