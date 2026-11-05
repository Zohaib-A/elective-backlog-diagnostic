-- 02_tidy.sql
-- Two fact tables and two reference tables from raw.rtt_full. The fact
-- tables are scoped to the providers in tidy.ref_scope_provider.
--
--   tidy.ref_scope_provider  the provider codes in scope, listed once and
--                   used by both fact tables.
--   tidy.rtt_total  one row per raw row: the non-band numbers (Total, unknown
--                   clock start, Total All). Holds every part type, so clock
--                   starts (Part_3, no bands) and clock stops with an unknown
--                   start date are kept.
--   tidy.ref_wait_band  one row per week band: lower and upper week parsed
--                   from the raw column names.
--   tidy.rtt_band   one row per raw row x week band. Banded parts only
--                   (Part_1A, Part_1B, Part_2, Part_2A); Part_3 has no bands.
--
-- The fact tables carry codes only, no names, so the name drift found in
-- docs/data_dictionary.md does not spread into them. Parent codes stay on the
-- facts because a provider's ICB can change month to month (April 2026 mergers).
--
-- Grain of rtt_total: period x provider_code x commissioner_code x part_type x tfc
-- (tested unique on raw.rtt_full; see sql/explore/ Q2).
--
-- Checks live in sql/tests/ and run in the build's test step, which fails the
-- build if any test returns rows.
CREATE SCHEMA IF NOT EXISTS tidy;

-- Provider scope from docs/brief.md. Change the list here only.
CREATE OR REPLACE TABLE tidy.ref_scope_provider AS
SELECT * FROM (VALUES
    ('R1H', 'Barts Health NHS Trust'),
    ('RQX', 'Homerton Healthcare NHS Foundation Trust'),
    ('RF4', 'Barking, Havering and Redbridge University Hospitals NHS Trust')
) AS t(provider_code, provider_label);

CREATE OR REPLACE TABLE tidy.rtt_total AS
SELECT strptime("Period", 'RTT-%B-%Y')::DATE AS period,
    "Provider Parent Org Code" AS provider_parent_code,
    "Provider Org Code" AS provider_code,
    "Commissioner Parent Org Code" AS commissioner_parent_code,
    "Commissioner Org Code" AS commissioner_code,
    "RTT Part Type" AS part_type,
    "Treatment Function Code" AS tfc,
    "Total" AS total_banded,
    "Patients with unknown clock start date" AS unknown_clock_start,
    "Total All" AS total_all
FROM raw.rtt_full
WHERE "Provider Org Code" IN (SELECT provider_code FROM tidy.ref_scope_provider)
    AND "Treatment Function Code" <> 'C_999';

-- Reference table of wait bands: one row per week-band column in raw.rtt_full,
-- with lower and upper week parsed from the column name. Built from the
-- table's own column list, so the bands always match what was loaded.
--   'Gt 17 To 18 Weeks SUM 1' -> lower_wk 17, upper_wk 18
--   'Gt 104 Weeks SUM 1'      -> lower_wk 104, upper_wk NULL (open-ended)
-- A band covers waits > lower_wk and <= upper_wk. lower_wk is unique and is
-- the join key from tidy.rtt_band.
CREATE OR REPLACE TABLE tidy.ref_wait_band AS
WITH cols AS (
    SELECT column_name AS band_label,
        regexp_extract(column_name, '^Gt (\d+)(?: To (\d+))? Weeks SUM 1$', ['lo', 'hi']) AS m
    FROM duckdb_columns()
    WHERE schema_name = 'raw'
        AND table_name = 'rtt_full'
        AND column_name LIKE 'Gt %'
)
SELECT row_number() OVER (ORDER BY m.lo::INT) AS band_order,
    band_label,
    m.lo::INT AS lower_wk,
    nullif(m.hi, '')::INT AS upper_wk,
    upper_wk - lower_wk AS width_wk,
    upper_wk IS NULL AS is_open_ended,
    coalesce(upper_wk <= 18, false) AS within_18_wk,
    lower_wk >= 52 AS is_52_plus
FROM cols
ORDER BY band_order;

-- Band facts. band_order/lower_wk/upper_wk come from tidy.ref_wait_band, so
-- the band labels are parsed in one place only, and band_order lets charts
-- sort bands without another join.
CREATE OR REPLACE TABLE tidy.rtt_band AS
WITH src AS (
    SELECT strptime("Period", 'RTT-%B-%Y')::DATE AS period,
        "Provider Parent Org Code" AS provider_parent_code,
        "Provider Org Code" AS provider_code,
        "Commissioner Parent Org Code" AS commissioner_parent_code,
        "Commissioner Org Code" AS commissioner_code,
        "RTT Part Type" AS part_type,
        "Treatment Function Code" AS tfc,
        COLUMNS('^Gt ')
    FROM raw.rtt_full
    WHERE "Provider Org Code" IN (SELECT provider_code FROM tidy.ref_scope_provider)
        AND "RTT Part Type" IN ('Part_1A', 'Part_1B', 'Part_2', 'Part_2A')
        AND "Treatment Function Code" <> 'C_999'
),
long AS (
    -- Drops null bands; null means zero, so sums are unaffected.
    UNPIVOT src ON COLUMNS('^Gt ') INTO NAME band_label VALUE pathways
)
SELECT long.* EXCLUDE (band_label),
    r.band_order,
    r.lower_wk,
    r.upper_wk
FROM long
JOIN tidy.ref_wait_band r USING (band_label);
