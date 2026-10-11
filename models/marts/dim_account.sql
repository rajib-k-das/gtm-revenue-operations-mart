select account_id, account_name, region, segment, industry, owner_id
from {{ ref('stg_crm__accounts') }}
