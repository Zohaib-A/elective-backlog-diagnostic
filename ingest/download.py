"""Download the RTT Full CSV zips listed in ingest/sources.yaml.

Each file lands in data/raw/rtt/<period>/<original filename>, and a row is
appended to data/raw/manifest.csv with its SHA-256 hash.

Rerunning is safe:
  * a file whose URL is already in the manifest, and whose local copy still
    matches the recorded hash, is skipped without downloading;
  * a downloaded file whose hash is already in the manifest is not recorded twice;
  * a revised month (new URL in sources.yaml) is downloaded and recorded as a
    new row, so the manifest keeps the full version history.

Usage:
  uv run python ingest/download.py            # everything in sources.yaml
  uv run python ingest/download.py --only 2026-08 2026-07
  uv run python ingest/download.py --force    # re-download even if unchanged

Exits non-zero if any file fails, so CI can stop on it.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import sys
import time
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import requests
import yaml

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCES = ROOT / "ingest" / "sources.yaml"
RAW_DIR = ROOT / "data" / "raw"
MANIFEST = RAW_DIR / "manifest.csv"

MANIFEST_FIELDS = [
    "period",
    "kind",
    "version",
    "url",
    "path",
    "sha256",
    "bytes",
    "downloaded_at_utc",
]

USER_AGENT = "elective-backlog-diagnostic/0.1 (portfolio project; python-requests)"
TIMEOUT_S = 60
RETRIES = 4
CHUNK = 1 << 16


# --------------------------------------------------------------------------- #
# Manifest helpers
# --------------------------------------------------------------------------- #
def read_manifest() -> list[dict]:
    if not MANIFEST.exists():
        return []
    with MANIFEST.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def append_manifest(row: dict) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    new = not MANIFEST.exists()
    with MANIFEST.open("a", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=MANIFEST_FIELDS)
        if new:
            w.writeheader()
        w.writerow(row)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


# --------------------------------------------------------------------------- #
# Download
# --------------------------------------------------------------------------- #
def fetch(session: requests.Session, url: str, dest: Path) -> None:
    """Stream url to dest via a .part file, retrying with backoff."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    last_err: Exception | None = None
    for attempt in range(1, RETRIES + 1):
        try:
            with session.get(url, stream=True, timeout=TIMEOUT_S) as r:
                r.raise_for_status()
                with part.open("wb") as f:
                    for chunk in r.iter_content(CHUNK):
                        f.write(chunk)
            part.replace(dest)  # atomic: no half-written file under the real name
            return
        except (requests.RequestException, OSError) as e:
            last_err = e
            part.unlink(missing_ok=True)
            if attempt < RETRIES:
                wait = 2 ** attempt
                print(f"    retry {attempt}/{RETRIES - 1} in {wait}s ({e})")
                time.sleep(wait)
    raise RuntimeError(f"download failed after {RETRIES} attempts: {last_err}")


def check_file(path: Path, kind: str) -> None:
    """Fail fast on HTML error pages saved as data, or zips with no CSV."""
    if kind == "rtt_full_csv":
        if not zipfile.is_zipfile(path):
            raise ValueError("not a valid zip (server may have returned an error page)")
        with zipfile.ZipFile(path) as z:
            bad = z.testzip()
            if bad:
                raise ValueError(f"corrupt member in zip: {bad}")
            if not any(n.lower().endswith(".csv") for n in z.namelist()):
                raise ValueError("zip contains no CSV file")
    elif path.stat().st_size == 0:
        raise ValueError("empty file")


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def jobs_from_sources(cfg: dict) -> list[dict]:
    jobs = [
        {
            "period": f["period"],
            "kind": cfg.get("dataset", "rtt_full_csv"),
            "version": f.get("version", "original"),
            "url": f["url"],
        }
        for f in cfg["files"]
    ]
    for name, ref in (cfg.get("reference") or {}).items():
        jobs.append(
            {
                "period": ref.get("as_of", "ref"),
                "kind": name,
                "version": ref.get("version", "original"),
                "url": ref["url"],
            }
        )
    return jobs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sources", type=Path, default=DEFAULT_SOURCES)
    ap.add_argument("--only", nargs="*", metavar="YYYY-MM", help="limit to these periods")
    ap.add_argument("--force", action="store_true", help="re-download even if unchanged")
    args = ap.parse_args()

    cfg = yaml.safe_load(args.sources.read_text(encoding="utf-8"))
    jobs = jobs_from_sources(cfg)
    if args.only:
        jobs = [j for j in jobs if str(j["period"]) in set(args.only)]
        if not jobs:
            print("No matching periods in sources.")
            return 1

    manifest = read_manifest()
    by_url = {r["url"]: r for r in manifest}
    known_hashes = {r["sha256"] for r in manifest}

    session = requests.Session()
    session.headers["User-Agent"] = USER_AGENT

    counts = {"downloaded": 0, "skipped": 0, "unchanged": 0, "failed": 0}
    failures: list[str] = []

    for j in jobs:
        name = Path(urlparse(j["url"]).path).name
        sub = "rtt" if j["kind"] == "rtt_full_csv" else "reference"
        dest = RAW_DIR / sub / str(j["period"]) / name
        label = f"{j['period']} {j['kind']}"

        # 1. Same URL already recorded and local copy intact -> skip, no network.
        prev = by_url.get(j["url"])
        if prev and not args.force and dest.exists() and sha256_of(dest) == prev["sha256"]:
            counts["skipped"] += 1
            print(f"  skip  {label} (already in manifest)")
            continue

        # 2. Download, validate, hash.
        try:
            print(f"  get   {label} -> {dest.relative_to(ROOT)}")
            fetch(session, j["url"], dest)
            check_file(dest, j["kind"])
            digest = sha256_of(dest)
        except Exception as e:  # noqa: BLE001 - report every failure, keep going
            dest.unlink(missing_ok=True)
            counts["failed"] += 1
            failures.append(f"{label}: {e}")
            print(f"  FAIL  {label}: {e}")
            continue

        # 3. Identical content already recorded (e.g. --force rerun) -> don't duplicate.
        if digest in known_hashes:
            counts["unchanged"] += 1
            print(f"  same  {label} (hash already in manifest)")
            continue

        row = {
            "period": j["period"],
            "kind": j["kind"],
            "version": j["version"],
            "url": j["url"],
            "path": dest.relative_to(ROOT).as_posix(),
            "sha256": digest,
            "bytes": dest.stat().st_size,
            "downloaded_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        append_manifest(row)
        known_hashes.add(digest)
        by_url[j["url"]] = row
        counts["downloaded"] += 1

    print(
        "\nDone: {downloaded} downloaded, {skipped} skipped, "
        "{unchanged} unchanged, {failed} failed.".format(**counts)
    )
    if failures:
        print("Failures:\n  " + "\n  ".join(failures))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
