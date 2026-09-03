"""Validate GKI version data and generate a GitHub Actions matrix."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


ANDROID_VERSION_RE = re.compile(r"^android\d+$")
KERNEL_VERSION_RE = re.compile(r"^\d+\.\d+$")
FULL_VERSION_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
PATCH_LEVEL_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
REVISION_RE = re.compile(r"^r\d+$")


class DataError(ValueError):
    """Raised when a GKI version data file has an invalid schema."""


def _require_string(value: Any, field: str, pattern: re.Pattern[str]) -> str:
    if not isinstance(value, str) or not pattern.fullmatch(value):
        raise DataError(f"{field} has an invalid value: {value!r}")
    return value


def _sublevel(version: Any, kernel_version: str, field: str) -> str:
    value = _require_string(version, field, FULL_VERSION_RE)
    match = FULL_VERSION_RE.fullmatch(value)
    assert match is not None
    if f"{match.group(1)}.{match.group(2)}" != kernel_version:
        raise DataError(
            f"{field} ({value}) does not match kernel_version ({kernel_version})"
        )
    return match.group(3)


def validate_data(
    data: Any,
    source: str = "data",
    expected_android_version: str | None = None,
    expected_kernel_version: str | None = None,
) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise DataError(f"{source} must contain a JSON object")

    android_version = _require_string(
        data.get("android_version"), "android_version", ANDROID_VERSION_RE
    )
    kernel_version = _require_string(
        data.get("kernel_version"), "kernel_version", KERNEL_VERSION_RE
    )
    if expected_android_version and android_version != expected_android_version:
        raise DataError(
            f"android_version ({android_version}) does not match {expected_android_version}"
        )
    if expected_kernel_version and kernel_version != expected_kernel_version:
        raise DataError(
            f"kernel_version ({kernel_version}) does not match {expected_kernel_version}"
        )
    entries = data.get("entries")
    if not isinstance(entries, list) or not entries:
        raise DataError("entries must be a non-empty array")

    seen_patch_levels: set[str] = set()
    legacy_lts = False
    for index, entry in enumerate(entries):
        field = f"entries[{index}]"
        if not isinstance(entry, dict):
            raise DataError(f"{field} must be an object")

        patch_level = entry.get("date")
        if patch_level == "lts":
            if legacy_lts:
                raise DataError("entries contains more than one lts target")
            legacy_lts = True
        else:
            _require_string(patch_level, f"{field}.date", PATCH_LEVEL_RE)

        if patch_level in seen_patch_levels:
            raise DataError(f"duplicate patch level: {patch_level}")
        seen_patch_levels.add(patch_level)
        _sublevel(entry.get("kernel"), kernel_version, f"{field}.kernel")

        revision = entry.get("revision")
        if revision is not None:
            _require_string(revision, f"{field}.revision", REVISION_RE)
        elif kernel_version == "5.10":
            raise DataError(f"{field}.revision is required for kernel 5.10")

    root_lts = data.get("lts")
    if root_lts is not None:
        if legacy_lts:
            raise DataError("lts must be stored either at the root or in entries, not both")
        _sublevel(root_lts, kernel_version, "lts")
        lts_revision = data.get("lts_revision")
        if lts_revision is not None:
            _require_string(lts_revision, "lts_revision", REVISION_RE)
    elif not legacy_lts:
        raise DataError("an lts target is required")

    return {
        "android_version": android_version,
        "kernel_version": kernel_version,
        "entries": entries,
        "lts": root_lts,
        "lts_revision": data.get("lts_revision"),
    }


def build_matrix(data: Any, deduplicate_sublevels: bool) -> list[dict[str, str]]:
    validated = validate_data(data)
    android_version = validated["android_version"]
    kernel_version = validated["kernel_version"]
    matrix: list[dict[str, str]] = []
    seen_sublevels: set[str] = set()

    for index, entry in enumerate(validated["entries"]):
        sublevel = _sublevel(
            entry["kernel"], kernel_version, f"entries[{index}].kernel"
        )
        patch_level = entry["date"]
        if (
            deduplicate_sublevels
            and patch_level != "lts"
            and sublevel in seen_sublevels
        ):
            continue
        if patch_level != "lts":
            seen_sublevels.add(sublevel)

        matrix.append(
            {
                "android_version": android_version,
                "kernel_version": kernel_version,
                "sub_level": sublevel,
                "os_patch_level": patch_level,
                "revision": entry.get("revision", ""),
            }
        )

    if validated["lts"] is not None:
        matrix.append(
            {
                "android_version": android_version,
                "kernel_version": kernel_version,
                "sub_level": _sublevel(validated["lts"], kernel_version, "lts"),
                "os_patch_level": "lts",
                "revision": validated["lts_revision"] or "",
            }
        )

    return matrix


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data_file", type=Path)
    parser.add_argument(
        "--deduplicate-sublevels",
        action="store_true",
        help="keep the first monthly target for each kernel sublevel",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        with args.data_file.open("r", encoding="utf-8") as file:
            data = json.load(file)
        validated = validate_data(
            data,
            str(args.data_file),
            args.data_file.parent.name,
            args.data_file.stem,
        )
        matrix = build_matrix(validated, args.deduplicate_sublevels)
    except (OSError, json.JSONDecodeError, DataError) as error:
        print(f"{args.data_file}: {error}", file=sys.stderr)
        return 1

    print(json.dumps(matrix, separators=(",", ":"), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
