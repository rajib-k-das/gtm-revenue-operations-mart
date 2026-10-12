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
    "5. ARR bridge by quarter, all regions ($K)": """
        select quarter_start as quarter, round(sum(opening_arr) / 1e3) as opening, round(sum(new_logo) / 1e3) as new_logo,
               round(sum(expansion) / 1e3) as expansion, round(sum(renewal_uplift) / 1e3) as uplift,
               round(sum(churn) / 1e3) as churn, round(sum(expired_awaiting_renewal) / 1e3) as awaiting_renewal,
               round(sum(closing_arr) / 1e3) as closing
        from marts.fct_arr_bridge group by 1 order by 1
    """,
    "6. P4 - Commit forecast error by rep forecast style (median, complete quarters; style is the answer key)": """
        select r.planted_forecast_style as planted_style, count(distinct r.rep_id) as reps,
               round(100 * median(f.commit_error) filter (where f.week_of_quarter = 4), 1)  as week4_error_pct,
               round(100 * median(f.commit_error) filter (where f.week_of_quarter = 6), 1)  as week6_error_pct,
               round(100 * median(f.commit_error) filter (where f.week_of_quarter = 8), 1)  as week8_error_pct,
               round(100 * avg(f.commit_error) filter (where f.week_of_quarter = 10), 1)    as week10_mean_error_pct
        from marts.fct_forecast_snapshots as f
        inner join marts.dim_rep as r on r.rep_id = f.owner_id
        where f.commit_error is not null
        group by 1 order by week6_error_pct desc
    """,
    "7. Quota attainment and opening pipeline coverage by region (complete quarters from Q2 2023)": """
        select r.region, round(100 * sum(q.bookings) / sum(q.quota_amount), 1) as attainment_pct,
               round(sum(q.opening_pipeline) / sum(q.quota_amount), 2) as opening_coverage,
               round(100.0 * count(*) filter (where q.attainment >= 1) / count(*), 1) as pct_rep_quarters_at_quota
        from marts.fct_rep_quarter as q
        inner join marts.dim_rep as r on r.rep_id = q.owner_id
        where q.is_quarter_complete and q.quarter_start >= date '2023-04-01'
        group by 1 order by 1
    """,
    "8. New-business stage conversion and median days in stage, by segment": """
        select segment, stage_name, count(*) as entered,
               round(100.0 * count(*) filter (where stage_outcome = 'Advanced')
                     / count(*) filter (where stage_outcome <> 'Still in stage'), 1) as conversion_pct,
               median(days_in_stage) as median_days
        from marts.fct_opportunity_stages
        where opportunity_type = 'New Business'
        group by 1, 2 order by 1, 2
    """,
    "9. P5 - Won deals: median size and days to close, by segment and type": """
        select segment, opportunity_type, count(*) as won, round(median(final_amount)) as median_amount,
               round(median(days_to_close)) as median_days_to_close,
               round(avg(quarters_pushed), 2) as avg_quarters_pushed
        from marts.dim_opportunity where outcome = 'Won'
        group by 1, 2 order by 2, 1
    """,
}


def main() -> None:
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        for title, sql in CHECKS.items():
            print(f"\n== {title} ==")
            con.sql(sql).show(max_rows=60, max_width=250)


if __name__ == "__main__":
    main()
