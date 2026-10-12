-- What each rep's forecast for the current quarter looked like at the end of every week (decision 008),
-- and, for completed quarters, what was actually booked. New business and expansion only (renewals are
-- forecast separately in most sales teams, and the quota covers new bookings).
--
--   won to date   deals won so far with a close date in the quarter
--   commit        won to date + open deals in forecast category Commit due in the quarter
--   best case     commit + open Best Case deals due in the quarter
--   error         commit / actual - 1 (positive = over-forecast)

with versions as (

    select * from {{ ref('int_opportunity_versions') }}
    where opportunity_type <> 'Renewal'

),

weeks as (

    select
        as_of_date,
        date_trunc('quarter', as_of_date)::date                                         as quarter_start,
        (date_trunc('quarter', as_of_date) + interval 3 month - interval 1 day)::date  as quarter_end,
        date_diff('week', date_trunc('quarter', as_of_date)::date, as_of_date) + 1    as week_of_quarter,
        data_cutoff
    from {{ ref('int_snapshot_dates') }}
    where is_week_end

),

reps as (

    select rep_id from {{ ref('dim_rep') }}

),

state as (

    select weeks.as_of_date, versions.*
    from weeks
    inner join versions
        on  versions.valid_from <= (weeks.as_of_date + interval 1 day)
        and (versions.valid_to is null or (weeks.as_of_date + interval 1 day) < versions.valid_to)
        and versions.close_date between weeks.quarter_start and weeks.quarter_end

),

by_rep as (

    select
        as_of_date,
        owner_id,
        coalesce(sum(amount) filter (where is_won), 0)                                     as won_to_date,
        coalesce(sum(amount) filter (where is_open and forecast_category = 'Commit'), 0)  as open_commit,
        coalesce(sum(amount) filter (where is_open and forecast_category = 'Best Case'), 0) as open_best_case,
        coalesce(sum(amount) filter (where is_open), 0)                                    as open_pipeline
    from state
    group by as_of_date, owner_id

),

actuals as (

    select owner_id, date_trunc('quarter', close_date)::date as quarter_start, sum(amount) as actual_bookings
    from versions
    where is_current and is_won
    group by all

)

select
    weeks.as_of_date,
    weeks.quarter_start,
    weeks.week_of_quarter,
    reps.rep_id                                                                    as owner_id,
    coalesce(b.won_to_date, 0)                                                     as won_to_date,
    coalesce(b.won_to_date, 0) + coalesce(b.open_commit, 0)                        as commit_forecast,
    coalesce(b.won_to_date, 0) + coalesce(b.open_commit, 0) + coalesce(b.open_best_case, 0)
                                                                                   as best_case_forecast,
    coalesce(b.open_pipeline, 0)                                                   as open_pipeline,
    weeks.quarter_end <= weeks.data_cutoff                                         as is_quarter_complete,
    case when weeks.quarter_end <= weeks.data_cutoff then coalesce(a.actual_bookings, 0) end
                                                                                   as actual_bookings,
    case when weeks.quarter_end <= weeks.data_cutoff and a.actual_bookings > 0
         then (coalesce(b.won_to_date, 0) + coalesce(b.open_commit, 0)) / a.actual_bookings - 1 end
                                                                                   as commit_error
from weeks
cross join reps
left join by_rep as b on b.as_of_date = weeks.as_of_date and b.owner_id = reps.rep_id
left join actuals as a on a.owner_id = reps.rep_id and a.quarter_start = weeks.quarter_start
