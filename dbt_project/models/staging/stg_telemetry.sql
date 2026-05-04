{{
  config(
    materialized='incremental',
    incremental_strategy='append',
    on_schema_change='sync_all_columns'
  )
}}

with source_data as (
    select
        json_extract_scalar(json_parse(after), '$.truck_id') as truck_id,
        cast(json_extract_scalar(json_parse(after), '$.latitude') as double) as latitude,
        cast(json_extract_scalar(json_parse(after), '$.longitude') as double) as longitude,
        cast(json_extract_scalar(json_parse(after), '$.speed_kmh') as double) as speed_kmh,
        json_extract_scalar(json_parse(after), '$.fuel_level') as fuel_level,
        cast(from_unixtime(cast(json_extract_scalar(json_parse(after), '$.timestamp') as bigint) / 1000.0) as timestamp) as event_ts,
        ts_ms,
        op,
        row_number() over (
            partition by json_extract_scalar(json_parse(after), '$.truck_id'), json_extract_scalar(json_parse(after), '$.timestamp') 
            order by _partition_offset desc
        ) as rn
    from {{ ref('truck_telemetry_raw') }}
    where op in ('c', 'r')
    
    {% if is_incremental() %}
    and ts_ms > (select coalesce(max(ts_ms), -1) from {{ this }})
    {% endif %}
),


deduped as (
    select *
    from source_data
    where rn = 1
    -- Physically valid coordinates (Curitiba bounding box)
    and latitude between -26.0 and -25.2
    and longitude between -49.5 and -49.1
    and speed_kmh >= 0
    and latitude is not null
    and longitude is not null
)

select
    truck_id,
    latitude,
    longitude,
    speed_kmh,
    fuel_level,
    event_ts,
    ts_ms
from deduped
