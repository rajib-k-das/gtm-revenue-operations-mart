# Design decisions

Each entry records a modeling choice, the alternatives considered, and why this one won.

## 001 — A fictional company, generated reproducibly

**Choice:** "Kestrel Cloud", a fictional B2B SaaS company selling a data platform. FY2023–FY2025 (fiscal year = calendar
year), extract date 31 January 2026. Two segments (Mid-Market, Enterprise), three regions (North America, EMEA, APAC),
24 account executives, 3,000 accounts and about 4,000 opportunities (new business, expansion, renewal).
`generate/generate_crm.py` uses a fixed seed, so every run produces identical data; CI regenerates it, so nothing is committed.
**Why:** real CRM data is never public. A generator also makes the data's true behaviour known, which decision 003 uses.
**Rejected:** public "CRM sales" datasets. They have final outcomes only, with no history of stage, amount or close-date
changes, which rules out point-in-time pipeline, waterfalls and forecast accuracy.

## 002 — Opportunity history as SCD Type 2

**Choice:** the extract includes an opportunity history table like Salesforce's OpportunityHistory: one row per change,
with the full state after the change. dbt turns it into versions with `valid_from` / `valid_to` (`int_opportunity_versions`).
A version is valid at instant *t* when `valid_from <= t < valid_to`. "As of a date" means the end of that day.
**Why:** RevOps questions are about the past as it was ("what was in the pipeline on 1 April?"), not as it is now.
**Rejected:** dbt's `snapshot` feature. It captures history from repeated runs going forward and cannot rebuild
three years after the fact.
**Tested:** every opportunity has exactly one current version, windows never overlap or leave gaps, and the current
version rebuilt from the history matches the separate current-state table exactly.

## 003 — Planted behaviours as a validation harness

**Choice:** the generator plants five known behaviours, and the analysis must find each one:
P1 end-of-quarter scrub (deals due this quarter, not yet in Negotiation, pushed to next quarter ten days before quarter end);
P2 hockey stick (late-quarter wins bunch into the final week); P3 APAC creates ~50% more pipeline per rep but converts it at
about half the rate; P4 three reps forecast optimistically, two conservatively; P5 Enterprise deals are ~5x larger and
take ~2x longer. Each rep's planted forecast style is kept in `dim_rep.planted_forecast_style` as an answer key only.
**Why:** with synthetic data, "findings" mean nothing unless the method is shown to recover what is known to be there.
This is a known-answer test at the scale of the whole company.
**Counter-argument weighed:** planted findings can look contrived. They are presented as a validation of the pipeline,
not as discoveries.

## 004 — Metric definitions

**Choice:** one documented definition per metric, used everywhere.
- **Pipeline for quarter Q at time t:** open opportunities whose close date falls in Q, at their amount at time t.
- **Pipeline waterfall** (`fct_pipeline_waterfall`), per quarter and rep:
  opening + created + pulled in − won − lost − moved out + amount change = closing, to the cent.
  Inflows are valued at the amount at the end of the quarter (or at closing); moved-out deals at their opening amount;
  amount change absorbs price changes and the gap between a deal's opening amount and the amount it was won at.
  Deals that entered and left a quarter's pipeline without closing net to zero and are not shown.
- Win rate, conversion, velocity and forecast accuracy follow in Layer 2.
**Tested:** every waterfall row reconciles, and its opening and closing equal the pipeline snapshot model's totals,
which are computed separately. The hand-built test company checks every bucket against a known answer.

## 005 — Build in two layers

**Choice:** Layer 1 is the generator, staging, SCD2 history, point-in-time pipeline snapshots and the waterfall.
Layer 2 adds win rates, stage conversion and velocity, forecast accuracy by rep, an ARR bridge and the dashboard.
**Why:** the point-in-time foundation has to be right before anything is measured on top of it.

## 006 — A lost deal counts against the quarter it was due in

**Found while building:** the CRM overwrites a lost deal's close date with the day it was lost. Taken at face value, a deal
due next quarter but lost this quarter looked like it was pulled into this quarter and then lost, which inflated both
"created" and "lost" (lost exceeded the whole opening pipeline every quarter).
**Choice:** a lost deal counts against the quarter of its close date just before it was lost. Won deals count in the
quarter of their booking date. A deal pushed out of the quarter and lost later counts as moved out.

## 007 — Snapshots at week and quarter ends

**Choice:** `fct_pipeline_snapshots` stores the open pipeline at the end of every Sunday, every quarter end and the
extract date (about 170 dates).
**Why:** weekly is the cadence sales leaders review pipeline at, and quarter ends anchor the waterfall.
Daily snapshots would multiply the table by seven for no extra insight; any other date can be rebuilt from the versions.
