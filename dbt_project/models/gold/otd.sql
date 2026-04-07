{{
  config(
    materialized='incremental',
    unique_key=['trip_date', 'district'],
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

/*
  otd.sql  (gold)
  ---------------
  On-Time Delivery (OTD) — the primary business KPI.

  Definition: an order is "on time" if total_duration_min <= the threshold.
  Threshold is set at 15 minutes (the median value is 11 minutes), which is reasonable for the simulation of Curitiba intra-city
  logistics. You can make this configurable via a dbt variable:
    dbt run --vars '{"otd_threshold_min": 60}'

  Aggregation: one row per (trip_date, delivery_address district).
  This lets the dashboard show OTD by day AND by destination zone.

  Incremental merge on (trip_date, district). On each run, recomputes only
  the last N days (lookback_days var, default 1) to handle late-arriving
  corrections without reprocessing historical data.
 
  Usage: dbt run --vars '{"otd_threshold_min": 15, "lookback_days": 1}'
*/


with trips as (

    select * from {{ ref('order_trips') }}
    where is_deleted = false
    {% if is_incremental() %}
    /* 
       For a 7-day rolling window, we need 6 preceding days of context
       plus the actual lookback period to refresh.
    */
    and trip_date >= current_date - interval '{{ var("lookback_days", 1) + 6 }}' day
    {% endif %}


),

-- Define OTD threshold (default 15 min, overridable via dbt var)
with_flags as (

    select
        trip_date,
        order_id,
        pickup_address,
        delivery_address,
        total_duration_min,
        deadhead_duration_min,
        loaded_duration_min,
        total_distance_km,
        deadhead_ratio,

        case
            when total_duration_min <= {{ var('otd_threshold_min', 15) }}
            then true
            else false
        end                                     as is_on_time,

        case
            when total_duration_min <= {{ var('otd_threshold_min', 15) }} * 0.75
            then 'fast'
            when total_duration_min <= {{ var('otd_threshold_min', 15) }}
            then 'on_time'
            when total_duration_min <= {{ var('otd_threshold_min', 15) }} * 1.25
            then 'slightly_late'
            else 'late'
        end                                     as delivery_tier

    from trips
    where total_duration_min is not null

),

daily_district as (

    select
        trip_date,
        delivery_address                        as district,
        count(*)                                as total_orders,
        sum(case when is_on_time then 1 else 0 end)
                                                as on_time_orders,
        count(*) - sum(case when is_on_time then 1 else 0 end)
                                                as late_orders,

        -- OTD rate
        round(
            sum(case when is_on_time then 1 else 0 end) * 1.0 / count(*),
            4
        )                                       as otd_rate,

        -- Delivery tier breakdown
        sum(case when delivery_tier = 'fast'          then 1 else 0 end) as fast_count,
        sum(case when delivery_tier = 'on_time'       then 1 else 0 end) as on_time_count,
        sum(case when delivery_tier = 'slightly_late' then 1 else 0 end) as slightly_late_count,
        sum(case when delivery_tier = 'late'          then 1 else 0 end) as late_count,

        -- Duration stats
        round(avg(total_duration_min), 1)       as avg_duration_min,
        round(min(total_duration_min), 1)       as min_duration_min,
        round(max(total_duration_min), 1)       as max_duration_min,

        -- Approx p90 (Trino supports approx_percentile)
        round(
            approx_percentile(total_duration_min, 0.9),
            1
        )                                       as p90_duration_min

    from with_flags
    group by 1, 2

),

final as (

    select
        trip_date,
        district,
        total_orders,
        on_time_orders,
        late_orders,
        otd_rate,
        fast_count,
        on_time_count,
        slightly_late_count,
        late_count,
        avg_duration_min,
        min_duration_min,
        max_duration_min,
        p90_duration_min,

        -- Rolling 7-day OTD (useful for trend charts in the dashboard)
        -- In incremental mode, this calculation is correct because the 'trips' CTE 
        -- fetches the necessary 6 preceding days for context.
        round(
            sum(on_time_orders) over (
                partition by district
                order by trip_date
                rows between 6 preceding and current row
            ) * 1.0 /
            nullif(sum(total_orders) over (
                partition by district
                order by trip_date
                rows between 6 preceding and current row
            ), 0),
            4
        )                                           as otd_rate_7d

    from daily_district

)

select * 
from final
{% if is_incremental() %}
-- Filter out context rows so we only merge the requested refresh window
where trip_date >= current_date - interval '{{ var("lookback_days", 1) }}' day
{% endif %}
order by trip_date desc, district
