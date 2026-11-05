-- profile_raw_rtt_full.sql
-- Profile queries behind the figures in docs/data_dictionary.md.
-- Read-only. Not run by build.py (it only runs sql/*.sql, not subfolders).
-- Run from the project root:
--   duckdb -readonly data/processed/rtt.duckdb < sql/explore/profile_raw_rtt_full.sql

-- Q1. Table size
SELECT count(*) AS rows,
    count(DISTINCT filename) AS files,
    count(DISTINCT Period) AS periods
FROM raw.rtt_full;

-- Q2. Grain test: rows must equal distinct keys, and no key column may be null
SELECT count(*) AS rows,
    count(DISTINCT (Period, "Provider Org Code", "Commissioner Org Code",
                    "RTT Part Type", "Treatment Function Code")) AS distinct_keys,
    count(*) - distinct_keys AS duplicate_rows,
    count(*) FILTER (WHERE Period IS NULL OR "Provider Org Code" IS NULL
                     OR "Commissioner Org Code" IS NULL OR "RTT Part Type" IS NULL
                     OR "Treatment Function Code" IS NULL) AS null_key_rows
FROM raw.rtt_full;

-- Q3. Distinct codes per identifier
SELECT count(DISTINCT "Provider Parent Org Code") AS provider_parents,
    count(DISTINCT "Provider Org Code") AS providers,
    count(DISTINCT "Commissioner Parent Org Code") AS commissioner_parents,
    count(DISTINCT "Commissioner Org Code") AS commissioners
FROM raw.rtt_full;

-- Q4. Rows per RTT part type
SELECT "RTT Part Type", "RTT Part Description", count(*) AS rows
FROM raw.rtt_full
GROUP BY ALL
ORDER BY 1;

-- Q5. Total reconciliation and null pattern by part type (null band = zero)
WITH t AS (
    SELECT "RTT Part Type" AS part,
        Total,
        "Patients with unknown clock start date" AS unknown_start,
        "Total All" AS total_all,
        coalesce(list_sum([*COLUMNS('^Gt ')]), 0) AS band_sum  -- list_sum skips nulls
    FROM raw.rtt_full
)
SELECT part,
    count(*) FILTER (WHERE Total IS NULL) AS total_null,
    count(*) FILTER (WHERE unknown_start IS NULL) AS unknown_start_null,
    count(*) FILTER (WHERE Total IS NOT NULL AND band_sum <> Total) AS bands_ne_total,
    count(*) FILTER (WHERE band_sum + coalesce(unknown_start, 0) <> total_all
                     AND part <> 'Part_3') AS bands_ne_total_all,
    count(*) FILTER (WHERE part = 'Part_3' AND band_sum <> 0) AS part3_rows_with_bands
FROM t
GROUP BY part
ORDER BY part;

-- Q6. Treatment function codes and names
SELECT "Treatment Function Code", any_value("Treatment Function Name") AS name
FROM raw.rtt_full
GROUP BY 1
ORDER BY 1;

-- Q7. Rows with no commissioner parent, by commissioner
SELECT "Commissioner Org Code",
    any_value("Commissioner Org Name") AS name,
    count(*) AS rows
FROM raw.rtt_full
WHERE "Commissioner Parent Org Code" IS NULL
GROUP BY 1
ORDER BY rows DESC;

-- Q8. Rows with no commissioner parent, by part type
SELECT "RTT Part Type", count(*) AS rows
FROM raw.rtt_full
WHERE "Commissioner Parent Org Code" IS NULL
GROUP BY 1
ORDER BY 1;

-- Q9. Codes with more than one name in the window
SELECT 'commissioner' AS kind, "Commissioner Org Code" AS code,
    count(DISTINCT "Commissioner Org Name") AS names
FROM raw.rtt_full GROUP BY 1, 2 HAVING names > 1
UNION ALL
SELECT 'provider', "Provider Org Code", count(DISTINCT "Provider Org Name")
FROM raw.rtt_full GROUP BY 1, 2 HAVING count(DISTINCT "Provider Org Name") > 1
ORDER BY kind, names DESC, code;

-- Q10. Scope providers: months present, first and last month, parent ICB(s)
SELECT "Provider Org Code",
    any_value("Provider Org Name") AS name,
    count(DISTINCT Period) AS months,
    min(strptime(Period, 'RTT-%B-%Y'))::DATE AS first_month,
    max(strptime(Period, 'RTT-%B-%Y'))::DATE AS last_month,
    string_agg(DISTINCT "Provider Parent Org Code", ', ') AS parents
FROM raw.rtt_full
WHERE "Provider Org Code" IN ('R1H', 'RQX', 'RF4')
GROUP BY 1
ORDER BY 1;

-- Q11. Scope commissioner: months present for QMF / A3A8R
SELECT "Commissioner Parent Org Code", "Commissioner Org Code",
    count(DISTINCT Period) AS months
FROM raw.rtt_full
WHERE "Commissioner Parent Org Code" = 'QMF'
GROUP BY ALL;

-- Q12. Scope rows by month (R1H, RQX, RF4 x QMF commissioner): a dip flags a missing provider
SELECT strptime(Period, 'RTT-%B-%Y')::DATE AS month,
    count(DISTINCT "Provider Org Code") AS providers,
    count(*) AS rows
FROM raw.rtt_full
WHERE "Provider Org Code" IN ('R1H', 'RQX', 'RF4')
    AND "Commissioner Parent Org Code" = 'QMF'
GROUP BY 1
ORDER BY 1;

-- Q13. Code churn: how many codes are present in every month, and how many start or stop
WITH span AS (
    SELECT 'provider' AS kind, "Provider Org Code" AS code,
        min(strptime(Period, 'RTT-%B-%Y'))::DATE AS first_month,
        max(strptime(Period, 'RTT-%B-%Y'))::DATE AS last_month,
        count(DISTINCT Period) AS months
    FROM raw.rtt_full GROUP BY 1, 2
    UNION ALL
    SELECT 'commissioner', "Commissioner Org Code",
        min(strptime(Period, 'RTT-%B-%Y'))::DATE,
        max(strptime(Period, 'RTT-%B-%Y'))::DATE,
        count(DISTINCT Period)
    FROM raw.rtt_full GROUP BY 1, 2
    UNION ALL
    SELECT 'provider_parent', "Provider Parent Org Code",
        min(strptime(Period, 'RTT-%B-%Y'))::DATE,
        max(strptime(Period, 'RTT-%B-%Y'))::DATE,
        count(DISTINCT Period)
    FROM raw.rtt_full GROUP BY 1, 2
)
SELECT kind,
    count(*) AS codes,
    count(*) FILTER (WHERE months = 36) AS all_36_months,
    count(*) FILTER (WHERE first_month > DATE '2023-09-01') AS appear_after_start,
    count(*) FILTER (WHERE last_month < DATE '2026-08-01') AS disappear_before_end,
    count(*) FILTER (WHERE months < datediff('month', first_month, last_month) + 1) AS with_gaps
FROM span
GROUP BY kind
ORDER BY kind;

-- Q14. NEL providers (provider parent QMF) that are not in all 36 months
SELECT "Provider Org Code",
    any_value("Provider Org Name") AS name,
    count(DISTINCT Period) AS months,
    min(strptime(Period, 'RTT-%B-%Y'))::DATE AS first_month,
    max(strptime(Period, 'RTT-%B-%Y'))::DATE AS last_month
FROM raw.rtt_full
WHERE "Provider Parent Org Code" = 'QMF'
GROUP BY 1
HAVING months < 36
ORDER BY months, 1;

-- Q15. Commissioner codes that start or stop inside the window
SELECT "Commissioner Org Code",
    any_value("Commissioner Org Name") AS name,
    count(DISTINCT Period) AS months,
    min(strptime(Period, 'RTT-%B-%Y'))::DATE AS first_month,
    max(strptime(Period, 'RTT-%B-%Y'))::DATE AS last_month
FROM raw.rtt_full
GROUP BY 1
HAVING months < 36
ORDER BY first_month, 1;

-- Q16. Provider parent (ICB) codes that start or stop inside the window
SELECT "Provider Parent Org Code",
    any_value("Provider Parent Name") AS name,
    count(DISTINCT Period) AS months,
    min(strptime(Period, 'RTT-%B-%Y'))::DATE AS first_month,
    max(strptime(Period, 'RTT-%B-%Y'))::DATE AS last_month
FROM raw.rtt_full
GROUP BY 1
HAVING months < 36
ORDER BY first_month, 1;

-- Q17. Old -> new provider parent (ICB) mapping, from providers whose parent changed
--      between March and April 2026
WITH mar AS (
    SELECT DISTINCT "Provider Org Code" AS p, "Provider Parent Org Code" AS old_icb
    FROM raw.rtt_full WHERE Period = 'RTT-March-2026'
), apr AS (
    SELECT DISTINCT "Provider Org Code" AS p, "Provider Parent Org Code" AS new_icb
    FROM raw.rtt_full WHERE Period = 'RTT-April-2026'
)
SELECT old_icb, new_icb, count(*) AS providers_moved
FROM mar JOIN apr USING (p)
WHERE old_icb <> new_icb
GROUP BY ALL
ORDER BY new_icb, old_icb;
