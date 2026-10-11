"""
Print the headline findings from the marts, and check them against the generator's planted behaviours.

Run after `dbt build`:
    python scripts/summarize_findings.py
"""

from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[1] / "data" / "warehouse.duckdb"

CHECKS = {
    "1. Pipeline waterfall by quarter, all reps ($K)": """
        select quarter_start as quarter,
               round(sum(opening_pipeline) / 1e3) as opening, round(sum(created) / 1e3) as created,
               round(sum(pulled_in) / 1e3) as pulled_in, round(sum(won) / 1e3) as won, round(sum(lost) / 1e3) as lost,
               round(sum(moved_out) / 1e3) as moved_out, round(sum(amount_change) / 1e3) as amount_chg,
               round(sum(closing_pipeline) / 1e3) as closing,
               round(100.0 * sum(moved_out) / nullif(sum(opening_pipeline), 0), 1) as pct_opening_moved_out
        from marts.fct_pipeline_waterfall group by 1 order by 1
    """,
    "2. P1 - Close dates pushed to a later quarter, by week of the quarter in which the push happened": """
        select date_diff('week', date_trunc('quarter', valid_from), valid_from) + 1 as week_of_quarter,
               count(*) as pushes, round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_pushes
        from intermediate.int_opportunity_versions
        where is_pushed_to_later_quarter and is_open
        group by 1 order by 1
    """,
    "3. P2 - Deals won (new business and expansion), by week of the quarter": """
        select date_diff('week', date_trunc('quarter', close_date), close_date) + 1 as week_of_quarter,
               count(*) as deals_won, round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_wins
        from intermediate.int_opportunity_versions
        where is_current and is_won and opportunity_type <> 'Renewal'
        group by 1 order by 1
    """,
    "4. P3 - New-business pipeline created vs won, by region (closed deals)": """
        select r.region,
               count(*) as deals, round(sum(v.amount) / 1e6, 1) as pipeline_created_m,
               round(sum(v.amount) filter (where v.is_won) / 1e6, 1) as won_m,
               round(100.0 * sum(v.amount) filter (where v.is_won) / sum(v.amount), 1) as win_rate_by_value_pct,
               round(count(*) / count(distinct r.rep_id) / 12.0, 1) as deals_created_per_rep_per_quarter
        from intermediate.int_opportunity_versions as v
        inner join marts.dim_rep as r on r.rep_id = v.owner_id
        where v.is_current and not v.is_open and v.opportunity_type = 'New Business'
        group by 1 order by 1
    """,
}


def main() -> None:
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        for title, sql in CHECKS.items():
            print(f"\n== {title} ==")
            con.sql(sql).show(max_rows=60, max_width=250)


if __name__ == "__main__":
    main()
