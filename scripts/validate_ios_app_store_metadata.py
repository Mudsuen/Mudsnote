#!/usr/bin/env python3

import json
import pathlib
import sys
from urllib.parse import urlparse


ROOT = pathlib.Path(__file__).resolve().parents[1]
METADATA_PATH = ROOT / "iOS" / "AppStore" / "metadata.json"
PROJECT_PATH = ROOT / "iOS" / "MudsnoteCompanion.xcodeproj" / "project.pbxproj"
INFO_PLIST_PATH = ROOT / "iOS" / "MudsnoteCompanion" / "Info.plist"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_limit(locale: str, field: str, value: str, limit: int, *, bytes_limit: bool = False) -> None:
    size = len(value.encode("utf-8")) if bytes_limit else len(value)
    unit = "bytes" if bytes_limit else "characters"
    if size > limit:
        fail(f"{locale} {field} is {size} {unit}; maximum is {limit}")


def main() -> None:
    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    version = metadata["version"]
    build = metadata["build"]

    for field in ("supportURL", "privacyPolicyURL"):
        parsed = urlparse(metadata[field])
        if parsed.scheme != "https" or not parsed.netloc:
            fail(f"{field} must be a public HTTPS URL")

    if not metadata.get("supportURLStatus", "").startswith("provisional;"):
        fail("supportURLStatus must explicitly track the provisional support URL")

    localizations = metadata.get("localizations", {})
    if set(localizations) != {"en-US", "zh-Hans"}:
        fail("metadata must contain exactly en-US and zh-Hans localizations")

    for locale, values in localizations.items():
        name = values["name"]
        if len(name) < 2:
            fail(f"{locale} name must contain at least 2 characters")
        require_limit(locale, "name", name, 30)
        require_limit(locale, "subtitle", values["subtitle"], 30)
        require_limit(locale, "promotionalText", values["promotionalText"], 170)
        require_limit(locale, "description", values["description"], 4_000)
        require_limit(locale, "keywords", values["keywords"], 100, bytes_limit=True)

    project = PROJECT_PATH.read_text(encoding="utf-8")
    expected_version = f"MARKETING_VERSION = {version};"
    if project.count(expected_version) != 8:
        fail(f"expected eight iOS target configurations with {expected_version}")
    if "MARKETING_VERSION = 0.3;" in project:
        fail("pre-release marketing version 0.3 remains in the iOS project")
    expected_build = f"CURRENT_PROJECT_VERSION = {build};"
    if project.count(expected_build) != 8:
        fail(f"expected eight iOS target configurations with {expected_build}")

    info_plist = INFO_PLIST_PATH.read_text(encoding="utf-8")
    if "$(MARKETING_VERSION)" not in info_plist:
        fail("app Info.plist must inherit MARKETING_VERSION")
    if "$(CURRENT_PROJECT_VERSION)" not in info_plist:
        fail("app Info.plist must inherit CURRENT_PROJECT_VERSION")

    print(
        f"Validated Mudsnote iOS {version} ({build}) App Store metadata fields; "
        "support URL remains provisional"
    )


if __name__ == "__main__":
    main()
