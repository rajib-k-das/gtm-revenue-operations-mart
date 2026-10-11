-- The history and the current-state table come from different CRM objects. The latest version rebuilt from the
-- history must match the opportunity's current state exactly; otherwise point-in-time answers can't be trusted.
select o.opportunity_id, o.stage_name, v.stage_name as history_stage, o.amount, v.amount as history_amount,
       o.close_date, v.close_date as history_close_date
from {{ ref('stg_crm__opportunities') }} as o
left join {{ ref('int_opportunity_versions') }} as v
    on v.opportunity_id = o.opportunity_id and v.is_current
where v.opportunity_id is null
   or o.stage_name is distinct from v.stage_name
   or o.amount is distinct from v.amount
   or o.close_date is distinct from v.close_date
   or o.forecast_category is distinct from v.forecast_category
