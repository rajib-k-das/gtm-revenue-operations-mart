-- One row per opportunity and open stage it entered: when it entered, when it left, and how it left
-- (advanced to a later stage or won, lost, or still there). Basis for stage conversion and velocity.

with versions as (

    select * from {{ ref('int_opportunity_versions') }}

),

stage_entries as (

    select opportunity_id, stage_name, valid_from as entered_at
    from versions
    where version_number = 1 or stage_changed

),

sequenced as (

    select
        *,
        lead(stage_name) over (partition by opportunity_id order by entered_at) as next_stage_name,
        lead(entered_at) over (partition by opportunity_id order by entered_at) as left_at
    from stage_entries

)

select
    opportunity_id,
    stage_name,
    cast(left(stage_name, 1) as integer)                                         as stage_number,
    entered_at,
    left_at,
    next_stage_name,
    case
        when next_stage_name is null        then 'Still in stage'
        when next_stage_name = 'Closed Lost' then 'Lost'
        else 'Advanced'
    end                                                                          as stage_outcome,
    date_diff('day', entered_at, left_at)                                        as days_in_stage
from sequenced
where stage_name not in ('Closed Won', 'Closed Lost')
