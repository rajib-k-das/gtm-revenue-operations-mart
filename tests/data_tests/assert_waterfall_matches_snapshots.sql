-- Independent check: the waterfall's opening and closing pipeline must equal the pipeline snapshot model's totals
-- (pipeline due in the quarter, as of the day before the quarter starts and as of its last day).
-- The two models are built separately, so agreement means both rebuild history correctly.

with snapshot_totals as (

    select
        w.quarter_start,
        w.owner_id,
        w.opening_pipeline,
        w.closing_pipeline,
        coalesce(sum(s.amount) filter (
            where s.as_of_date = w.quarter_start - interval 1 day and s.close_quarter = w.quarter_start), 0)
                                                                                    as snapshot_opening,
        coalesce(sum(s.amount) filter (
            where s.as_of_date = w.quarter_start + interval 3 month - interval 1 day
              and s.close_quarter = w.quarter_start), 0)                            as snapshot_closing
    from {{ ref('fct_pipeline_waterfall') }} as w
    left join {{ ref('fct_pipeline_snapshots') }} as s
        on  s.owner_id = w.owner_id
        and s.as_of_date in (w.quarter_start - interval 1 day, w.quarter_start + interval 3 month - interval 1 day)
    group by all

)

select *
from snapshot_totals
where abs(opening_pipeline - snapshot_opening) > 0.005
   or abs(closing_pipeline - snapshot_closing) > 0.005
