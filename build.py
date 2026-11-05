"""Rebuild everything from the raw files: download -> extract -> load -> test.

Usage:
  uv run python build.py                # full rebuild
  uv run python build.py --offline      # skip download; use zips already in data/raw
  uv run python build.py --from load    # start at a later step
  uv run python build.py --from test    # rerun the tests only

Each step stops the build if it fails. SQL scripts in sql/ run in filename
order against data/processed/rtt.duckdb, with the project root as the working
directory so their relative paths resolve.

Tests in sql/tests/ run last. Each is one query that returns a row per
failure; the build fails if any test returns rows.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "processed" / "rtt.duckdb"
STEPS = ["download", "extract", "load", "test"]
TEST_ROWS_SHOWN = 20


class BuildFailed(Exception):
    """A step failed in a way that is not a subprocess exit code."""


def run_py(script: str) -> None:
    subprocess.run([sys.executable, str(ROOT / script)], cwd=ROOT, check=True)


def run_sql() -> None:
    DB.parent.mkdir(parents=True, exist_ok=True)
    os.chdir(ROOT)
    with duckdb.connect(str(DB)) as con:
        for sql_file in sorted((ROOT / "sql").glob("*.sql")):
            print(f"  sql   {sql_file.name}")
            t = time.perf_counter()
            # Split on ';' line endings so every statement runs and the final
            # SELECT (each script's check query) can be printed.
            for chunk in sql_file.read_text(encoding="utf-8").split(";\n"):
                code = "\n".join(
                    ln for ln in chunk.splitlines() if not ln.strip().startswith("--")
                ).strip().rstrip(";")
                if not code:
                    continue
                rel = con.sql(code)
                if rel is not None and code.upper().startswith(("SELECT", "WITH")):
                    cols, rows = rel.columns, rel.fetchall()
                    for row in rows:
                        print("        " + ", ".join(f"{c}={v:,}" if isinstance(v, int) else f"{c}={v}"
                                                     for c, v in zip(cols, row)))
            print(f"        {time.perf_counter() - t:.1f}s")


def run_tests() -> None:
    tests = sorted((ROOT / "sql" / "tests").glob("*.sql"))
    if not tests:
        raise BuildFailed("no tests found in sql/tests/")
    failed = []
    with duckdb.connect(str(DB), read_only=True) as con:
        for test in tests:
            sql = test.read_text(encoding="utf-8").strip().rstrip(";")
            rel = con.sql(sql)
            cols, rows = rel.columns, rel.fetchall()
            if not rows:
                print(f"  pass  {test.name}")
                continue
            failed.append(test.name)
            print(f"  FAIL  {test.name}: {len(rows):,} failing row(s)")
            for row in rows[:TEST_ROWS_SHOWN]:
                print("        " + ", ".join(f"{c}={v}" for c, v in zip(cols, row)))
            if len(rows) > TEST_ROWS_SHOWN:
                print(f"        ... {len(rows) - TEST_ROWS_SHOWN:,} more")
    if failed:
        raise BuildFailed(f"{len(failed)} of {len(tests)} test(s) failed: {', '.join(failed)}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--offline", action="store_true", help="skip the download step")
    ap.add_argument("--from", dest="start", choices=STEPS, default="download")
    args = ap.parse_args()

    steps = STEPS[STEPS.index(args.start):]
    if args.offline and "download" in steps:
        steps.remove("download")

    actions = {
        "download": lambda: run_py("ingest/download.py"),
        "extract": lambda: run_py("ingest/extract.py"),
        "load": run_sql,
        "test": run_tests,
    }
    for step in steps:
        print(f"\n== {step} ==", flush=True)
        try:
            actions[step]()
        except subprocess.CalledProcessError as e:
            print(f"\nBuild stopped: {step} exited with {e.returncode}.")
            return 1
        except BuildFailed as e:
            print(f"\nBuild stopped: {step} failed. {e}")
            return 1
    print(f"\nBuild complete -> {DB.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
