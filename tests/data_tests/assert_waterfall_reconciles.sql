-- Every waterfall row must add up to the cent: opening + created + pulled in - won - lost - moved out + amount change = closing.
select *
from {{ ref('fct_pipeline_waterfall') }}
where abs(opening_pipeline + created + pulled_in - won - lost - moved_out + amount_change - closing_pipeline) > 0.005
