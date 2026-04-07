{{
  config(
    materialized='incremental',
    unique_key='truck_id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

with raw_data as (
    select
        json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.id')          as truck_id,
        json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.model')       as model,
        cast(json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.capacity_kg') as integer) as capacity_kg,
        lower(trim(json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.status'))) as status,
        ts_ms,
        op,
        case when op = 'd' then true else false end as is_deleted,
        row_number() over (
            partition by json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.id') 
            order by _partition_offset desc
        ) as rn
    from {{ ref('trucks_raw') }}

    {% if is_incremental() %}
    where ts_ms > (select max(ts_ms) from {{ this }})
    {% endif %}
)


select
    truck_id,
    model,
    capacity_kg,
    status,
    -- Validate status is within the known domain
    case
        when status in ('available', 'in_transit', 'maintenance') then true
        else false
    end                             as is_valid_status,
    ts_ms,
    is_deleted
from raw_data
where rn = 1

