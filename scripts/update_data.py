"""增量更新 GKI 内核版本数据。"""

import copy
import json
import os
import sys
import time

from gki_fetch import (
    TARGETS,
    fetch_lts,
    fetch_makefile,
    get_end_date,
    json_path,
    make_date_range,
    parse_version,
)
from prepare_matrix import validate_data


def update_target(android_ver: str, kernel_ver: str,
                  date_start: str, date_end: str | None,
                  dep_cutoff: str) -> bool:
    path = json_path(android_ver, kernel_ver)
    end = get_end_date(date_end)
    is_k510 = (kernel_ver == "5.10")

    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        validate_data(data, path, android_ver, kernel_ver)
        entries = data.get("entries", [])
    else:
        data = {
            "android_version": android_ver,
            "kernel_version": kernel_ver,
            "entries": [],
        }
        if not is_k510:
            data["lts"] = None
        entries = []
    original_data = copy.deepcopy(data)

    # 建立已有日期索引，避免覆写
    existing_dates = {e.get("date") for e in entries if isinstance(e, dict)}
    all_dates = make_date_range(date_start, end)
    new_dates = [d for d in all_dates if d not in existing_dates]

    if not new_dates:
        print("  No new months to fetch")
    else:
        print(f"  Fetching {len(new_dates)} new month(s): {new_dates[0]} ~ {new_dates[-1]}")
        for date in new_dates:
            label = f"{android_ver}-{kernel_ver}-{date}"
            print(f"    [{label}] ", end="", flush=True)

            text = fetch_makefile(android_ver, kernel_ver, date, dep_cutoff)
            if text is None:
                print("not found, skip")
                continue

            ver = parse_version(text)
            if ver is None:
                raise RuntimeError(f"failed to parse Makefile for {label}")

            version, patchlevel, sublevel = ver
            detail = f"{version}.{patchlevel}.{sublevel}"

            # 仅 5.10 写入 revision
            new_entry = {"date": date, "kernel": detail}
            if is_k510:
                new_entry["revision"] = "r1"

            entries.append(new_entry)
            print(f"-> {detail}")
            time.sleep(0.3)

    # 排序：将具体日期按字母排序，'lts' 置于末尾
    entries.sort(key=lambda e: (e.get("date") == "lts", e.get("date", "")))

    # 更新 LTS
    lts_label = f"{android_ver}-{kernel_ver}-lts"
    print(f"  [{lts_label}] ", end="", flush=True)
    lts_text = fetch_lts(android_ver, kernel_ver)
    if lts_text is None:
        raise RuntimeError(f"LTS branch not found: {lts_label}")

    ver = parse_version(lts_text)
    if ver is None:
        raise RuntimeError(f"failed to parse Makefile for {lts_label}")

    version, patchlevel, sublevel = ver
    lts_value = f"{version}.{patchlevel}.{sublevel}"

    if is_k510:
        # 5.10 的 LTS 存在于 entries 内
        lts_entry = next((e for e in entries if e.get("date") == "lts"), None)
        if lts_entry:
            if lts_entry.get("kernel") != lts_value:
                lts_entry["kernel"] = lts_value
                print(f"-> {lts_value} (updated entries.lts)")
            else:
                print(f"-> {lts_value} (unchanged)")
        else:
            entries.append({"date": "lts", "kernel": lts_value, "revision": "r1"})
            print(f"-> {lts_value} (added to entries)")
    else:
        # 其他版本使用根节点 lts
        old_lts = data.get("lts")
        if old_lts != lts_value:
            data["lts"] = lts_value
            print(f"-> {lts_value} (was {old_lts})")
        else:
            print(f"-> {lts_value} (unchanged)")

    data["entries"] = entries
    validate_data(data, path, android_ver, kernel_ver)
    changed = data != original_data
    if changed:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        temp_path = f"{path}.tmp"
        with open(temp_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(temp_path, path)
        print(f"  => Saved {len(entries)} entries to {path}")
    else:
        print(f"  => No changes")

    return changed


def main():
    any_changed = False
    for (android_ver, kernel_ver), (date_start, date_end, dep_cutoff) in TARGETS.items():
        print(f"\n=== {android_ver} / {kernel_ver} ===")
        if update_target(android_ver, kernel_ver, date_start, date_end, dep_cutoff):
            any_changed = True

    print(f"\n{'Data updated.' if any_changed else 'All data up-to-date.'}")
    return any_changed


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"\nFATAL: {e}", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)
