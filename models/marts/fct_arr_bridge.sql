-- Quarterly ARR bridge by region (decision 009):
--   opening ARR + new logo + expansion + renewal uplift - churn - expired awaiting renewal = closing ARR
--
-- ARR on a day = annual value of contracts active that day (start_date <= day <= end_date).
--   new logo          contract starts at an account with no active contract the day before
--   expansion         any other non-renewal contract (expansion deals, or new business at an existing customer)
--   renewal uplift    renewal contract ARR minus the ARR of the contract it renews (the two swap on the same day)
--   churn             a contract ends without a renewal, and its renewal opportunity was lost (or never opened)
--   expired awaiting  a contract ends without a renewal yet, but its renewal opportunity is still open
--     renewal         (a late renewal is backdated, so this can later turn into uplift)

with contracts as (

    select c.*, a.region
    from {{ ref('stg_crm__contracts') }} as c
    inner join {{ ref('stg_crm__accounts') }} as a using (account_id)

),

cutoff as (

    select max(data_cutoff) as data_cutoff from {{ ref('int_snapshot_dates') }}

),

quarters as (

    select
        quarter_start::date                                         as quarter_start,
        (quarter_start + interval 3 month - interval 1 day)::date   as quarter_end
    from (
        select unnest(generate_series(
            date_trunc('quarter', (select min(start_date) from contracts))::date,
            (select data_cutoff from cutoff), interval 3 month)) as quarter_start
    )
    where (quarter_start + interval 3 month - interval 1 day)::date <= (select data_cutoff from cutoff)

),

regions as (

    select distinct region from contracts

),

renewal_status as (

    -- for each contract, its renewal opportunity's status (if any) and whether a renewal contract exists
    select
        c.contract_id,
        max(o.stage_name)                                                  as renewal_stage,
        bool_or(r.contract_id is not null)                                 as is_renewed
    from contracts as c
    left join {{ ref('stg_crm__opportunities') }} as o on o.renewed_contract_id = c.contract_id
    left join contracts as r on r.renewed_contract_id = c.contract_id
    group by c.contract_id

),

starts as (

    select
        c.region,
        date_trunc('quarter', c.start_date)::date                          as quarter_start,
        case
            when c.renewed_contract_id is not null then 'renewal_uplift'
            when exists (
                select 1 from contracts as prior
                where prior.account_id = c.account_id
                  and prior.start_date <= c.start_date - interval 1 day
                  and prior.end_date >= c.start_date - interval 1 day
            ) then 'expansion'
            else 'new_logo'
        end                                                                as bucket,
        c.arr - coalesce(parent.arr, 0)                                    as amount
    from contracts as c
    left join contracts as parent on parent.contract_id = c.renewed_contract_id

),

ends as (

    select
        c.region,
        date_trunc('quarter', c.end_date + interval 1 day)::date           as quarter_start,
        case when s.renewal_stage is not null and s.renewal_stage <> 'Closed Lost'
             then 'expired_awaiting_renewal' else 'churn' end              as bucket,
        c.arr                                                              as amount
    from contracts as c
    inner join renewal_status as s using (contract_id)
    where not s.is_renewed

),

movements as (

    select * from starts
    union all
    select * from ends

),

arr_on as (

    -- ARR active on the day before each quarter and on its last day
    select q.quarter_start, r.region,
           coalesce(sum(c.arr) filter (where c.start_date <= q.quarter_start - interval 1 day
                                         and c.end_date >= q.quarter_start - interval 1 day), 0) as opening_arr,
           coalesce(sum(c.arr) filter (where c.start_date <= q.quarter_end
                                         and c.end_date >= q.quarter_end), 0)                     as closing_arr
    from quarters as q
    cross join regions as r
    left join contracts as c on c.region = r.region
    group by q.quarter_start, r.region

)

select
    a.quarter_start,
    a.region,
    a.opening_arr,
    coalesce(sum(m.amount) filter (where m.bucket = 'new_logo'), 0)                     as new_logo,
    coalesce(sum(m.amount) filter (where m.bucket = 'expansion'), 0)                    as expansion,
    coalesce(sum(m.amount) filter (where m.bucket = 'renewal_uplift'), 0)               as renewal_uplift,
    coalesce(sum(m.amount) filter (where m.bucket = 'churn'), 0)                        as churn,
    coalesce(sum(m.amount) filter (where m.bucket = 'expired_awaiting_renewal'), 0)     as expired_awaiting_renewal,
    a.closing_arr
from arr_on as a
left join movements as m on m.quarter_start = a.quarter_start and m.region = a.region
group by a.quarter_start, a.region, a.opening_arr, a.closing_arr
