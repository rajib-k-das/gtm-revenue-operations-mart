-- One row per change to an opportunity, holding its full state after the change.
select
    trim(Id)                                        as history_id,
    trim(OpportunityId)                             as opportunity_id,
    cast(CreatedDate as timestamp)                  as changed_at,
    trim(StageName)                                 as stage_name,
    cast(Amount as decimal(14, 2))                  as amount,
    cast(CloseDate as date)                         as close_date,
    trim(ForecastCategory)                          as forecast_category,
    cast(Probability as integer)                    as probability
from {{ source('crm', 'opportunity_history') }}
