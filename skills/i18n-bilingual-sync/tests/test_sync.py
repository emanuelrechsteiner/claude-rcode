"""Tests for i18n bilingual sync script."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parent.parent / "scripts" / "sync.py"


@pytest.fixture
def locale_pair(tmp_path: Path) -> tuple[Path, Path]:
    de = tmp_path / "de.json"
    en = tmp_path / "en.json"
    de.write_text(
        json.dumps(
            {"hello": "Hallo", "nav": {"home": "Start"}},
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    en.write_text(
        json.dumps(
            {"hello": "Hello", "nav": {"home": "Home"}},
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    return de, en


def run_sync(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
    )


def load(p: Path) -> dict:
    return json.loads(p.read_text(encoding="utf-8"))


def test_add_toplevel_key(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    r = run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "goodbye",
        "--source-value",
        "Tschüss",
        "--target-value",
        "Goodbye",
    )
    assert r.returncode == 0, r.stderr
    assert load(de)["goodbye"] == "Tschüss"
    assert load(en)["goodbye"] == "Goodbye"


def test_add_nested_key(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    r = run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "nav.about",
        "--source-value",
        "Über uns",
        "--target-value",
        "About",
    )
    assert r.returncode == 0, r.stderr
    assert load(de)["nav"]["about"] == "Über uns"
    assert load(en)["nav"]["about"] == "About"
    # existing keys preserved
    assert load(de)["nav"]["home"] == "Start"


def test_modify_existing_key(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    r = run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "hello",
        "--source-value",
        "Servus",
        "--target-value",
        "Hi",
    )
    assert r.returncode == 0, r.stderr
    assert load(de)["hello"] == "Servus"
    assert load(en)["hello"] == "Hi"


def test_delete_key(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    r = run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "hello",
        "--delete",
    )
    assert r.returncode == 0, r.stderr
    assert "hello" not in load(de)
    assert "hello" not in load(en)


def test_delete_nested_key_cleans_empty_parent(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    r = run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "nav.home",
        "--delete",
    )
    assert r.returncode == 0, r.stderr
    assert "nav" not in load(de)
    assert "nav" not in load(en)


def test_structure_preserved_with_unicode(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "umlaut",
        "--source-value",
        "Ärger",
        "--target-value",
        "Trouble",
    )
    # ensure_ascii=False — raw unicode in file
    raw = de.read_text(encoding="utf-8")
    assert "Ärger" in raw
    assert "\\u" not in raw


def test_both_files_updated(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    de_before = de.stat().st_mtime_ns
    en_before = en.stat().st_mtime_ns
    run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "new",
        "--source-value",
        "neu",
        "--target-value",
        "new",
    )
    assert de.stat().st_mtime_ns >= de_before
    assert en.stat().st_mtime_ns >= en_before
    assert "new" in load(de)
    assert "new" in load(en)


def test_rejects_deeply_nested_key(locale_pair: tuple[Path, Path]) -> None:
    de, en = locale_pair
    r = run_sync(
        "--source",
        str(de),
        "--target",
        str(en),
        "--key",
        "a.b.c",
        "--source-value",
        "x",
        "--target-value",
        "y",
    )
    assert r.returncode != 0
    assert "Nested" in r.stderr or "nested" in r.stderr
