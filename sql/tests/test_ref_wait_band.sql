-- test_ref_wait_band.sql
-- tidy.ref_wait_band must hold the 105 RTT week bands, all parsed, contiguous
-- and unique on lower_wk. Returns one row per failed expectation; no rows = pass.
WITH b AS (
    SELECT *, lag(upper_wk) OVER (ORDER BY band_order) AS prev_upper
    FROM tidy.ref_wait_band
),
stats AS (
    SELECT count(*) AS bands,
        count(*) FILTER (WHERE lower_wk IS NULL) AS unparsed,
        count(*) - count(DISTINCT lower_wk) AS duplicate_lower_wk,
        count(*) FILTER (WHERE prev_upper IS NOT NULL AND lower_wk IS DISTINCT FROM prev_upper) AS gaps,
        count(*) FILTER (WHERE is_open_ended) AS open_ended,
        count(*) FILTER (WHERE within_18_wk) AS within_18_wk,
        count(*) FILTER (WHERE is_52_plus) AS is_52_plus
    FROM b
),
checks AS (
    SELECT 'bands' AS check_name, bands AS actual, 105 AS expected FROM stats
    UNION ALL SELECT 'unparsed', unparsed, 0 FROM stats
    UNION ALL SELECT 'duplicate_lower_wk', duplicate_lower_wk, 0 FROM stats
    UNION ALL SELECT 'gaps', gaps, 0 FROM stats
    UNION ALL SELECT 'open_ended', open_ended, 1 FROM stats
    UNION ALL SELECT 'within_18_wk', within_18_wk, 18 FROM stats
    UNION ALL SELECT 'is_52_plus', is_52_plus, 53 FROM stats
)
SELECT *
FROM checks
WHERE actual IS DISTINCT FROM expected;
