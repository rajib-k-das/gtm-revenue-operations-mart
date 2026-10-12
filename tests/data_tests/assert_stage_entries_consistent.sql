-- Every opportunity enters at least one open stage, and an opportunity can only be won if its last stage advanced.
select d.opportunity_id, d.outcome
from {{ ref('dim_opportunity') }} as d
left join {{ ref('fct_opportunity_stages') }} as s using (opportunity_id)
group by d.opportunity_id, d.outcome
having count(s.opportunity_id) = 0
    or (d.outcome = 'Won' and count(*) filter (where s.stage_outcome = 'Advanced') = 0)
    or (d.outcome = 'Lost' and count(*) filter (where s.stage_outcome = 'Lost') <> 1)
