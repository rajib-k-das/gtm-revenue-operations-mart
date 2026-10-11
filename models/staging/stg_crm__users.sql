select
    trim(Id)                    as rep_id,
    trim(Name)                  as rep_name,
    trim(Region)                as region,
    trim(Segment)               as segment,
    -- The generator's hidden forecast style (decision 003). Kept for validating the analysis, never used by it.
    trim(ForecastStyle)         as planted_forecast_style
from {{ source('crm', 'users') }}
