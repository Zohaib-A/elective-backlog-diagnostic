-- test_band_reconciliation.sql
-- Every banded row in tidy.rtt_total (Part_1A, Part_1B, Part_2, Part_2A) must
-- have bands in tidy.rtt_band that sum to total_all - unknown_clock_start, and
-- Part_3 must have no bands. Comparisons use IS DISTINCT FROM, so a null
-- total_all or a missing band set fails instead of slipping through.
-- Returns one row per failing fact row; no rows = pass.
WITH b AS (
    SELECT period, provider_code, commissioner_code, part_type, tfc,
        sum(pathways) AS band_sum,
        count(*) AS band_rows
    FROM tidy.rtt_band
    GROUP BY ALL
)
SELECT CASE
        WHEN t.part_type = 'Part_3' THEN 'Part_3 row has bands'
        WHEN b.band_rows IS NULL THEN 'banded row has no bands'
        ELSE 'band sum does not match total_all - unknown_clock_start'
    END AS failure,
    t.period, t.provider_code, t.commissioner_code, t.part_type, t.tfc,
    t.total_all, t.unknown_clock_start, b.band_sum, b.band_rows
FROM tidy.rtt_total t
LEFT JOIN b USING (period, provider_code, commissioner_code, part_type, tfc)
WHERE (t.part_type = 'Part_3' AND b.band_rows IS NOT NULL)
    OR (t.part_type <> 'Part_3'
        AND (b.band_rows IS NULL
             OR b.band_sum IS DISTINCT FROM t.total_all - coalesce(t.unknown_clock_start, 0)));
