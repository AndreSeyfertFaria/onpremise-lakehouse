{{
  config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
  )
}}

/*
  order_trips.sql  (silver)
  -------------------------
  One row per completed order trip. Calculates:
  - Deadhead distance: truck position at dispatch → pickup address
  - Loaded distance:   pickup address → delivery address
  - Duration in minutes for each leg and total
  - Whether the trip was completed (has all required timestamps)

  Uses Trino's great_circle_distance(lat1, lon1, lat2, lon2) which returns
  the distance in kilometres.

  Strategy for coordinates:
  - "Dispatch position" = the truck's last known telemetry point BEFORE
     the order was dispatched (simulates where the truck actually was).
  - "Pickup position" = first telemetry point AFTER collected_at.
  - "Delivery position" = last telemetry point BEFORE delivered_at.
  This gives us real GPS coordinates instead of hardcoded district centroids.
  
   Incremental merge on order_id.
 
  The key efficiency decision: telemetry is bounded by the time window
  of the new orders batch. If the new orders were dispatched between
  T_min and T_max, we only read telemetry in [T_min, T_max + buffer].
  This avoids a full scan of the telemetry table on every run.
 
  Buffer of +2 hours on T_max covers late telemetry pings arriving
  after the delivery timestamp was written.
*/

with orders as (

    select * from {{ ref('stg_orders') }}
    where
        -- Only process fully completed trips
        dispatched_at is not null
        and collected_at  is not null
        and delivered_at  is not null
        and (status = 'delivered' or is_deleted = true)


    {% if is_incremental() %}
        -- Only orders delivered more recently than our latest row
        and delivered_at > (select max(delivered_at) from {{ this }})
    {% endif %}
),

telemetry as (

    select t.* from {{ ref('stg_telemetry') }} t
    {% if is_incremental() %}
    inner join (
        select
            min(dispatched_at) as window_start,
            max(delivered_at) + interval '2' hour as window_end
        from orders
    ) w
    on t.event_ts between w.window_start and w.window_end
    {% endif %}

),

-- Last known truck position just before dispatch (deadhead origin)
dispatch_position as (

    select
        truck_id,
        order_id,
        latitude   as dispatch_lat,
        longitude  as dispatch_lon
    from (
        select
            t.truck_id,
            o.order_id,
            t.latitude,
            t.longitude,
            row_number() over (
                partition by t.truck_id, o.order_id
                order by t.event_ts desc
            ) as rn
        from telemetry t
        inner join orders o on t.truck_id = o.truck_id
        where t.event_ts < o.dispatched_at
    )
    where rn = 1

),

-- First telemetry point after collection (loaded leg origin = pickup)
pickup_position as (

    select
        truck_id,
        order_id,
        latitude   as pickup_lat,
        longitude  as pickup_lon
    from (
        select
            t.truck_id,
            o.order_id,
            t.latitude,
            t.longitude,
            row_number() over (
                partition by t.truck_id, o.order_id
                order by t.event_ts asc
            ) as rn
        from telemetry t
        inner join orders o on t.truck_id = o.truck_id
        where t.event_ts >= o.collected_at
    )
    where rn = 1

),

-- Last telemetry point before delivery (loaded leg end = delivery)
delivery_position as (

    select
        truck_id,
        order_id,
        latitude   as delivery_lat,
        longitude  as delivery_lon
    from (
        select
            t.truck_id,
            o.order_id,
            t.latitude,
            t.longitude,
            row_number() over (
                partition by t.truck_id, o.order_id
                order by t.event_ts desc
            ) as rn
        from telemetry t
        inner join orders o on t.truck_id = o.truck_id
        where t.event_ts <= o.delivered_at
    )
    where rn = 1

)

, distances as (
    select
        o.order_id,
        o.truck_id,
        o.pickup_address,
        o.delivery_address,
        o.dispatched_at,
        o.collected_at,
        o.delivered_at,
        o.is_deleted,
        great_circle_distance(
            dp.dispatch_lat, dp.dispatch_lon,
            pp.pickup_lat,   pp.pickup_lon
        ) as raw_deadhead_distance,
        great_circle_distance(
            pp.pickup_lat,   pp.pickup_lon,
            dlv.delivery_lat, dlv.delivery_lon
        ) as raw_loaded_distance
    from orders o
    left join dispatch_position dp  on o.order_id = dp.order_id
    left join pickup_position   pp  on o.order_id = pp.order_id
    left join delivery_position dlv on o.order_id = dlv.order_id
)

select
    order_id,
    truck_id,
    pickup_address,
    delivery_address,
    dispatched_at,
    collected_at,
    delivered_at,

    -- Deadhead leg: dispatch position → pickup
    round(raw_deadhead_distance, 3)                 as deadhead_distance_km,

    -- Loaded leg: pickup → delivery
    round(raw_loaded_distance, 3)                   as loaded_distance_km,

    -- Total distance
    round(raw_deadhead_distance + raw_loaded_distance, 3) as total_distance_km,

    -- Duration in minutes
    round(
        date_diff('second', dispatched_at, collected_at) / 60.0,
        1
    )                                               as deadhead_duration_min,

    round(
        date_diff('second', collected_at, delivered_at) / 60.0,
        1
    )                                               as loaded_duration_min,

    round(
        date_diff('second', dispatched_at, delivered_at) / 60.0,
        1
    )                                               as total_duration_min,

    -- Deadhead ratio: what fraction of total trip was unloaded movement
    case
        when (raw_deadhead_distance + raw_loaded_distance) > 0
        then round(
            raw_deadhead_distance / (raw_deadhead_distance + raw_loaded_distance),
            4
        )
        else null
    end                                             as deadhead_ratio,

    -- Date partition column (useful for incremental models later)
    cast(dispatched_at as date)                     as trip_date,
    is_deleted

from distances
where round(date_diff('second', dispatched_at, delivered_at) / 60.0, 1) <= 120
