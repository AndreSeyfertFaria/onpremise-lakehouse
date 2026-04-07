{{
  config(
    materialized='incremental',
    incremental_strategy='append',
    schema='bronze'
  )
}}

/*
  orders_raw.sql
  --------------
  Persistent landing zone for the orders Kafka topic.
  Captures raw JSON payloads into Iceberg Parquet for long-term retention.
*/

select
    op,
    ts_ms,
    before,
    after,
    _partition_id,
    _partition_offset

from {{ source('kafka_source', 'orders_raw') }}

{% if is_incremental() %}
  -- High-fidelity offset tracking: only ingest records newer than our last offset per partition
  where _partition_offset > (
    select coalesce(max(_partition_offset), -1) 
    from {{ this }} 
    where _partition_id = {{ source('kafka_source', 'orders_raw') }}._partition_id
  )
{% endif %}

