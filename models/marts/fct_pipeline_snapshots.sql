-- Open pipeline exactly as it stood at the end of each snapshot date (decision 002).
-- Grain: one row per snapshot date and open opportunity.

with versions as (

    select * from {{ ref('int_opportunity_versions') }}

),

dates as (

    select as_of_date, is_week_end, is_quarter_end from {{ ref('int_snapshot_dates') }}

)

select
    dates.as_of_date,
    dates.is_week_end,
    dates.is_quarter_end,
    versions.opportunity_id,
    versions.owner_id,
    versions.account_id,
    versions.opportunity_type,
    versions.stage_name,
    versions.forecast_category,
    versions.amount,
    versions.close_date,
    versions.close_quarter,
    versions.close_date < dates.as_of_date                                  as is_past_due
from dates
inner join versions
    on  versions.valid_from <= (dates.as_of_date + interval 1 day)
    and (versions.valid_to is null or (dates.as_of_date + interval 1 day) < versions.valid_to)
where versions.is_open
