select rep_id, rep_name, region, segment, planted_forecast_style
from {{ ref('stg_crm__users') }}
