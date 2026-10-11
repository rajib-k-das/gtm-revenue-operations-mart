-- Quarterly pipeline waterfall per rep (decision 004): how the pipeline due in a quarter moved during that quarter.
--
--   pipeline(Q) at time t = open opportunities whose close date falls in Q, at their amount at time t
--   opening = pipeline(Q) at the start of Q        closing = pipeline(Q) at the end of Q
--
--   closing = opening + created + pulled_in - won - lost - moved_out + amount_change
--
-- Buckets, per opportunity (comparing its state at the start and the end of the quarter):
--   created / pulled_in  entered pipeline(Q) during Q: created in Q, or already existed with a close date outside Q.
--                        Valued at its amount at the end of Q (or when it closed).
--   won / lost           closed during Q out of pipeline(Q), at the amount it closed at. Won deals count in the quarter
--                        of their booking date; lost deals in the quarter they were due in just before they were lost
--                        (the CRM overwrites a lost deal's close date with the loss date).
--   moved_out            in pipeline(Q) at the start, still open at the end but now due outside Q, at its opening amount.
--   amount_change        everything else: price changes on deals that stayed, and the gap between a deal's opening
--                        amount and the amount it was won at.
-- Deals that entered and left pipeline(Q) within the quarter without closing (e.g. pulled in, then pushed out)
-- net to zero and are not shown. Only complete quarters (ended on or before the extract date) are included.

with versions as (

    select * from {{ ref('int_opportunity_versions') }}

),

cutoff as (

    select max(data_cutoff) as data_cutoff from {{ ref('int_snapshot_dates') }}

),

quarters as (

    select
        quarter_start::date                                             as quarter_start,
        (quarter_start + interval 3 month - interval 1 day)::date       as quarter_end,
        quarter_start::timestamp                                        as t_start,
        (quarter_start + interval 3 month)::timestamp                   as t_end
    from (
        select unnest(generate_series(
            date_trunc('quarter', (select min(valid_from) from versions))::date,
            (select data_cutoff from cutoff),
            interval 3 month)) as quarter_start
    )
    where (quarter_start + interval 3 month - interval 1 day)::date <= (select data_cutoff from cutoff)

),

-- each opportunity's state at the start and at the end of each quarter
state_at_end as (

    select quarters.*, versions.*
    from quarters
    inner join versions
        on  versions.valid_from <= quarters.t_end
        and (versions.valid_to is null or quarters.t_end < versions.valid_to)

),

state_at_start as (

    select quarters.quarter_start, versions.opportunity_id, versions.is_open, versions.close_date, versions.amount
    from quarters
    inner join versions
        on  versions.valid_from <= quarters.t_start
        and (versions.valid_to is null or quarters.t_start < versions.valid_to)

),

flagged as (

    select
        e.quarter_start,
        e.opportunity_id,
        e.owner_id,
        coalesce(s.is_open and s.close_date between e.quarter_start and e.quarter_end, false)   as in_at_start,
        e.is_open and e.close_date between e.quarter_start and e.quarter_end                    as in_at_end,
        -- Closed during Q out of pipeline(Q). A won deal's close date is its booking date. A lost deal's close date
        -- is overwritten with the day it was lost, so it counts against the quarter it was due in just before.
        not e.is_open and e.valid_from >= e.t_start
            and (case when e.is_won then e.close_date else e.previous_close_date end)
                between e.quarter_start and e.quarter_end                                       as closed_in_quarter,
        e.created_at >= e.t_start                                                               as created_in_quarter,
        e.is_won,
        coalesce(s.amount, 0)                                                                   as start_amount,
        e.amount                                                                                as end_amount
    from state_at_end as e
    left join state_at_start as s
        on s.quarter_start = e.quarter_start and s.opportunity_id = e.opportunity_id

),

valued as (

    select
        *,
        case when in_at_start then start_amount else 0 end                                     as opening_value,
        case when in_at_end then end_amount else 0 end                                         as closing_value,
        case when not in_at_start and (in_at_end or closed_in_quarter) then end_amount else 0 end
                                                                                                as inflow_value,
        case
            when not in_at_end and closed_in_quarter then end_amount
            when not in_at_end and in_at_start then start_amount
            else 0
        end                                                                                     as outflow_value
    from flagged
    where in_at_start or in_at_end or closed_in_quarter

)

select
    quarter_start,
    owner_id,
    coalesce(sum(opening_value), 0)                                                              as opening_pipeline,
    coalesce(sum(inflow_value) filter (where created_in_quarter), 0)                             as created,
    coalesce(sum(inflow_value) filter (where not created_in_quarter), 0)                         as pulled_in,
    coalesce(sum(outflow_value) filter (where closed_in_quarter and is_won), 0)                  as won,
    coalesce(sum(outflow_value) filter (where closed_in_quarter and not is_won), 0)              as lost,
    coalesce(sum(outflow_value) filter (where not closed_in_quarter), 0)                         as moved_out,
    coalesce(sum(closing_value - opening_value - inflow_value + outflow_value), 0)               as amount_change,
    coalesce(sum(closing_value), 0)                                                              as closing_pipeline,
    count(*) filter (where in_at_start)                                                          as opening_deals,
    count(*) filter (where closed_in_quarter and is_won)                                         as won_deals,
    count(*) filter (where closed_in_quarter and not is_won)                                     as lost_deals,
    count(*) filter (where not in_at_end and not closed_in_quarter)                              as moved_out_deals,
    count(*) filter (where in_at_end)                                                            as closing_deals
from valued
group by quarter_start, owner_id
