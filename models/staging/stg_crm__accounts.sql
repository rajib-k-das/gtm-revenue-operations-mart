select
    trim(Id)                    as account_id,
    trim(Name)                  as account_name,
    trim(Region)                as region,
    trim(Segment)               as segment,
    trim(Industry)              as industry,
    trim(OwnerId)               as owner_id
from {{ source('crm', 'accounts') }}
