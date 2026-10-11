-- The dates the pipeline is reconstructed for: every week-ending Sunday and every quarter end,
-- from the quarter end before the first opportunity up to the extract date (the last change in the data).
-- A snapshot "as of" a date means the state at the end of that day.

with bounds as (

    select
        (date_trunc('quarter', min(changed_at)) - interval 1 day)::date   as first_date,
        max(changed_at)::date                                             as data_cutoff
    from {{ ref('stg_crm__opportunity_history') }}

),

days as (

    select unnest(generate_series(first_date, data_cutoff, interval 1 day))::date as as_of_date, data_cutoff
    from bounds

)

select
    as_of_date,
    dayofweek(as_of_date) = 0                                             as is_week_end,
    as_of_date = (date_trunc('quarter', as_of_date) + interval 3 month - interval 1 day)::date
                                                                          as is_quarter_end,
    data_cutoff
from days
where dayofweek(as_of_date) = 0
   or as_of_date = (date_trunc('quarter', as_of_date) + interval 3 month - interval 1 day)::date
   or as_of_date = data_cutoff
