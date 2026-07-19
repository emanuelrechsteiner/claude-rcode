#!/usr/bin/env python3
"""i18n bilingual sync: mirror a key edit across two locale JSON files.

Mechanical JSON edit only — translation is the caller's responsibility.
Supports top-level and 1-level nested keys (e.g. "nav.home").
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def dump_json(path: Path, data: dict) -> None:
    with path.open("w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False, sort_keys=False)
        fh.write("\n")


def split_key(key: str) -> tuple[str, str | None]:
    if "." not in key:
        return key, None
    parts = key.split(".")
    if len(parts) > 2:
        raise ValueError(f"Nested keys deeper than 1 level not supported: {key!r}")
    return parts[0], parts[1]


def set_key(data: dict, key: str, value: str) -> None:
    top, sub = split_key(key)
    if sub is None:
        data[top] = value
        return
    if top not in data or not isinstance(data[top], dict):
        data[top] = {}
    data[top][sub] = value


def delete_key(data: dict, key: str) -> bool:
    """Return True if something was deleted."""
    top, sub = split_key(key)
    if sub is None:
        return data.pop(top, None) is not None
    if top in data and isinstance(data[top], dict):
        removed = data[top].pop(sub, None) is not None
        # clean up empty parent object
        if removed and not data[top]:
            del data[top]
        return removed
    return False


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Sync a key across two locale JSON files.")
    p.add_argument("--source", required=True, help="Path to source locale JSON")
    p.add_argument("--target", required=True, help="Path to target locale JSON")
    p.add_argument("--key", required=True, help="Dotted key (max 1 level nesting)")
    p.add_argument("--source-value", help="Value to write in source locale")
    p.add_argument("--target-value", help="Translated value to write in target locale")
    p.add_argument("--delete", action="store_true", help="Delete key from both files")
    args = p.parse_args(argv)

    source_path = Path(args.source)
    target_path = Path(args.target)

    try:
        source_data = load_json(source_path)
        target_data = load_json(target_path)
    except json.JSONDecodeError as e:
        print(f"ERROR: invalid JSON: {e}", file=sys.stderr)
        return 2

    try:
        if args.delete:
            s_removed = delete_key(source_data, args.key)
            t_removed = delete_key(target_data, args.key)
            action = f"deleted (source={s_removed}, target={t_removed})"
        else:
            if args.source_value is None or args.target_value is None:
                print(
                    "ERROR: --source-value and --target-value required unless --delete",
                    file=sys.stderr,
                )
                return 2
            set_key(source_data, args.key, args.source_value)
            set_key(target_data, args.key, args.target_value)
            action = "set"
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2

    dump_json(source_path, source_data)
    dump_json(target_path, target_data)
    print(f"OK: {action} key={args.key!r} in {source_path.name} + {target_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
