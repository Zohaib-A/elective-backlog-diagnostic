-- test_rtt_total.sql
-- tidy.rtt_total must be unique on its grain, have no null key or total_all,
-- and contain every provider in tidy.ref_scope_provider.
-- Returns one row per failure; no rows = pass.
SELECT 'duplicate key' AS failure,
    period, provider_code, commissioner_code, part_type, tfc
FROM tidy.rtt_total
GROUP BY ALL
HAVING count(*) > 1

UNION ALL
SELECT 'null key or total_all',
    period, provider_code, commissioner_code, part_type, tfc
FROM tidy.rtt_total
WHERE period IS NULL OR provider_code IS NULL OR commissioner_code IS NULL
    OR part_type IS NULL OR tfc IS NULL OR total_all IS NULL

UNION ALL
SELECT 'scope provider has no rows',
    NULL, s.provider_code, NULL, NULL, NULL
FROM tidy.ref_scope_provider s
ANTI JOIN tidy.rtt_total t USING (provider_code);
