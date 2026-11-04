"""Unzip the RTT Full CSV zips recorded in data/raw/manifest.csv.

For each period, the latest manifest row (the current version of that month)
is extracted to data/interim/rtt/<period>/. Any other CSV already in that
folder is deleted, so a revised month never leaves its old extract behind for
sql/01_load.sql's glob to double-count.

Rerunning is safe: a CSV whose size and CRC already match the zip member is
left alone. The raw zips are never modified.

Usage:
  uv run python ingest/extract.py
  uv run python ingest/extract.py --only 2026-08
"""

from __future__ import annotations

import argparse
import csv
import shutil
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data" / "raw" / "manifest.csv"
INTERIM = ROOT / "data" / "interim" / "rtt"
CHUNK = 1 << 20


def current_zips() -> dict[str, Path]:
    """Latest rtt_full_csv manifest row per period (later rows win)."""
    with MANIFEST.open(newline="", encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(f) if r["kind"] == "rtt_full_csv"]
    return {r["period"]: ROOT / r["path"] for r in rows}


def crc_of(path: Path) -> int:
    crc = 0
    with path.open("rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            crc = zlib.crc32(block, crc)
    return crc


def extract_one(period: str, zip_path: Path) -> str:
    out_dir = INTERIM / period
    out_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        members = [m for m in z.infolist() if m.filename.lower().endswith(".csv")]
        if len(members) != 1:
            raise ValueError(f"expected 1 CSV in {zip_path.name}, found {len(members)}")
        m = members[0]
        dest = out_dir / Path(m.filename).name  # flatten any folder inside the zip

        for stale in out_dir.glob("*.csv"):
            if stale != dest:
                stale.unlink()
                print(f"  rm    {period} stale {stale.name}")

        if dest.exists() and dest.stat().st_size == m.file_size and crc_of(dest) == m.CRC:
            return "skipped"

        part = dest.with_suffix(".csv.part")
        with z.open(m) as src, part.open("wb") as dst:
            shutil.copyfileobj(src, dst, CHUNK)
        part.replace(dest)
        return "extracted"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", nargs="*", metavar="YYYY-MM", help="limit to these periods")
    args = ap.parse_args()

    jobs = current_zips()
    if args.only:
        jobs = {p: z for p, z in jobs.items() if p in set(args.only)}
        if not jobs:
            print("No matching periods in manifest.")
            return 1

    counts = {"extracted": 0, "skipped": 0, "failed": 0}
    for period, zip_path in sorted(jobs.items()):
        try:
            result = extract_one(period, zip_path)
        except Exception as e:  # noqa: BLE001 - report every failure, keep going
            counts["failed"] += 1
            print(f"  FAIL  {period}: {e}")
            continue
        counts[result] += 1
        if result == "extracted":
            print(f"  unzip {period} <- {zip_path.name}")

    print("\nDone: {extracted} extracted, {skipped} skipped, {failed} failed.".format(**counts))
    return 1 if counts["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
