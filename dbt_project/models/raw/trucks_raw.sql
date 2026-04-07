{{
  config(
    materialized='incremental',
    incremental_strategy='append',
    schema='bronze'
  )
}}

/*
  trucks_raw.sql
  --------------
  Persistent landing zone for the trucks Kafka topic.
*/

select
    op,
    ts_ms,
    before,
    after,
    _partition_id,
    _partition_offset

from {{ source('kafka_source', 'trucks_raw') }}

{% if is_incremental() %}
  where _partition_offset > (
    select coalesce(max(_partition_offset), -1) 
    from {{ this }} 
    where _partition_id = {{ source('kafka_source', 'trucks_raw') }}._partition_id
  )
{% endif %}

