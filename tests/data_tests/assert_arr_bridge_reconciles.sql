-- Each ARR bridge row must add up: its movements are computed from contract starts and ends, while opening and
-- closing ARR are computed independently from the contracts active on each day.
select *
from {{ ref('fct_arr_bridge') }}
where abs(opening_arr + new_logo + expansion + renewal_uplift - churn - expired_awaiting_renewal - closing_arr) > 0.005
