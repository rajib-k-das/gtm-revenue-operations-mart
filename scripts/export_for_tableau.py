"""
Export the five small CSV files behind the Tableau Public dashboard (docs/dashboard_guide.md).

Each file is shaped for one view, so the dashboard needs no joins and few calculated fields. All data is synthetic.

Run after `dbt build`:
    python scripts/export_for_tableau.py
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "warehouse.duckdb"
EXPORT_DIR = ROOT / "exports"

QUARTER_LABEL = "strftime(quarter_start, '%Y') || ' Q' || quarter(quarter_start)"

EXPORTS = {
    # View 1. One row per quarter, region, segment and waterfall step. Bar Start and Bar Size are running totals,
    # so they stay correct when several regions or segments are summed together (a Gantt bar per step).
    "pipeline_waterfall.csv": f"""
        with by_group as (
            select w.quarter_start, r.region, r.segment,
                   sum(w.opening_pipeline) as opening, sum(w.created) as created, sum(w.pulled_in) as pulled_in,
                   sum(w.won) as won, sum(w.lost) as lost, sum(w.moved_out) as moved_out,
                   sum(w.amount_change) as amount_change, sum(w.closing_pipeline) as closing
            from marts.fct_pipeline_waterfall as w
            inner join marts.dim_rep as r on r.rep_id = w.owner_id
            group by all
        ),
        steps as (
            select quarter_start, region, segment, step_order, step, step_type, amount, bar_start
            from by_group,
            lateral (values
                (1, 'Opening pipeline', 'Total',     opening,        0),
                (2, 'Created',          'Increase',  created,        opening),
                (3, 'Pulled in',        'Increase',  pulled_in,      opening + created),
                (4, 'Won',              'Decrease', -won,            opening + created + pulled_in),
                (5, 'Lost',             'Decrease', -lost,           opening + created + pulled_in - won),
                (6, 'Moved out',        'Decrease', -moved_out,      opening + created + pulled_in - won - lost),
                (7, 'Amount change',    'Change',    amount_change,  opening + created + pulled_in - won - lost - moved_out),
                (8, 'Closing pipeline', 'Total',     closing,        0)
            ) as v(step_order, step, step_type, amount, bar_start)
        )
        select {QUARTER_LABEL} as quarter, quarter_start, region, segment, step_order, step, step_type,
               amount, bar_start, amount as bar_size
        from steps
        order by quarter_start, region, segment, step_order
    """,
    # View 2. One row per rep, complete quarter and week: commit forecast against what was finally booked.
    # Forecast Style is the generator's answer key (planted behaviour P4), shown so the recovery can be judged.
    "forecast_accuracy.csv": f"""
        select {QUARTER_LABEL} as quarter, f.week_of_quarter, r.rep_name, r.region, r.segment,
               upper(left(r.planted_forecast_style, 1)) || substr(r.planted_forecast_style, 2) as forecast_style,
               f.won_to_date, f.commit_forecast, f.best_case_forecast, f.actual_bookings, f.commit_error
        from marts.fct_forecast_snapshots as f
        inner join marts.dim_rep as r on r.rep_id = f.owner_id
        where f.is_quarter_complete and f.commit_error is not null and f.week_of_quarter <= 13
        order by f.quarter_start, r.rep_name, f.week_of_quarter
    """,
    # View 3. One row per rep and complete quarter (from Q2 2023, the first with opening pipeline).
    "rep_quarters.csv": f"""
        select {QUARTER_LABEL} as quarter, q.quarter_start, r.rep_name, r.region, r.segment,
               q.quota_amount, q.bookings, q.opening_pipeline, q.attainment, q.opening_coverage
        from marts.fct_rep_quarter as q
        inner join marts.dim_rep as r on r.rep_id = q.owner_id
        where q.is_quarter_complete and q.quarter_start >= date '2023-04-01'
        order by q.quarter_start, r.rep_name
    """,
    # View 4. Week of the quarter in which deals are won (P2) and close dates are pushed out (P1).
    "deal_timing.csv": """
        with wins as (
            select 'Deals won' as event,
                   least(date_diff('week', date_trunc('quarter', close_date), close_date) + 1, 13) as week_of_quarter
            from intermediate.int_opportunity_versions
            where is_current and is_won and opportunity_type <> 'Renewal'
        ),
        pushes as (
            select 'Close dates pushed to a later quarter' as event,
                   least(date_diff('week', date_trunc('quarter', valid_from), valid_from) + 1, 13) as week_of_quarter
            from intermediate.int_opportunity_versions
            where is_pushed_to_later_quarter and is_open
        ),
        events as (select * from wins union all select * from pushes),
        weeks as (select unnest(range(1, 14)) as week_of_quarter),
        events_list as (select distinct event from events)
        select e.event, w.week_of_quarter, count(ev.event) as events,
               count(ev.event) / sum(count(ev.event)) over (partition by e.event) as share_of_events
        from events_list as e
        cross join weeks as w
        left join events as ev on ev.event = e.event and ev.week_of_quarter = w.week_of_quarter
        group by e.event, w.week_of_quarter
        order by 1, 2
    """,
    # View 5. One row per quarter, region and ARR movement; churn is negative.
    "arr_bridge.csv": f"""
        select {QUARTER_LABEL} as quarter, quarter_start, region, component_order, component, amount,
               opening_arr, closing_arr
        from marts.fct_arr_bridge,
        lateral (values
            (1, 'New logo',       new_logo),
            (2, 'Expansion',      expansion),
            (3, 'Renewal uplift', renewal_uplift),
            (4, 'Churn',         -churn)
        ) as v(component_order, component, amount)
        order by quarter_start, region, component_order
    """,
}


def main() -> None:
    EXPORT_DIR.mkdir(exist_ok=True)
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        for name, sql in EXPORTS.items():
            path = EXPORT_DIR / name
            con.sql(sql).write_csv(str(path))
            rows = con.sql(f"select count(*) from read_csv_auto('{path}')").fetchone()[0]
            print(f"  wrote exports/{name:<24} {rows:>6,} rows")


if __name__ == "__main__":
    main()
