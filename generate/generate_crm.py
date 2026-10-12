"""
Generate a synthetic, Salesforce-style CRM extract for a fictional B2B SaaS company, "Kestrel Cloud".

Why synthetic: real CRM data is never public. Instead of hiding that, the generator plants known behaviours
(listed below) so the warehouse can be validated against a ground truth: the analysis must find each one.

Output (CSV, Salesforce-like column names) in --out-dir (default data/raw):
    users.csv                 account executives (24), with region, segment and a hidden forecast style
    accounts.csv              ~3,000 customer and prospect accounts
    opportunities.csv         current state of every opportunity
    opportunity_history.csv   one row per change, with the full state after the change
                              (like Salesforce's OpportunityHistory: stage, amount, close date, forecast category)
    contracts.csv             12-month subscription contracts created by won deals (like Salesforce's Contract object),
                              each renewal contract linked to the contract it renews
    quotas.csv                quarterly new-bookings quota per rep

Planted behaviours (the "answer key"; see docs/decisions.md, decision 003):
    P1  End-of-quarter scrub: ten days before quarter end, deals due this quarter that are not yet in Negotiation are often pushed
        to next quarter, so close-date push-outs spike in the last weeks of a quarter.
    P2  Hockey stick: deals that are about to close late in a quarter tend to close in its final week.
    P3  APAC creates ~50% more pipeline per rep but converts it at about half the rate.
    P4  Forecast bias: three reps call Proposal-stage deals "Commit" (optimistic); two leave Negotiation-stage
        deals in "Best Case" (conservative).
    P5  Enterprise deals are ~5x larger and take ~2x longer to close.

The random seed is fixed, so every run produces identical data.

Usage:
    python generate/generate_crm.py                      # writes data/raw/*.csv
    python generate/generate_crm.py --out-dir somewhere
"""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SEED = 20260131
START = date(2023, 1, 1)
CUTOFF = date(2026, 1, 31)          # the "extract date": nothing happens after this day

STAGES = ["1-Discovery", "2-Qualification", "3-Solution", "4-Proposal", "5-Negotiation"]
WON, LOST = "Closed Won", "Closed Lost"
STAGE_PROBABILITY = {STAGES[0]: 10, STAGES[1]: 20, STAGES[2]: 40, STAGES[3]: 60, STAGES[4]: 80, WON: 100, LOST: 0}
ADVANCE = [0.65, 0.70, 0.75, 0.80, 0.75]          # chance of moving to the next stage (last step = win)

REGIONS = {"North America": (6, 4), "EMEA": (5, 3), "APAC": (4, 2)}   # (Mid-Market reps, Enterprise reps)
SEGMENTS = ("Mid-Market", "Enterprise")

rng = np.random.default_rng(SEED)


# ---------------------------------------------------------------- calendar helpers
def quarter_end(d: date) -> date:
    q_last_month = ((d.month - 1) // 3) * 3 + 3
    return (date(d.year + (q_last_month == 12), 1 if q_last_month == 12 else q_last_month + 1, 1) - timedelta(days=1))


def month_end(d: date) -> date:
    return date(d.year + (d.month == 12), 1 if d.month == 12 else d.month + 1, 1) - timedelta(days=1)


def at(d: date, hour: float) -> datetime:
    return datetime.combine(d, time(0)) + timedelta(hours=hour)


def business_time(d: date) -> datetime:
    return at(d, float(rng.uniform(8, 18)))


# ---------------------------------------------------------------- entities
@dataclass
class Rep:
    id: str
    name: str
    region: str
    segment: str
    forecast_style: str = "accurate"


@dataclass
class Account:
    id: str
    name: str
    region: str
    segment: str
    industry: str
    owner_id: str
    first_win: date | None = None
    first_win_amount: float = 0.0


@dataclass
class Contract:
    id: str
    opportunity: "Opportunity"
    start: date
    end: date
    arr: float
    renews: "Contract | None" = None


def one_year_later(d: date) -> date:
    """Last day of a 12-month term starting on d."""
    try:
        return d.replace(year=d.year + 1) - timedelta(days=1)
    except ValueError:                                    # 29 February
        return date(d.year + 1, 2, 28)


@dataclass
class Opportunity:
    id: str
    account: Account
    owner: Rep
    type: str
    created: datetime
    amount: float
    close_date: date
    renews_contract_id: str = ""                          # renewals only: the contract up for renewal
    versions: list = field(default_factory=list)


FIRST = ["Avery", "Jordan", "Morgan", "Riley", "Casey", "Quinn", "Taylor", "Harper", "Rowan", "Elliot", "Sasha",
         "Dana", "Kai", "Noor", "Mira", "Theo", "Lena", "Omar", "Priya", "Mateo", "Ines", "Yuki", "Ravi", "Zara"]
LAST = ["Holt", "Marsh", "Vance", "Reyes", "Okafor", "Lindqvist", "Brennan", "Kato", "Duarte", "Novak", "Shah",
        "Moreau", "Fischer", "Tanaka", "Osei", "Kowalski", "Hart", "Ibarra", "Nakamura", "Quist", "Sorensen",
        "Adeyemi", "Castillo", "Weber"]
NAME_A = ["Blue", "North", "Silver", "Granite", "Harbor", "Summit", "Cedar", "Bright", "Iron", "Clear", "Pine",
          "River", "Atlas", "Nova", "Crest", "Delta", "Echo", "Falcon", "Lumen", "Orbit"]
NAME_B = ["peak", "field", "stone", "line", "path", "works", "bridge", "point", "gate", "wave"]
NAME_C = ["Logistics", "Health", "Retail", "Energy", "Capital", "Foods", "Labs", "Media", "Systems", "Mobility"]
INDUSTRY = {"Logistics": "Transportation", "Health": "Healthcare", "Retail": "Retail", "Energy": "Energy",
            "Capital": "Financial Services", "Foods": "Consumer Goods", "Labs": "Life Sciences", "Media": "Media",
            "Systems": "Technology", "Mobility": "Transportation"}


def build_reps() -> list[Rep]:
    reps, n = [], 0
    for region, (mm, ent) in REGIONS.items():
        for segment, count in (("Mid-Market", mm), ("Enterprise", ent)):
            for _ in range(count):
                n += 1
                reps.append(Rep(f"005{n:012d}", f"{FIRST[n - 1]} {LAST[n - 1]}", region, segment))
    # P4: forecast bias, assigned to fixed reps so it is reproducible and spread across regions
    for i in (1, 11, 17):
        reps[i].forecast_style = "optimistic"
    for i in (4, 14):
        reps[i].forecast_style = "conservative"
    return reps


def build_accounts(reps: list[Rep]) -> list[Account]:
    accounts = []
    regions, segments = list(REGIONS), list(SEGMENTS)
    for n in range(1, 3001):
        region = regions[rng.choice(3, p=[0.45, 0.33, 0.22])]
        segment = segments[rng.choice(2, p=[0.75, 0.25])]
        owners = [r for r in reps if r.region == region and r.segment == segment]
        c = NAME_C[rng.integers(len(NAME_C))]
        name = f"{NAME_A[rng.integers(len(NAME_A))]}{NAME_B[rng.integers(len(NAME_B))]} {c} {n:04d}"
        accounts.append(Account(f"001{n:012d}", name, region, segment, INDUSTRY[c], owners[rng.integers(len(owners))].id))
    return accounts


# ---------------------------------------------------------------- opportunity simulation
def forecast_category(stage: str, style: str) -> str:
    if stage == WON:
        return "Closed"
    if stage == LOST:
        return "Omitted"
    if stage in STAGES[:2]:
        return "Pipeline"
    if stage == STAGES[3] and style == "optimistic":
        return "Commit"                                   # P4
    if stage == STAGES[4]:
        return "Best Case" if style == "conservative" else "Commit"   # P4
    return "Best Case"


def simulate(opp: Opportunity, start_stage: int, advance_mult: float, dwell_days: float,
             negotiate: bool = True) -> tuple[str, date | None]:
    """Walk one opportunity through its life, recording a version (full state) at every change."""
    stage_idx, stage = start_stage, STAGES[start_stage]
    style = opp.owner.forecast_style

    def record(ts: datetime) -> None:
        if opp.versions and ts <= opp.versions[-1]["ts"]:
            ts = opp.versions[-1]["ts"] + timedelta(minutes=5)
        opp.versions.append({"ts": ts, "stage": stage, "amount": round(opp.amount, 2), "close": opp.close_date,
                             "fc": forecast_category(stage, style), "prob": STAGE_PROBABILITY[stage]})

    record(opp.created)
    t = opp.created
    next_stage = business_time(t.date() + timedelta(days=int(rng.gamma(2.0, dwell_days / 2.0)) + 1))
    while True:
        qe = quarter_end(t.date())
        scrub = at(qe - timedelta(days=10), 17.0)
        if scrub <= t:
            scrub = at(quarter_end(qe + timedelta(days=1)) - timedelta(days=10), 17.0)
        overdue = at(opp.close_date + timedelta(days=3), 10.0)
        if overdue <= t:
            overdue = t + timedelta(hours=1)
        event = min(next_stage, scrub, overdue)
        if event.date() > CUTOFF:
            return "open", None
        t = event

        if event == overdue:                              # rep notices the close date has passed
            opp.close_date = month_end(t.date() + timedelta(days=20))
            record(t)
            continue
        if event == scrub:                                # P1: end-of-quarter scrub of early-stage deals
            if stage_idx <= 3 and quarter_end(opp.close_date) == quarter_end(t.date()) and rng.random() < 0.55:
                opp.close_date = quarter_end(quarter_end(t.date()) + timedelta(days=1))
                record(t)
            continue

        # stage event
        if rng.random() > min(ADVANCE[stage_idx] * advance_mult, 0.97):
            stage, opp.close_date = LOST, t.date()
            record(t)
            return "lost", t.date()
        if stage_idx == 4:                                # win
            days_left = (quarter_end(t.date()) - t.date()).days
            if days_left <= 21 and rng.random() < 0.6:    # P2: hockey stick into the quarter's last week
                snapped = at(quarter_end(t.date()) - timedelta(days=int(rng.integers(0, 6))), float(rng.uniform(9, 18)))
                if t < snapped and snapped.date() <= CUTOFF:
                    t = snapped
            stage, opp.close_date = WON, t.date()
            record(t)
            return "won", t.date()
        stage_idx += 1
        stage = STAGES[stage_idx]
        if (opp.close_date - t.date()).days < 21 and rng.random() < 0.4:   # ordinary slippage near the close date
            opp.close_date = month_end(opp.close_date + timedelta(days=30))
        if stage_idx == 3 and negotiate:                  # proposal: price is negotiated (not on renewals)
            opp.amount = max(500.0, round(opp.amount * float(rng.lognormal(-0.05, 0.15)) / 500) * 500)
        record(t)
        next_stage = business_time(t.date() + timedelta(days=int(rng.gamma(2.0, dwell_days / 2.0)) + 1))


def new_opportunity(counter: list, account: Account, owner: Rep, kind: str, created: datetime, amount: float,
                    close: date) -> Opportunity:
    counter[0] += 1
    return Opportunity(f"006{counter[0]:012d}", account, owner, kind, created, amount, close)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "data" / "raw")
    args = parser.parse_args()

    reps = build_reps()
    rep_by_id = {r.id: r for r in reps}
    accounts = build_accounts(reps)
    accounts_by_owner: dict[str, list[Account]] = {}
    for a in accounts:
        accounts_by_owner.setdefault(a.owner_id, []).append(a)

    counter = [0]
    opportunities: list[Opportunity] = []
    contracts: list[Contract] = []

    def run(opp: Opportunity, start_stage: int, advance_mult: float, dwell: float,
            renews: Contract | None = None) -> None:
        outcome, closed = simulate(opp, start_stage, advance_mult, dwell, negotiate=renews is None)
        opportunities.append(opp)
        if outcome == "won":
            # a renewal contract starts the day after the one it renews ends, even if it was signed late
            start = renews.end + timedelta(days=1) if renews else closed
            contracts.append(Contract(f"800{len(contracts) + 1:012d}", opp, start, one_year_later(start),
                                      round(opp.amount, 2), renews))
            if opp.account.first_win is None:
                opp.account.first_win, opp.account.first_win_amount = closed, opp.amount

    # 1. New business: each rep creates opportunities week by week
    for rep in reps:
        enterprise = rep.segment == "Enterprise"
        weekly = (0.35 if enterprise else 0.9) * (1.5 if rep.region == "APAC" else 1.0)          # P3
        mult = 0.88 if rep.region == "APAC" else 1.0                                            # P3
        dwell = 26.0 if enterprise else 12.0                                                    # P5
        week = START
        while week <= CUTOFF:
            for _ in range(rng.poisson(weekly)):
                created_day = week + timedelta(days=int(rng.integers(0, 5)))
                if created_day > CUTOFF:
                    continue
                account = accounts_by_owner[rep.id][rng.integers(len(accounts_by_owner[rep.id]))]
                median = 110_000 if enterprise else 24_000                                     # P5
                amount = max(2_000.0, round(float(rng.lognormal(np.log(median), 0.5)) / 500) * 500)
                expected = 110 if enterprise else 55          # reps set optimistic close dates, so deals slip
                close = month_end(created_day + timedelta(days=int(expected * rng.uniform(0.7, 1.3))))
                opp = new_opportunity(counter, account, rep, "New Business", business_time(created_day), amount, close)
                run(opp, 0, mult, dwell)
            week += timedelta(days=7)

    # 2. Expansion: customers buy more, about once every three years on average
    for account in accounts:
        if account.first_win is None:
            continue
        owner = rep_by_id[account.owner_id]
        t = account.first_win
        while True:
            t = t + timedelta(days=int(rng.exponential(365 / 0.35)) + 30)
            if t > CUTOFF:
                break
            amount = max(1_000.0, round(account.first_win_amount * 0.35 * float(rng.lognormal(0, 0.4)) / 500) * 500)
            close = month_end(t + timedelta(days=60))
            opp = new_opportunity(counter, account, owner, "Expansion", business_time(t), amount, close)
            run(opp, 1, 1.15, 9.0 if owner.segment == "Mid-Market" else 18.0)

    # 3. Renewals: every contract comes up for renewal 90 days before it ends (renewed contracts too)
    i = 0
    while i < len(contracts):
        contract = contracts[i]
        i += 1
        created_day = contract.end - timedelta(days=89)
        if created_day > CUTOFF:
            continue
        source = contract.opportunity
        opp = new_opportunity(counter, source.account, source.owner, "Renewal", business_time(created_day),
                              round(contract.arr * 1.03, 2), month_end(contract.end))
        opp.renews_contract_id = contract.id
        run(opp, 2, 1.32, 15.0, renews=contract)      # renewals start at Solution and win about nine times in ten

    write_outputs(args.out_dir, reps, accounts, opportunities, contracts)


def write_outputs(out_dir: Path, reps: list[Rep], accounts: list[Account], opportunities: list[Opportunity],
                  contracts: list[Contract]) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    fmt = "%Y-%m-%d %H:%M:%S"

    def write(name: str, header: list[str], rows: list[list]) -> None:
        with open(out_dir / name, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(rows)
        print(f"  wrote {name:<26} {len(rows):>7,} rows")

    write("users.csv", ["Id", "Name", "Region", "Segment", "ForecastStyle"],
          [[r.id, r.name, r.region, r.segment, r.forecast_style] for r in reps])
    write("accounts.csv", ["Id", "Name", "Region", "Segment", "Industry", "OwnerId"],
          [[a.id, a.name, a.region, a.segment, a.industry, a.owner_id] for a in accounts])

    opportunities.sort(key=lambda o: o.id)
    opp_rows, hist_rows, n = [], [], 0
    for o in opportunities:
        last = o.versions[-1]
        opp_rows.append([o.id, f"{o.account.name} - {o.type}", o.account.id, o.owner.id, o.type, last["stage"],
                         f"{last['amount']:.2f}", last["close"].isoformat(), last["fc"], last["prob"],
                         o.created.strftime(fmt), str(last["stage"] in (WON, LOST)).lower(),
                         str(last["stage"] == WON).lower(), o.renews_contract_id])
        for v in o.versions:
            n += 1
            hist_rows.append([f"008{n:012d}", o.id, v["ts"].strftime(fmt), v["stage"], f"{v['amount']:.2f}",
                              v["close"].isoformat(), v["fc"], v["prob"]])
    write("opportunities.csv", ["Id", "Name", "AccountId", "OwnerId", "Type", "StageName", "Amount", "CloseDate",
                                "ForecastCategoryName", "Probability", "CreatedDate", "IsClosed", "IsWon", "RenewedContractId"],
          opp_rows)
    write("opportunity_history.csv", ["Id", "OpportunityId", "CreatedDate", "StageName", "Amount", "CloseDate",
                                      "ForecastCategory", "Probability"], hist_rows)

    write("contracts.csv", ["Id", "AccountId", "OpportunityId", "ContractType", "StartDate", "EndDate",
                            "AnnualRecurringRevenue", "RenewedContractId"],
          [[c.id, c.opportunity.account.id, c.opportunity.id, c.opportunity.type, c.start.isoformat(),
            c.end.isoformat(), f"{c.arr:.2f}", c.renews.id if c.renews else ""] for c in contracts])

    # Quotas: new-bookings quota (New Business + Expansion) per rep and quarter, set at ~115% of the segment's
    # average bookings per rep that year, so typical attainment sits a little under 90%.
    bookings: dict[tuple[str, int], list[float]] = {}
    for o in opportunities:
        last = o.versions[-1]
        if last["stage"] == WON and o.type != "Renewal":
            bookings.setdefault((o.owner.segment, last["close"].year), []).append(last["amount"])
    rows = []
    for r in reps:
        for year in range(START.year, CUTOFF.year + 1):
            reps_in_segment = sum(1 for x in reps if x.segment == r.segment)
            # the extract year is incomplete, so its quota is based on the prior full year
            basis_year = year if year < CUTOFF.year else year - 1
            total = sum(bookings.get((r.segment, basis_year), []))
            per_quarter = total / reps_in_segment / 4
            quota = max(5_000, round(1.15 * per_quarter / 5_000) * 5_000)
            for q in range(4):
                q_start = date(year, 3 * q + 1, 1)
                if q_start <= CUTOFF:
                    rows.append([r.id, q_start.isoformat(), quota])
    write("quotas.csv", ["OwnerId", "QuarterStartDate", "QuotaAmount"], rows)


if __name__ == "__main__":
    main()
