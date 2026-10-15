#!/usr/bin/env python3
"""Update one configured unlisted gist with validated portable Beads text only."""

import argparse
from datetime import datetime, timezone
import hashlib
from http.client import HTTPException
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


ROOT = Path(__file__).resolve().parents[1]
FILES = ("issues.jsonl", "config.yaml", "metadata.json")
MAX_BYTES = 8 * 1024 * 1024  # Below GitHub's documented >10 MB clone-only boundary.


def no_symlinks(path):
    if not path.is_absolute() or ".." in path.parts:
        raise ValueError("Use an absolute path without parent traversal")
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError("Symlink paths are not accepted")


def read_text(path, private=False):
    no_symlinks(path)
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as source:
        info = os.fstat(source.fileno())
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("Backup inputs must be regular files")
        if private and (info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o600):
            raise ValueError("Private configuration must be owned by this user with mode 0600")
        data = source.read(MAX_BYTES)
        if source.read(1):
            raise ValueError(f"Backup input exceeds {MAX_BYTES:,} bytes; nothing is uploaded or truncated")
        if len(data) >= MAX_BYTES * 3 // 4:
            print(f"BACKUP WARNING: input has reached 75% of the {MAX_BYTES:,}-byte limit; review export growth",
                  file=sys.stderr)
    text = data.decode("utf-8")
    if "\x00" in text:
        raise ValueError("Backup inputs must be UTF-8 text without NUL bytes")
    return text


def command(args, cwd, payload=None):
    # Never echo captured output/errors: either may contain private ledger text.
    try:
        environment = {key: value for key, value in os.environ.items()
                       if not (args[0] == "br" and key.startswith("BEADS_"))}
        return subprocess.run(args, cwd=cwd, input=payload, capture_output=True,
                              text=True, check=True, timeout=30, env=environment).stdout
    except (OSError, subprocess.SubprocessError) as error:
        raise ValueError(f"{args[0]} operation failed; backup is not verified") from error


def json_object(text):
    value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError("Expected a JSON object")
    return value


def project(root):
    common = Path(command(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], root).strip())
    if common.name != ".git":
        raise ValueError("Expected a project with a main .git directory")
    main = common.parent
    listing = command(["git", "-c", "core.quotePath=false", "worktree", "list", "--porcelain"], root)
    worktrees = [main]
    for line in listing.splitlines():
        if line.startswith("worktree "):
            raw = line.removeprefix("worktree ")
            if raw.startswith('"'):
                raise ValueError("Quoted/control-character worktree paths are unsupported")
            worktrees.append(Path(raw).resolve())
    return main, worktrees


def validate_export(contents):
    ids = set()
    for line in contents["issues.jsonl"].splitlines():
        issue = json_object(line)
        issue_id = issue.get("id")
        if not isinstance(issue_id, str) or not re.fullmatch(r"factory-[A-Za-z0-9.-]+", issue_id) or issue_id in ids:
            raise ValueError("Invalid or duplicate issue ID in Beads export")
        if not isinstance(issue.get("title"), str) or not issue["title"].strip():
            raise ValueError("Missing issue title in Beads export")
        ids.add(issue_id)
    if not ids:
        raise ValueError("Refusing an empty Beads export")
    validate_metadata(contents["metadata.json"])
    if not contents["config.yaml"].strip():
        raise ValueError("Missing Beads configuration")


def validate_metadata(text):
    if json_object(text) != {"database": "beads.db", "jsonl_export": "issues.jsonl"}:
        raise ValueError("Unsupported Beads metadata paths or fields")


def check_gist(value, gist_id):
    if value.get("id") != gist_id or value.get("public") is not False:
        raise ValueError("Configured gist must exist and be unlisted (public=false)")
    files = value.get("files")
    if not isinstance(files, dict) or set(files) != set(FILES) or not all(isinstance(row, dict) for row in files.values()):
        raise ValueError("Configured gist must contain exactly the three named backup files")
    if value.get("truncated"):
        raise ValueError("Gist file list is truncated; the complete allowlist is not verified")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def fetch_raw(url, gist_id, name):
    """Read only a pinned file on the approved gist host, without account headers.

    A file-level truncated API result is not the complete backup. Keep the
    original portable format and verify its full raw contents instead. Do not
    follow redirects, allow arbitrary URLs, or print private URLs/diagnostics.
    """
    if not isinstance(url, str) or name not in FILES:
        raise ValueError("Missing or unsupported raw readback URL")
    try:
        parsed = urlsplit(url)
    except ValueError as error:
        raise ValueError("Unsupported raw readback URL") from error
    parts = parsed.path.split("/")
    if (parsed.scheme != "https" or parsed.netloc != "gist.githubusercontent.com"
            or parsed.query or parsed.fragment or len(parts) != 6
            or not re.fullmatch(r"[A-Za-z0-9-]+", parts[1])
            or parts[2] != gist_id or parts[3] != "raw"
            or not re.fullmatch(r"[a-f0-9]{40}", parts[4]) or parts[5] != name):
        raise ValueError("Unsupported raw readback URL")
    opener = build_opener(NoRedirect())
    deadline = time.monotonic() + 30
    data = bytearray()
    try:
        # No gh invocation, auth headers, cookies or URL in a child command line.
        with opener.open(Request(url, headers={"Accept": "text/plain"}), timeout=10) as response:
            if response.status != 200:
                raise ValueError("Unexpected raw response")
            length = response.headers.get("Content-Length")
            if length is not None and not 0 <= int(length) <= MAX_BYTES:
                raise ValueError("Raw response exceeds the readback limit")
            while True:
                if time.monotonic() >= deadline:
                    raise ValueError("Raw response deadline exceeded")
                # Bound returned body chunks, including no-newline responses.
                # HTTP setup/framing can perform additional socket reads; this
                # checked deadline is not a strict total network time bound.
                chunk = response.read1(min(64 * 1024, MAX_BYTES + 1 - len(data)))
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > MAX_BYTES:
                    raise ValueError("Raw response exceeds the readback limit")
            if time.monotonic() >= deadline:
                raise ValueError("Raw response deadline exceeded")
        text = data.decode("utf-8")
        if "\x00" in text:
            raise ValueError("Raw response is not portable text")
        return text
    except (OSError, ValueError, HTTPException) as error:
        raise ValueError("Raw readback failed; remote outcome needs inspection") from error


def backup(root, config_path):
    main, worktrees = project(root)
    no_symlinks(config_path)
    private_git_config = main / ".git/factory-ops/beads-backup.json"
    if config_path != private_git_config and any(config_path.is_relative_to(path) for path in worktrees):
        raise ValueError("Private configuration must be outside all project worktrees")
    config = json_object(read_text(config_path, private=True))
    gist_id = config.get("gist_id")
    if (set(config) != {"gist_id", "root", "visibility"} or config.get("root") != str(main)
            or config.get("visibility") != "unlisted" or not isinstance(gist_id, str)
            or not re.fullmatch(r"[a-f0-9]{5,64}", gist_id)):
        raise ValueError("Configuration requires gist_id, matching root and visibility=unlisted")
    source = main / ".beads"
    for name in FILES:
        path = source / name
        no_symlinks(path)
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError("Backup inputs must be regular files")
    validate_metadata(read_text(source / "metadata.json"))
    no_symlinks(source / "beads.db")
    if not (source / "beads.db").is_file():
        raise ValueError("Missing canonical Beads database")
    command(["br", "sync", "--flush-only", "--db", str(source / "beads.db")], main)
    contents = {name: read_text(main / ".beads" / name) for name in FILES}
    validate_export(contents)
    endpoint = f"gists/{gist_id}"
    base = ["gh", "api", "--hostname", "github.com", endpoint]
    check_gist(json_object(command([*base, "--method", "GET"], main)), gist_id)
    payload = json.dumps({"files": {name: {"content": text} for name, text in contents.items()}})
    # A timeout/nonzero result after PATCH may already have changed the remote.
    # Fail rather than claiming success or blindly retrying the write.
    command([*base, "--method", "PATCH", "--input", "-"], main, payload)
    result = json_object(command([*base, "--method", "GET"], main))
    check_gist(result, gist_id)
    for name, text in contents.items():
        row = result["files"][name]
        truncated = row.get("truncated")
        if truncated is True:
            remote = fetch_raw(row.get("raw_url"), gist_id, name)
        elif truncated is None or truncated is False:
            remote = row.get("content")
        else:
            raise ValueError("Unsupported file truncation status; remote outcome needs inspection")
        if (not isinstance(remote, str)
                or hashlib.sha256(remote.encode("utf-8")).digest()
                != hashlib.sha256(text.encode("utf-8")).digest()):
            raise ValueError("Readback differs; remote outcome needs inspection")
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, type=Path, help="private mode-0600 JSON: gist_id/root/visibility")
    args = parser.parse_args()
    try:
        at = backup(ROOT, args.config)
        print(f"Beads gist backup verified at {at}")
        return 0
    except (OSError, ValueError) as error:
        # No input bytes, API diagnostics, gist ID or URL in routine output.
        print(f"BACKUP FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
