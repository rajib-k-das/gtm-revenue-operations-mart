select
    trim(Id)                                        as opportunity_id,
    trim(Name)                                      as opportunity_name,
    trim(AccountId)                                 as account_id,
    trim(OwnerId)                                   as owner_id,
    trim(Type)                                      as opportunity_type,
    trim(StageName)                                 as stage_name,
    cast(Amount as decimal(14, 2))                  as amount,
    cast(CloseDate as date)                         as close_date,
    trim(ForecastCategoryName)                      as forecast_category,
    cast(Probability as integer)                    as probability,
    cast(CreatedDate as timestamp)                  as created_at,
    cast(IsClosed as boolean)                       as is_closed,
    cast(IsWon as boolean)                          as is_won
from {{ source('crm', 'opportunities') }}
