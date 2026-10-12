-- One row per opportunity: who, what, when, how it ended, how long it took, and how often its close date moved.

with versions as (

    select * from {{ ref('int_opportunity_versions') }}

),

summary as (

    select
        opportunity_id,
        min(valid_from)                                                   as created_at,
        max(valid_from) filter (where not is_open)                        as closed_at,
        arg_min(amount, version_number)                                   as initial_amount,
        arg_max(amount, version_number)                                   as final_amount,
        arg_min(close_date, version_number)                               as initial_close_date,
        arg_max(close_date, version_number)                               as final_close_date,
        arg_max(stage_name, version_number)                               as final_stage_name,
        count(*) filter (where is_pushed_to_later_quarter and is_open)    as quarters_pushed,
        count(*) filter (where close_date_changed and is_open)            as close_date_changes,
        max(case when is_open then cast(left(stage_name, 1) as integer) end) as furthest_open_stage
    from versions
    group by opportunity_id

)

select
    o.opportunity_id,
    o.opportunity_type,
    o.owner_id,
    o.account_id,
    r.region,
    r.segment,
    summary.created_at,
    summary.closed_at,
    case summary.final_stage_name when 'Closed Won' then 'Won' when 'Closed Lost' then 'Lost' else 'Open' end
                                                                          as outcome,
    date_diff('day', summary.created_at, summary.closed_at)               as days_to_close,
    summary.initial_amount,
    summary.final_amount,
    summary.initial_close_date,
    summary.final_close_date,
    summary.quarters_pushed,
    summary.close_date_changes,
    summary.furthest_open_stage,
    o.renewed_contract_id
from {{ ref('stg_crm__opportunities') }} as o
inner join summary using (opportunity_id)
inner join {{ ref('dim_rep') }} as r on r.rep_id = o.owner_id
