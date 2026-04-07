{{
  config(
    materialized='incremental',
    unique_key=['truck_id', 'activity_date'],
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

/*
  truck_activity.sql  (silver)
  ----------------------------
  Daily activity summary per truck. Aggregates order_trips to produce:
  - Total trips completed
  - Total distance driven (deadhead + loaded)
  - Deadhead vs loaded ratio
  - Avg trip duration
  - Time in each status (approximated from telemetry density)
  - Active hours (hours with at least one telemetry ping)

  This model is optimized for CDC ingestion using a merge incremental strategy.
  It re-processes data from the last known activity_date onwards to capture 
  late-arriving telemetry or order updates for the current day.
*/


with trips as (

    select * from {{ ref('order_trips') }}
    where is_deleted = false
    {% if is_incremental() %}
    and trip_date >= (select max(activity_date) from {{ this }})
    {% endif %}


),

-- Metadata from stg_trucks (Registry layer)
truck_registry as (

    select
        truck_id,
        model,
        capacity_kg,
        status as truck_status
    from {{ ref('stg_trucks') }}
    where is_deleted = false


),

-- Count telemetry pings per truck per hour to estimate active time
telemetry_hourly as (

    select
        truck_id,
        cast(event_ts as date)                          as activity_date,
        date_trunc('hour', event_ts)                    as activity_hour,
        avg(speed_kmh)                                  as avg_speed_kmh,
        count(*)                                        as ping_count
    from {{ ref('stg_telemetry') }}
    {% if is_incremental() %}
    where cast(event_ts as date) >= (select max(activity_date) from {{ this }})
    {% endif %}
    group by 1, 2, 3

),

active_hours_agg as (

    select
        truck_id,
        activity_date,
        count(distinct activity_hour)                   as active_hours,
        avg(avg_speed_kmh)                              as avg_speed_kmh,
        sum(ping_count)                                 as total_pings
    from telemetry_hourly
    group by 1, 2

),

daily_trips as (

    select
        truck_id,
        trip_date                                       as activity_date,
        count(*)                                        as trips_completed,
        sum(deadhead_distance_km)                       as total_deadhead_km,
        sum(loaded_distance_km)                         as total_loaded_km,
        sum(total_distance_km)                          as total_distance_km,
        sum(total_duration_min)                         as total_duration_min,
        avg(deadhead_ratio)                             as avg_deadhead_ratio,
        avg(total_duration_min)                         as avg_trip_duration_min,

        -- Simplistic "Primary District": most occurring pickup point
        -- In Trino, we can use array_agg + slice or max_by (if supported)
        -- max_by(pickup_address, count_per_address) would be ideal.
        -- Let's use a simpler approach: the one with the most trips.
        -- We'll use a sub-CTE for this to keep it clean.
        null as primary_district 

    from trips
    group by 1, 2

),

-- Resolve the district with the most pickups for the day
district_ranking as (
    select
        truck_id,
        trip_date,
        pickup_address,
        row_number() over (
            partition by truck_id, trip_date 
            order by count(*) desc
        ) as rn
    from trips
    group by 1, 2, 3
)

select
    dt.truck_id,
    dt.activity_date,
    tr.model,
    tr.capacity_kg,
    dr.pickup_address                                   as primary_district,
    
    dt.trips_completed,
    round(dt.total_distance_km, 2)                      as total_distance_km,
    round(dt.total_deadhead_km, 2)                      as total_deadhead_km,
    round(dt.total_loaded_km, 2)                        as total_loaded_km,
    
    round(dt.total_duration_min, 1)                     as total_duration_min,
    round(dt.avg_deadhead_ratio, 4)                     as avg_deadhead_ratio,

    ah.active_hours,
    ah.total_pings,
    round(ah.avg_speed_kmh, 1)                          as avg_speed_kmh

from daily_trips dt
left join truck_registry tr     on dt.truck_id = tr.truck_id
left join active_hours_agg ah   on dt.truck_id = ah.truck_id 
                               and dt.activity_date = ah.activity_date
left join district_ranking dr   on dt.truck_id = dr.truck_id 
                               and dt.activity_date = dr.trip_date
                               and dr.rn = 1
