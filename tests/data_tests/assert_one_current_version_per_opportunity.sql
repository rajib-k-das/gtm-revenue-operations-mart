-- Every opportunity has exactly one current version, and versions never overlap or leave gaps:
-- each version ends exactly when the next one starts.
with checks as (
    select
        opportunity_id,
        count(*) filter (where is_current)                                         as current_versions,
        count(*) filter (where not is_current and valid_to <= valid_from)          as non_positive_windows
    from {{ ref('int_opportunity_versions') }}
    group by opportunity_id
)
select * from checks where current_versions <> 1 or non_positive_windows > 0
