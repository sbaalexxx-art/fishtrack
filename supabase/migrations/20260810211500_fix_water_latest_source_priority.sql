-- Water latest-source arbitration.
-- Contract:
--   1. Fresh observations always outrank stale observations.
--   2. Among fresh observations: AFDJ > DanubeHIS > DanubeFIS.
--   3. Timestamp/fetch ordering breaks ties inside the same priority.
-- Historical applied migrations remain untouched.

create or replace function public.get_water_station_latest_v1(
  p_station_id text default null
)
returns table (
  station_id text,
  station_name text,
  river_name text,
  latitude double precision,
  longitude double precision,
  display_order integer,
  level_cm numeric,
  observed_at timestamptz,
  observed_at_precision text,
  source_key text,
  source_name text,
  source_url text,
  quality_status text,
  confidence text,
  fetched_at timestamptz,
  freshness_minutes integer,
  is_stale boolean
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with candidates as (
    select
      observation.*,
      source_registry.source_key,
      source_registry.display_name as source_name,
      source_registry.freshness_target_minutes,
      case source_registry.source_key
        when 'AFDJ' then 1
        when 'DanubeHIS' then 2
        when 'DanubeFIS' then 3
        else 100
      end as source_priority,
      (
        observation.observed_at <
        now() - make_interval(
          mins => coalesce(source_registry.freshness_target_minutes, 2160)
        )
      ) as candidate_is_stale
    from public.water_operational_observations observation
    join public.water_data_sources source_registry
      on source_registry.id = observation.source_id
     and source_registry.country_code = observation.country_code
     and source_registry.is_active
    where observation.station_id is not null
      and observation.metric_code = 'water_level_cm'
      and observation.availability_status = 'available'
      and observation.quality_status in ('validated', 'corrected')
      and (
        p_station_id is null
        or observation.station_id = p_station_id
      )
  ),
  ranked as (
    select
      candidate.*,
      row_number() over (
        partition by candidate.station_id
        order by
          candidate.candidate_is_stale asc nulls last,
          candidate.source_priority asc,
          candidate.observed_at desc nulls last,
          candidate.fetched_at desc,
          candidate.created_at desc
      ) as row_rank
    from candidates candidate
  )
  select
    station.id,
    station.name,
    station.river,
    station.latitude,
    station.longitude,
    station.display_order,
    latest.value,
    latest.observed_at,
    latest.observed_at_precision,
    latest.source_key,
    latest.source_name,
    latest.source_url,
    latest.quality_status,
    latest.confidence,
    latest.fetched_at,
    floor(
      greatest(
        0,
        extract(epoch from (now() - latest.observed_at)) / 60.0
      )
    )::integer,
    latest.candidate_is_stale
  from ranked latest
  join public.stations station
    on station.id = latest.station_id
  where latest.row_rank = 1
  order by
    station.display_order nulls last,
    station.name;
$$;

comment on function public.get_water_station_latest_v1(text) is
  'Secure Water mobile contract returning the preferred fresh canonical water-level observation per station using AFDJ > DanubeHIS > DanubeFIS source priority.';

revoke all
  on function public.get_water_station_latest_v1(text)
  from public;

grant execute
  on function public.get_water_station_latest_v1(text)
  to anon, authenticated, service_role;