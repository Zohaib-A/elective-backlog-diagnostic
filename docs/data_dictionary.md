# Data dictionary: `raw.rtt_full`

**Database:** `data/processed/rtt.duckdb` · **Built by:** `sql/01_load.sql` · **Column list:** `docs/schema_raw_rtt_full.txt`

`raw.rtt_full` holds every row of the 36 NHS England RTT Full CSV extracts (September 2023 to August 2026), stacked unchanged. Nothing is filtered or reshaped here; later scripts do that.

Profile figures below come from the build on 4 November 2026: **6,599,919 rows, 36 files, 36 periods.**

Every figure in this document comes from a query in [`sql/explore/profile_raw_rtt_full.sql`](../sql/explore/profile_raw_rtt_full.sql), cited below as Q1 to Q17. The file is read-only and is not run by `build.py`. To reproduce the figures:

```
duckdb -readonly data/processed/rtt.duckdb < sql/explore/profile_raw_rtt_full.sql
```

## Grain

One row per **Period × Provider Org Code × Commissioner Org Code × RTT Part Type × Treatment Function Code**.

Each row is a count of pathways (not patients) for that combination, split into weekly wait bands.

**Tested unique (Q2):** rows = 6,599,919, distinct keys = 6,599,919, duplicate rows = 0, rows with a null key column = 0. The parent codes and names are not part of the key; they are attributes of the provider and commissioner codes.

## Identifier columns

| #   | Column                         | Type    | Description                                                                                              | Example                                       |
| --- | ------------------------------ | ------- | -------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| 1   | `Period`                       | VARCHAR | Reporting month as text, `RTT-<Month>-<YYYY>`. Sorts alphabetically, not by date. Parse before ordering. | `RTT-August-2026`                             |
| 2   | `Provider Parent Org Code`     | VARCHAR | Code of the ICB the provider sits in (48 distinct).                                                      | `QMF`                                         |
| 3   | `Provider Parent Name`         | VARCHAR | Name of that ICB.                                                                                        | `NHS NORTH EAST LONDON INTEGRATED CARE BOARD` |
| 4   | `Provider Org Code`            | VARCHAR | ODS code of the provider trust or independent sector site (589 distinct).                                | `R1H`                                         |
| 5   | `Provider Org Name`            | VARCHAR | Provider name.                                                                                           | `BARTS HEALTH NHS TRUST`                      |
| 6   | `Commissioner Parent Org Code` | VARCHAR | Code of the commissioning ICB. Null for specialised commissioning hubs and `NONC` rows (see notes).      | `QMF`                                         |
| 7   | `Commissioner Parent Name`     | VARCHAR | Name of the commissioning ICB.                                                                           | `NHS NORTH EAST LONDON INTEGRATED CARE BOARD` |
| 8   | `Commissioner Org Code`        | VARCHAR | Sub-ICB location or commissioning hub code (130 distinct).                                               | `A3A8R`                                       |
| 9   | `Commissioner Org Name`        | VARCHAR | Commissioner name. Wording changes between months for some codes.                                        | `NHS NORTH EAST LONDON (SUB ICB LOCATION)`    |
| 10  | `RTT Part Type`                | VARCHAR | Which measure the row counts. See [RTT part types](#rtt-part-types).                                     | `Part_2`                                      |
| 11  | `RTT Part Description`         | VARCHAR | Text label for `RTT Part Type`.                                                                          | `Incomplete Pathways`                         |
| 12  | `Treatment Function Code`      | VARCHAR | Specialty code. `C_999` is the all-specialty total. See [Treatment functions](#treatment-functions).     | `C_110`                                       |
| 13  | `Treatment Function Name`      | VARCHAR | Specialty name.                                                                                          | `Trauma and Orthopaedic Service`              |

All code and name columns are pinned to VARCHAR in the load so codes such as `06Q` or `C_999` are never type-sniffed.

## Measure columns

| #      | Column                                   | Type    | Description                                                                                                                                                                                    |
| ------ | ---------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 14–117 | `Gt NN To MM Weeks SUM 1`                | BIGINT  | Pathways that had waited more than NN and up to MM weeks at the period end (or at clock stop, for completed parts). 104 one-week bands from `Gt 00 To 01` to `Gt 103 To 104`. Null means zero. |
| 118    | `Gt 104 Weeks SUM 1`                     | BIGINT  | Open-ended top band: more than 104 weeks. The 92nd percentile calculation needs a documented cap for this band.                                                                                |
| 119    | `Total`                                  | BIGINT  | Sum of the week bands. Filled for Part_1A and Part_1B only; null for Part_2, Part_2A and Part_3.                                                                                               |
| 120    | `Patients with unknown clock start date` | BIGINT  | Completed pathways with no recorded clock start, so no wait band. Filled for Part_1A and Part_1B only.                                                                                         |
| 121    | `Total All`                              | BIGINT  | Row total including unknown clock starts. The one total filled for every part type.                                                                                                            |
| 122    | `filename`                               | VARCHAR | Source CSV path, added by the load (`filename = true`). Shows which extract (original or revised) a row came from.                                                                             |

### How the totals fit together

Checked against every row in the build (Q5, 0 mismatches):

| Part type        | Rule                                                                  |
| ---------------- | --------------------------------------------------------------------- |
| Part_1A, Part_1B | sum of bands = `Total`; `Total` + unknown clock start = `Total All`   |
| Part_2, Part_2A  | sum of bands = `Total All` (`Total` and unknown clock start are null) |
| Part_3           | all bands null; `Total All` is the count of new clock starts          |

Use `Total All` as the headline count for every part type. Use the bands only for Part_1A, Part_1B, Part_2 and Part_2A.

## RTT part types

| Code      | Description                                  | Rows      | What it counts                                                                              | Used for                                                       |
| --------- | -------------------------------------------- | --------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `Part_1A` | Completed Pathways For Admitted Patients     | 677,204   | Clock stops this month where the patient was admitted for treatment, banded by wait at stop | Clock stops                                                    |
| `Part_1B` | Completed Pathways For Non-Admitted Patients | 1,153,791 | Clock stops this month without admission (outpatient treatment, discharge, etc.)            | Clock stops; +10% non-admitted scenario                        |
| `Part_2`  | Incomplete Pathways                          | 2,356,942 | Pathways still waiting at month end, banded by time waited so far                           | Waiting list, % within 18 weeks, 52+ weeks, 92nd percentile    |
| `Part_2A` | Incomplete Pathways with DTA                 | 1,096,469 | Subset of Part_2 with a decision to admit                                                   | Admitted backlog. Do not add to Part_2; it is already included |
| `Part_3`  | New RTT Periods - All Patients               | 1,315,513 | Clock starts in the month (no wait bands)                                                   | Clock starts                                                   |

## Treatment functions

The file reports 18 named specialties, five "Other" groups and a total.

| Code    | Name                              | Code    | Name                                |
| ------- | --------------------------------- | ------- | ----------------------------------- |
| `C_100` | General Surgery Service           | `C_330` | Dermatology Service                 |
| `C_101` | Urology Service                   | `C_340` | Respiratory Medicine Service        |
| `C_110` | Trauma and Orthopaedic Service    | `C_400` | Neurology Service                   |
| `C_120` | Ear Nose and Throat Service       | `C_410` | Rheumatology Service                |
| `C_130` | Ophthalmology Service             | `C_430` | Elderly Medicine Service            |
| `C_140` | Oral Surgery Service              | `C_502` | Gynaecology Service                 |
| `C_150` | Neurosurgical Service             | `X02`   | Other - Medical Services            |
| `C_160` | Plastic Surgery Service           | `X03`   | Other - Mental Health Services      |
| `C_170` | Cardiothoracic Surgery Service    | `X04`   | Other - Paediatric Services         |
| `C_300` | General Internal Medicine Service | `X05`   | Other - Surgical Services           |
| `C_301` | Gastroenterology Service          | `X06`   | Other - Other Services              |
| `C_320` | Cardiology Service                | `C_999` | **Total** (all treatment functions) |

`C_999` duplicates the sum of the other codes. **Exclude it when summing across specialties**, or use it alone for all-specialty figures.

## Project scope values

| Item                 | Column                         | Values                                                                                                                                                                                  |
| -------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Providers            | `Provider Org Code`            | `R1H` Barts Health NHS Trust · `RQX` Homerton Healthcare NHS Foundation Trust · `RF4` Barking, Havering and Redbridge University Hospitals NHS Trust (codes confirmed in the data, Q10) |
| Commissioner ICB     | `Commissioner Parent Org Code` | `QMF` NHS North East London ICB (all 36 months, Q11)                                                                                                                                    |
| Commissioner sub-ICB | `Commissioner Org Code`        | `A3A8R` (all 36 months; the only sub-ICB under `QMF`, Q11)                                                                                                                              |

Filter on codes, never on names; names drift between months.

## KPI to column mapping

| KPI (from `docs/brief.md`)   | Source                                                                               |
| ---------------------------- | ------------------------------------------------------------------------------------ |
| Incomplete pathways          | `Part_2`, `Total All`                                                                |
| % incomplete within 18 weeks | `Part_2`: sum of bands `Gt 00 To 01` … `Gt 17 To 18` ÷ `Total All`                   |
| 52+ week waiters             | `Part_2`: sum of bands `Gt 52 To 53` … `Gt 104 Weeks`                                |
| 92nd percentile wait         | `Part_2` bands, interpolated within the band where the cumulative share crosses 0.92 |
| Clock starts                 | `Part_3`, `Total All`                                                                |
| Clock stops                  | `Part_1A` + `Part_1B`, `Total All`                                                   |
| Net list change              | `Part_2` `Total All` this month − last month                                         |
| Unreported removals          | last month's `Part_2` + `Part_3` − (`Part_1A` + `Part_1B`) − this month's `Part_2`   |

## Data quality notes

- **Null bands mean zero.** Bands are blank in the source CSV when the count is zero. Wrap them in `coalesce(..., 0)` before summing, or use `list_sum`, which skips nulls. (Q5 reconciles to the totals on that basis.)
- **Null commissioner parent.** 141,805 Part_2 rows (and similar shares of the other parts, Q8) have no `Commissioner Parent Org Code`. These are specialised commissioning hubs (e.g. `13Q` National Commissioning Hub 1, `14M` London H&J Commissioning Hub) and `NONC` (non-contracted, name `#N/A`). A filter on `QMF` drops them, so NEL providers' totals will not reconcile to provider-level published figures unless these rows are included.
- **Name drift.** 106 commissioner codes and 19 provider codes have more than one name across the window, with up to three names per code (Q9; e.g. `06Q`, `A3A8R`). Join and filter on codes.
- **Period is text.** `min(Period)` returns `RTT-April-2024`, not the first month. Convert with `strptime(Period, 'RTT-%B-%Y')` or derive the month from `filename`.
- **Revisions.** Revised months replace originals; `ingest/extract.py` keeps only the current extract per period, so there is no double counting. `filename` ends in `-revised` when the revised file was used.
- **Missing submissions.** Trusts that did not submit for a month are absent, not zero. Flag them from `data/raw/reference/2026-08/Missing-data-adjustments-to-Aug26-XLSX-109K-vjgRdG.xlsx`.

### Organisation changes

**Scope providers (Q10, Q12):**

| Code  | Months present | First    | Last     | Parent ICB       |
| ----- | -------------- | -------- | -------- | ---------------- |
| `R1H` | 36 of 36       | Sep 2023 | Aug 2026 | `QMF` throughout |
| `RQX` | 36 of 36       | Sep 2023 | Aug 2026 | `QMF` throughout |
| `RF4` | **35 of 36**   | Sep 2023 | Aug 2026 | `QMF` throughout |

- **RF4 is missing for November 2025.** It has no rows at all that month, so scope rows drop from about 300 a month to 201 (Q12). NHS England's missing-data adjustments file confirms the gap: it lists an RF4 estimate for November 2025 based on October 2025 (58,662 incomplete pathways, 11,928 non-admitted, 2,413 admitted, 16,466 clock starts). That month must be flagged in every RF4 and ICB series. November 2025 net list change, and October-to-December comparisons, are not valid for RF4 without the estimate. For December 2025, the month-on-month change must compare against October 2025 or against the estimate.
- None of the three scope trusts changed code or parent ICB in the window. `QMF` and `A3A8R` are present in all 36 months (Q11).

**Other NEL providers (provider parent `QMF`, Q14):** three smaller providers are not in all 36 months. They are outside the brief's provider scope, but they count towards any ICB-wide total built from `Provider Parent Org Code = 'QMF'`.

| Code    | Name                                   | Months | First    | Last     |
| ------- | -------------------------------------- | ------ | -------- | -------- |
| `RAT`   | North East London NHS Foundation Trust | 5      | Sep 2023 | Jan 2024 |
| `V8N5R` | SpaMedica Dalston                      | 30     | Mar 2024 | Aug 2026 |
| `V3J9W` | Pastel Health                          | 11     | Oct 2025 | Aug 2026 |

**Code churn across the whole file (Q13):**

| Level                 | Codes | In all 36 months | Appear after Sep 2023 | Disappear before Aug 2026 | With gaps |
| --------------------- | ----- | ---------------- | --------------------- | ------------------------- | --------- |
| Provider              | 589   | 406              | 130                   | 56                        | 14        |
| Commissioner          | 130   | 126              | 2                     | 1                         | 2         |
| Provider parent (ICB) | 48    | 30               | 6                     | 12                        | 0         |

- **ICB mergers, April 2026 (Q16).** Twelve ICB codes stop after March 2026 and six new ones start in April 2026. The changes are not all one-to-one. Q17 maps old codes to new ones from the providers that moved between March and April 2026. North Central London (`QMJ`) and North West London (`QRV`) merge cleanly into West and North London (`Z9B2Z`). Others split: Frimley (`QNQ`) providers go to `S0E4D`, `S9B9J` and `QRL`, and Hertfordshire and West Essex (`QM7`) providers go to `D7T5G` and `S1Y5D`. The sub-ICB code `D4U1Y` (Frimley) stops in March 2026, and `U2G6B` (Thames Valley) starts in April 2026 (Q15). North East London (`QMF`) is not affected, but any London or England benchmark that groups by ICB code will break at April 2026. Trend benchmarks at provider-code level, or map old codes to new ones with Q17 first.
- **Provider churn** is mostly independent sector sites starting or stopping. Trend at a fixed set of provider codes, not at "all providers in the month".
- **Pathways, not patients.** One patient can have more than one open pathway.
