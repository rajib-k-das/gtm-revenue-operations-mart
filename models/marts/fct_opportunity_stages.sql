-- Stage conversion and velocity: one row per opportunity and stage entered, with region, segment and type,
-- so conversion (advanced / (advanced + lost)) and days in stage can be cut any way.
select
    e.*,
    d.opportunity_type,
    d.region,
    d.segment,
    d.owner_id,
    date_trunc('quarter', e.entered_at)::date as entered_quarter
from {{ ref('int_opportunity_stage_entries') }} as e
inner join {{ ref('dim_opportunity') }} as d using (opportunity_id)
