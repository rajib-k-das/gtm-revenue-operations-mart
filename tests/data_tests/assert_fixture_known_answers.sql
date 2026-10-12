-- Known answers for the hand-built test company (tests/fixtures/README.md). Skipped when the fixture isn't loaded.

with fixture_loaded as (

    select count(*) > 0 as is_loaded from {{ ref('dim_rep') }} where rep_id = '005FIXTURE0001'

),

q1 as (

    select * from {{ ref('fct_pipeline_waterfall') }} where quarter_start = date '2024-01-01'

),

waterfall_failures as (

    select 'Q1 2024 waterfall' as failed_check
    from (select 1) as one
    left join q1 on true
    where q1.opening_pipeline is distinct from 38000
       or q1.created is distinct from 6000
       or q1.pulled_in is distinct from 30000
       or q1.won is distinct from 12000
       or q1.lost is distinct from 30000
       or q1.moved_out is distinct from 20000
       or q1.amount_change is distinct from 2000
       or q1.closing_pipeline is distinct from 14000
       or q1.won_deals is distinct from 1
       or q1.moved_out_deals is distinct from 1

),

-- At the end of 2023 all five deals except the one created in January were open.
snapshot_failures as (

    select 'snapshot 2023-12-31' as failed_check
    from (
        select count(*) as deals, sum(amount) as amount
        from {{ ref('fct_pipeline_snapshots') }}
        where as_of_date = date '2023-12-31'
    ) as s
    where s.deals <> 4 or s.amount <> 68000

),

-- Point in time: on 2024-02-19 deal 2 was still due in February; a day later it had been pushed to April.
point_in_time_failures as (

    select 'deal 2 push' as failed_check
    from {{ ref('int_opportunity_versions') }}
    where opportunity_id = '006FIXTURE0002' and version_number = 2
      and not (is_pushed_to_later_quarter and previous_close_date = date '2024-02-29')

),

-- Layer 2: one new-logo contract of $12,000 in Q1 2024; the rep booked $12,000 against a $50,000 quota and
-- started the quarter with $38,000 of new-business pipeline due in it (76% coverage).
layer2_failures as (

    select 'ARR bridge Q1 2024' as failed_check
    from {{ ref('fct_arr_bridge') }}
    where quarter_start = date '2024-01-01'
      and (opening_arr <> 0 or new_logo <> 12000 or closing_arr <> 12000)

    union all

    select 'rep quarter Q1 2024'
    from {{ ref('fct_rep_quarter') }}
    where quarter_start = date '2024-01-01'
      and (bookings <> 12000 or abs(attainment - 0.24) > 1e-9 or opening_pipeline <> 38000
           or abs(opening_coverage - 0.76) > 1e-9)

    union all

    -- on Sunday 31 March 2024 the quarter's $12,000 win was in "won to date"
    select 'forecast snapshot 2024-03-31'
    from {{ ref('fct_forecast_snapshots') }}
    where as_of_date = date '2024-03-31' and won_to_date <> 12000

    union all

    -- deal 4 entered Qualification and was lost from it
    select 'stage outcome deal 4'
    from {{ ref('fct_opportunity_stages') }}
    where opportunity_id = '006FIXTURE0004' and stage_name = '2-Qualification' and stage_outcome <> 'Lost'

),

expected_rows as (

    select 'missing Layer 2 rows' as failed_check
    where (select count(*) from {{ ref('fct_arr_bridge') }} where quarter_start = date '2024-01-01') <> 1
       or (select count(*) from {{ ref('fct_rep_quarter') }} where quarter_start = date '2024-01-01') <> 1
       or (select count(*) from {{ ref('fct_forecast_snapshots') }} where as_of_date = date '2024-03-31') <> 1

)

select f.*
from (
    select * from waterfall_failures
    union all select * from layer2_failures
    union all select * from expected_rows
    union all select * from snapshot_failures
    union all select * from point_in_time_failures
) as f
cross join fixture_loaded
where fixture_loaded.is_loaded
