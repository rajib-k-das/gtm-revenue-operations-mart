-- SCD Type 2 history of every opportunity (decision 002).
-- Each change in the CRM's history becomes a version, valid from its change time until the next change.
-- A version is valid at instant t when valid_from <= t < valid_to (valid_to null = current version).
-- With this, the pipeline can be rebuilt exactly as it stood at any moment.

with history as (

    select * from {{ ref('stg_crm__opportunity_history') }}

),

opportunities as (

    select opportunity_id, account_id, owner_id, opportunity_type, created_at
    from {{ ref('stg_crm__opportunities') }}

),

versioned as (

    select
        history.*,
        row_number() over opportunity_timeline                         as version_number,
        lead(changed_at) over opportunity_timeline                     as valid_to,
        lag(stage_name) over opportunity_timeline                      as previous_stage_name,
        lag(amount) over opportunity_timeline                          as previous_amount,
        lag(close_date) over opportunity_timeline                      as previous_close_date
    from history
    window opportunity_timeline as (partition by opportunity_id order by changed_at)

)

select
    versioned.opportunity_id,
    versioned.version_number,
    versioned.changed_at                                               as valid_from,
    versioned.valid_to,
    versioned.valid_to is null                                         as is_current,
    opportunities.account_id,
    opportunities.owner_id,
    opportunities.opportunity_type,
    opportunities.created_at,
    versioned.stage_name,
    versioned.amount,
    versioned.close_date,
    date_trunc('quarter', versioned.close_date)::date                  as close_quarter,
    versioned.forecast_category,
    versioned.probability,
    versioned.stage_name not in ('Closed Won', 'Closed Lost')          as is_open,
    versioned.stage_name = 'Closed Won'                                as is_won,

    -- What changed in this version (all false for the first version)
    coalesce(versioned.stage_name <> versioned.previous_stage_name, false)   as stage_changed,
    coalesce(versioned.amount <> versioned.previous_amount, false)           as amount_changed,
    coalesce(versioned.close_date <> versioned.previous_close_date, false)   as close_date_changed,
    coalesce(date_trunc('quarter', versioned.close_date)
             > date_trunc('quarter', versioned.previous_close_date), false)  as is_pushed_to_later_quarter,
    coalesce(date_trunc('quarter', versioned.close_date)
             < date_trunc('quarter', versioned.previous_close_date), false)  as is_pulled_to_earlier_quarter,
    versioned.previous_close_date

from versioned
inner join opportunities using (opportunity_id)
