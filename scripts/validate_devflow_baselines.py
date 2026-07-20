#!/usr/bin/env python3
"""Validate the repository-owned Devflow product baseline contract."""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / ".devflow-baselines.json"
FULL_SHA = re.compile(r"[0-9a-f]{40}")


def fail(message: str) -> None:
    raise ValueError(message)


def git_succeeds(*args: str) -> bool:
    return subprocess.run(
        ["git", *args],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def validate() -> str:
    try:
        config = json.loads(CONFIG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {CONFIG.name}: {exc}")

    if config.get("schema_version") != 1:
        fail("schema_version must be 1")
    tracks = config.get("tracks")
    if not isinstance(tracks, dict) or not tracks:
        fail("tracks must be a non-empty object")

    for name, track in tracks.items():
        if not isinstance(name, str) or not name or not isinstance(track, dict):
            fail("every track must have a non-empty name and object value")
        commit = track.get("verified_commit")
        if not isinstance(commit, str) or FULL_SHA.fullmatch(commit) is None:
            fail(f"track {name} must use a full lowercase verified_commit SHA")
        if not git_succeeds("cat-file", "-e", f"{commit}^{{commit}}"):
            fail(f"track {name} verified_commit is unavailable: {commit}")
        if not git_succeeds("merge-base", "--is-ancestor", commit, "HEAD"):
            fail(f"track {name} verified_commit is not an ancestor of HEAD: {commit}")

        verified_at = track.get("verified_at")
        try:
            dt.date.fromisoformat(verified_at)
        except (TypeError, ValueError):
            fail(f"track {name} verified_at must be an ISO date")

        scope = track.get("scope")
        if not isinstance(scope, list) or not scope or len(scope) != len(set(scope)):
            fail(f"track {name} scope must be a non-empty unique list")

        protected_paths = track.get("protected_paths")
        if (
            not isinstance(protected_paths, list)
            or not protected_paths
            or len(protected_paths) != len(set(protected_paths))
        ):
            fail(f"track {name} protected_paths must be a non-empty unique list")
        for raw_path in protected_paths:
            if not isinstance(raw_path, str) or not raw_path:
                fail(f"track {name} contains an invalid protected path")
            path = PurePosixPath(raw_path)
            if path.is_absolute() or ".." in path.parts:
                fail(f"track {name} protected path must stay inside the repository: {raw_path}")
            if not (ROOT / raw_path).is_file():
                fail(f"track {name} protected path does not exist: {raw_path}")

    return ", ".join(
        f"{name}={track['verified_commit'][:12]}" for name, track in sorted(tracks.items())
    )


if __name__ == "__main__":
    try:
        summary = validate()
    except ValueError as exc:
        print(f"ERROR: invalid {CONFIG.name}: {exc}", file=sys.stderr)
        sys.exit(1)
    print(f"Devflow baseline contract passed: {summary}")
