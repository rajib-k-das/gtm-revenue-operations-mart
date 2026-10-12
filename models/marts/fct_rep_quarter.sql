-- One row per rep and quarter: quota, new bookings (new business + expansion), attainment, and the pipeline
-- coverage the rep started the quarter with (open new-business and expansion pipeline due in the quarter ÷ quota).

with quotas as (

    select * from {{ ref('stg_crm__quotas') }}

),

bookings as (

    select owner_id, date_trunc('quarter', close_date)::date as quarter_start,
           sum(amount) as bookings, count(*) as deals_won
    from {{ ref('int_opportunity_versions') }}
    where is_current and is_won and opportunity_type <> 'Renewal'
    group by all

),

opening_pipeline as (

    select owner_id, close_quarter as quarter_start, sum(amount) as opening_pipeline, count(*) as opening_deals
    from {{ ref('fct_pipeline_snapshots') }}
    where opportunity_type <> 'Renewal'
      and as_of_date = close_quarter - interval 1 day
    group by all

),

cutoff as (

    select max(data_cutoff) as data_cutoff from {{ ref('int_snapshot_dates') }}

)

select
    q.quarter_start,
    q.rep_id                                                                     as owner_id,
    q.quota_amount,
    coalesce(b.bookings, 0)                                                      as bookings,
    coalesce(b.deals_won, 0)                                                     as deals_won,
    coalesce(b.bookings, 0) / q.quota_amount                                     as attainment,
    coalesce(p.opening_pipeline, 0)                                              as opening_pipeline,
    coalesce(p.opening_deals, 0)                                                 as opening_deals,
    coalesce(p.opening_pipeline, 0) / q.quota_amount                             as opening_coverage,
    (q.quarter_start + interval 3 month - interval 1 day)::date <= cutoff.data_cutoff
                                                                                 as is_quarter_complete
from quotas as q
cross join cutoff
left join bookings as b on b.owner_id = q.rep_id and b.quarter_start = q.quarter_start
left join opening_pipeline as p on p.owner_id = q.rep_id and p.quarter_start = q.quarter_start
