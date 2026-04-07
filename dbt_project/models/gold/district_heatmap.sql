{{
  config(
    materialized='incremental',
    unique_key=['trip_date', 'origin_district', 'destination_district'],
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

/*
  district_heatmap.sql  (gold)
  ----------------------------
  Aggregated delivery statistics per origin→destination district pair.
  Powers the geo-heatmap in the analytics dashboard.

  One row per (trip_date, pickup_address, delivery_address).
*/


with trips as (

    select 
        trip_date,
        pickup_address,
        delivery_address,
        total_distance_km,
        total_duration_min,
        deadhead_ratio
    from {{ ref('order_trips') }}
    where is_deleted = false
    and trip_date is not null
    {% if is_incremental() %}
    and trip_date >= current_date - interval '{{ var("lookback_days", 1) + 3 }}' day
    {% endif %}


)

select
    trip_date,
    pickup_address                              as origin_district,
    delivery_address                            as destination_district,

    -- Volume
    count(*)                                    as order_count,

    -- Distance
    round(avg(coalesce(total_distance_km, 0)), 2) as avg_distance_km,
    round(min(coalesce(total_distance_km, 0)), 2) as min_distance_km,
    round(max(coalesce(total_distance_km, 0)), 2) as max_distance_km,

    -- Duration
    round(avg(total_duration_min), 1)           as avg_duration_min,
    round(
        approx_percentile(total_duration_min, 0.5),
        1
    )                                           as median_duration_min,

    -- Efficiency
    -- Efficiency
    round(avg(coalesce(deadhead_ratio, 0)), 4)  as avg_deadhead_ratio,

    -- OTD for this corridor
    round(
        sum(case when total_duration_min <= {{ var('otd_threshold_min', 15) }} then 1 else 0 end)
        * 1.0 / nullif(count(*), 0),
        4
    )                                           as corridor_otd_rate

from trips
where
    total_duration_min is not null

group by 1, 2, 3
{% if is_incremental() %}
-- Filter out context rows so we only merge the requested refresh window
having trip_date >= current_date - interval '{{ var("lookback_days", 1) }}' day
{% endif %}
order by trip_date desc, order_count desc
