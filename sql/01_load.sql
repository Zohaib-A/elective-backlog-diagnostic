-- 01_load.sql
-- Load every monthly RTT Full CSV extract into raw.rtt_full, one row per CSV row.
--
-- Input:  data/interim/rtt/<period>/*.csv, unzipped from data/raw/rtt/<period>/*.zip
--         (raw zips stay untouched so their SHA-256 still matches data/raw/manifest.csv).
-- Run from the project root, e.g.  duckdb data/processed/rtt.duckdb < sql/01_load.sql
--
-- Notes:
--   * filename = true keeps the source path on every row for provenance/revisions.
--   * union_by_name = true lines columns up by header name, so a month that adds,
--     drops or reorders a column cannot silently shift values into the wrong band.
--   * Code/name columns are pinned to VARCHAR so codes like '06Q' or 'C_999'
--     are never type-sniffed; the week-band counts are sniffed (BIGINT).
--   * No filtering or reshaping here; that happens in later scripts.
CREATE SCHEMA IF NOT EXISTS raw;
CREATE OR REPLACE TABLE raw.rtt_full AS
SELECT *
FROM read_csv(
        'data/interim/rtt/*/*.csv',
        header = true,
        filename = true,
        union_by_name = true,
        types = { 'Period': 'VARCHAR',
        'Provider Parent Org Code': 'VARCHAR',
        'Provider Parent Name': 'VARCHAR',
        'Provider Org Code': 'VARCHAR',
        'Provider Org Name': 'VARCHAR',
        'Commissioner Parent Org Code': 'VARCHAR',
        'Commissioner Parent Name': 'VARCHAR',
        'Commissioner Org Code': 'VARCHAR',
        'Commissioner Org Name': 'VARCHAR',
        'RTT Part Type': 'VARCHAR',
        'RTT Part Description': 'VARCHAR',
        'Treatment Function Code': 'VARCHAR',
        'Treatment Function Name': 'VARCHAR' }
    );
-- Quick check: expect 36 files (Sep 2023 to Aug 2026), one Period value per file.
SELECT count(DISTINCT filename) AS files,
    count(DISTINCT Period) AS periods,
    count(*) AS rows
FROM raw.rtt_full;