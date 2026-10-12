-- Validation harness (decision 003): the marts must recover each behaviour the generator planted.
-- Thresholds sit well inside the planted effects but far from "no effect", so a modelling error that
-- blurs a signal fails here. Skipped for the hand-built test company, which is too small to show patterns.

with is_generated as (

    select count(*) >= 20 as yes from {{ ref('dim_rep') }}

),

-- P1: close-date pushes into a later quarter happen mostly in the last three weeks of the quarter.
p1 as (

    select 'P1 end-of-quarter scrub' as failed_check
    from (
        select avg(case when date_diff('week', date_trunc('quarter', valid_from), valid_from) + 1 >= 11
                        then 1.0 else 0.0 end) as late_share
        from {{ ref('int_opportunity_versions') }}
        where is_pushed_to_later_quarter and is_open
    )
    where late_share <= 0.5

),

-- P2: the final week of the quarter holds well over its even share (7/91) of new-bookings wins.
p2 as (

    select 'P2 hockey stick' as failed_check
    from (
        select avg(case when date_diff('day', close_date,
                                       (date_trunc('quarter', close_date) + interval 3 month - interval 1 day)::date) <= 6
                        then 1.0 else 0.0 end) as last_week_share
        from {{ ref('dim_opportunity') }} as d
        inner join {{ ref('int_opportunity_versions') }} as v on v.opportunity_id = d.opportunity_id and v.is_current
        where d.outcome = 'Won' and d.opportunity_type <> 'Renewal'
    )
    where last_week_share <= 1.75 * 7 / 91

),

-- P3: APAC creates more new-business pipeline per rep, but wins a much smaller share of it.
p3_by_region as (

    select
        region = 'APAC'                                                            as is_apac,
        count(*) * 1.0 / count(distinct owner_id)                                  as deals_per_rep,
        sum(final_amount) filter (where outcome = 'Won') / sum(final_amount)       as win_rate_by_value
    from {{ ref('dim_opportunity') }}
    where opportunity_type = 'New Business' and outcome <> 'Open'
    group by 1

),

p3 as (

    select 'P3 inflated APAC pipeline' as failed_check
    from p3_by_region as apac
    inner join p3_by_region as rest on apac.is_apac and not rest.is_apac
    where apac.deals_per_rep <= 1.3 * rest.deals_per_rep
       or apac.win_rate_by_value >= 0.75 * rest.win_rate_by_value

),

-- P4: at week 6, optimistic reps' commit forecasts sit above accurate reps', which sit above conservative reps'.
p4_by_style as (

    select r.planted_forecast_style as style, median(f.commit_error) as week6_error
    from {{ ref('fct_forecast_snapshots') }} as f
    inner join {{ ref('dim_rep') }} as r on r.rep_id = f.owner_id
    where f.week_of_quarter = 6 and f.commit_error is not null
    group by 1

),

p4 as (

    select 'P4 forecast bias' as failed_check
    from (
        select
            max(week6_error) filter (where style = 'optimistic')   as optimistic,
            max(week6_error) filter (where style = 'accurate')     as accurate,
            max(week6_error) filter (where style = 'conservative') as conservative
        from p4_by_style
    )
    where not coalesce(optimistic > accurate and accurate > conservative, false)   -- a missing group fails too

),

-- P5: Enterprise new-business deals are much larger and take much longer to win.
p5_by_segment as (

    select segment, median(final_amount) as median_amount, median(days_to_close) as median_days
    from {{ ref('dim_opportunity') }}
    where opportunity_type = 'New Business' and outcome = 'Won'
    group by 1

),

p5 as (

    select 'P5 enterprise size and cycle' as failed_check
    from p5_by_segment as e
    inner join p5_by_segment as m on e.segment = 'Enterprise' and m.segment = 'Mid-Market'
    where e.median_amount <= 3 * m.median_amount or e.median_days <= 1.5 * m.median_days

)

select f.*
from (
    select * from p1 union all select * from p2 union all select * from p3
    union all select * from p4 union all select * from p5
) as f
cross join is_generated
where is_generated.yes
