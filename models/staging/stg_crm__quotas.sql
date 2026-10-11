select
    trim(OwnerId)                                   as rep_id,
    cast(QuarterStartDate as date)                  as quarter_start,
    cast(QuotaAmount as decimal(14, 2))             as quota_amount
from {{ source('crm', 'quotas') }}
