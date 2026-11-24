# Elective Backlog Diagnostic

Where is the elective waiting list stuck in North East London, why, and which intervention would clear the longest waiters fastest?

This project is built to answer that for the Director of Elective Recovery at NHS North East London ICB, using only public NHS England data. It covers the ICB's three main acute trusts over the latest 36 published months (September 2023 to August 2026).

> **Status: in progress.** The data pipeline and its tests are built. The analysis, findings, Power BI report and decision memo are still to come. See [Progress](#progress).

## The questions

1. Which specialties and providers hold most 52+ week waiters, and is their share rising or falling?
2. Is each provider's gap to the ICB's 18-week performance caused by its specialty mix, or by slower treatment within the same specialty?
3. How many extra clock stops per week, by specialty, are needed to reach a target by a chosen date?
4. Which of three interventions reduces the 52+ week cohort most within six months: a validation sprint, 10% more non-admitted clock stops, or insourcing in the top two specialties?

Each question will end in one written finding with a number, in `docs/findings.md`.

## Scope

| | |
|---|---|
| ICB | NHS North East London |
| Providers | Barts Health (R1H), Homerton Healthcare (RQX), Barking, Havering and Redbridge University Hospitals (RF4) |
| Period | September 2023 to August 2026 (36 months) |
| Data | NHS England Referral to Treatment (RTT) waiting times, provider-level Full CSV files |
| Out of scope | Patient-level data, diagnostic and cancer waits, cost modelling |

Every source is public open data. The project uses no patient-level records and no client figures.

## How it works

One command downloads the data, builds the database and runs the tests:

```bash
python build.py
```

The build runs five steps in order:

1. Download (`ingest/download.py`) fetches each month's zip from NHS England, records its SHA-256 hash in `data/raw/manifest.csv` and skips files it already has. When NHS England revises a month, it uses the latest file and records the version.
2. Extract (`ingest/extract.py`) unzips the current version of each month and deletes stale CSVs, so a revised month is never loaded twice.
3. Load (`sql/01_load.sql`) reads every monthly file into `raw.rtt_full` in DuckDB. Organisation and treatment-function codes are stored as text so leading zeros survive.
4. Tidy (`sql/02_tidy.sql`) filters to the three trusts, unpivots the weekly wait-band columns into rows, and builds a reference table of wait bands parsed from the column names.
5. Test (`sql/tests/`) checks the tidy tables, including a reconciliation of wait-band counts to reported totals. The build fails if any test returns rows.

The database is written to `data/processed/rtt.duckdb`. Derived data stays out of Git.

## Key measures

| Measure | Definition |
|---|---|
| % within 18 weeks | Incomplete pathways in bands ending at or below 18 weeks ÷ all incomplete pathways (standard: 92%) |
| 52+ week waiters | Incomplete pathways in bands starting at 52 weeks or more |
| Net list change | This month's waiting list − last month's |
| 92nd percentile wait | Interpolated within the band where the cumulative share passes 0.92, with a documented cap on the open-ended top band |
| Unreported removals | Last month's list + clock starts − clock stops − this month's list. A positive value means pathways left the list without a recorded treatment, often through validation |

## Caveats

- Months where a trust submitted no data are flagged from NHS England's missing-data file and are not interpolated.
- Survival and clearance rates are estimates, because banded data mixes validation removals in with treatment.
- Scenario results depend on their assumptions. Each scenario chart will sit next to its assumptions table and a ±50% sensitivity run.

## Repository layout

```
ingest/        download and extract scripts
sql/           load and tidy steps, exploration queries, tests
analysis/      Python analysis
docs/          brief, data dictionary, schema notes
data/raw/      download manifest (data files are not committed)
build.py       runs the whole pipeline
```

## Progress

- [x] Scope and stakeholder brief (`docs/brief.md`)
- [x] Download, extract and load 36 months of RTT data
- [x] Data dictionary (`docs/data_dictionary.md`)
- [x] Tidy tables and automated tests
- [ ] KPI tables in SQL, reconciled to the NHS England RTT dashboard
- [ ] Analysis notebooks and written findings
- [ ] Power BI report (Answer, Diagnosis, Scenarios)
- [ ] One-page decision memo

## Requirements

Python 3.12 and the DuckDB Python package.

## Licence

MIT
