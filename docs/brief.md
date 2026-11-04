# Stakeholder brief: Elective Backlog Diagnostic

**Version:** 0.1 · 4 November 2026 · Author: Zohaib Ahmed

## Decision to support

The **Director of Elective Recovery at NHS North East London ICB** has recovery money to place over the next two quarters (insourcing, validation, mutual aid). They need to know **where the backlog is stuck, why, and which intervention moves the longest waiters fastest.**

This project gives them a ranked, evidence-based answer from public data.

## Scope

| Item | Decision |
|---|---|
| ICB | NHS North East London |
| Providers | Main acute trusts: Barts Health (R1H), Homerton Healthcare (RQX), Barking, Havering and Redbridge University Hospitals (RF4). *Codes to be confirmed against the RTT files in Week 1.* |
| Commissioner filter | Pathways commissioned by North East London ICB, at the providers above |
| Time window | Latest 36 published months: **September 2023 to August 2026** |
| Specialties | All treatment functions kept; ranked during analysis. Small specialties pooled into "Other" below a minimum list size |
| Data | NHS England RTT waiting times (provider-level Full CSV files); ONS mid-year population estimates for per-100,000 rates |

## Questions this project must answer

1. **Where are the long waiters?** Which specialties and providers hold most 52+ week waiters, and is their share rising or falling?
2. **Caseload or operations?** Is each provider's gap to the ICB's 18-week performance caused by its specialty mix (mix effect) or by slower treatment within the same specialty (rate effect)?
3. **How much capacity closes the gap?** How many extra clock stops per week, by specialty, are needed to reach a chosen target by a chosen date, compared with the trailing 12-week run rate?
4. **What works best?** Which of three interventions reduces the 52+ week cohort most within six months?
   - A one-off validation sprint
   - +10% non-admitted clock stops
   - Insourced extra stops in the top two specialties

Each question ends in one written finding with a number, in `docs/findings.md`.

## KPI definitions

| KPI | Definition |
|---|---|
| % incomplete within 18 weeks | Incomplete pathways in bands ending at or below 18 weeks ÷ total incomplete pathways. Constitutional standard: 92% |
| 52+ week waiters | Incomplete pathways in bands starting at 52 weeks or more |
| Net list change | Incomplete pathways this month − incomplete pathways last month |
| 92nd percentile wait | Weeks waited by the 92nd percentile pathway, interpolated within the wait band where the cumulative share crosses 0.92. The open-ended top band uses a documented cap |
| Unreported removals | Last month's list + clock starts − clock stops − this month's list. A positive value means pathways left the list without a reported stop (often validation) |

Clock starts are new RTT periods. Clock stops are completed admitted pathways plus completed non-admitted pathways.

## Out of scope

- Patient-level data of any kind
- Diagnostic waits and cancer waiting times
- Cost modelling beyond assumptions stated in the scenario table
- Any client data or figures from my own work. Public open data only

## Assumptions and known caveats

- Missing trust submissions are flagged from NHS England's missing-data adjustments file and never interpolated silently.
- Revised months use the latest published file, recorded in `data/raw/manifest.csv`.
- Survival and clearance rates from banded data are estimates, because validation removals mix into them.
- Scenario outputs depend on stated assumptions; each scenario chart sits next to its assumptions table and a ±50% sensitivity run.

## Deliverables

- A 3-page Power BI report: Answer, Diagnosis, Scenarios
- A one-page decision memo (`docs/memo.pdf`) with ranked recommendations
- Notebooks that reproduce every number in the memo
- A README a reader can understand in 60 seconds

## Done when

- One command rebuilds everything from the raw files.
- All tests pass and the reconciliation to published figures is documented.
- Each of the four questions has a written finding with a number.
