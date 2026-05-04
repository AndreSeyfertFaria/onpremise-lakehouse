{{
  config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

with raw_data as (
    select
        cast(json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.id') as integer) as order_id,
        json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.truck_id')        as truck_id,
        json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.status')          as status,
        json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.pickup_address')  as pickup_address,
        json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.delivery_address') as delivery_address,
        cast(from_unixtime(cast(json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.dispatched_at') as bigint) / 1000.0) as timestamp) as dispatched_at,
        cast(from_unixtime(cast(json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.collected_at') as bigint) / 1000.0) as timestamp) as collected_at,
        cast(from_unixtime(cast(json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.delivered_at') as bigint) / 1000.0) as timestamp) as delivered_at,
        ts_ms,
        op,
        case when op = 'd' then true else false end as is_deleted,
        row_number() over (
            partition by json_extract_scalar(json_parse(case when op = 'd' then before else after end), '$.id') 
            order by _partition_offset desc
        ) as rn
    from {{ ref('orders_raw') }}
    
    {% if is_incremental() %}
    where ts_ms > (select coalesce(max(ts_ms), -1) from {{ this }})
    {% endif %}
)


select
    order_id,
    truck_id,
    status,
    pickup_address,
    delivery_address,
    dispatched_at,
    collected_at,
    delivered_at,
    ts_ms,
    is_deleted
from raw_data
where rn = 1
