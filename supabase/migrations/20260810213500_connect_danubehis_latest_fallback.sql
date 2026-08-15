-- Connect DanubeHIS latest staging as a mobile latest-only fallback.
--
-- IMPORTANT:
-- DanubeHIS latest staging currently exposes relative measurement age,
-- not an exact observation timestamp. Therefore these rows are NOT promoted
-- into the append-only operational history.
--
-- Latest-source contract:
--   1. Fresh observations outrank stale observations.
--   2. Among equally fresh candidates:
--        AFDJ      = primary
--        DanubeHIS = fallback
--        DanubeFIS = secondary fallback
--   3. DanubeHIS relative observed_at is derived only for freshness/latest
--      arbitration and remains explicitly marked as "relative".

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
  with operational_candidates as (
    select
      observation.station_id,
      observation.value::numeric as level_cm,
      observation.observed_at,
      observation.observed_at_precision,
      source_registry.source_key,
      source_registry.display_name as source_name,
      observation.source_url,
      observation.quality_status,
      observation.confidence,
      observation.fetched_at,
      observation.created_at,
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
  danubehis_prepared as (
    select
      mapping.station_id,
      staging.value::numeric as level_cm,
      case
        when staging.exact_observed_at is not null
          then staging.exact_observed_at
        when staging.observed_at_precision = 'relative'
          and staging.source_age_seconds_approx is not null
          then staging.fetched_at - make_interval(
            secs => staging.source_age_seconds_approx::double precision
          )
        else null
      end as observed_at,
      case
        when staging.exact_observed_at is not null then 'exact'
        else 'relative'
      end as observed_at_precision,
      source_registry.source_key,
      source_registry.display_name as source_name,
      staging.source_url,
      'validated'::text as quality_status,
      case
        when staging.exact_observed_at is not null then 'high'
        else 'medium'
      end::text as confidence,
      staging.fetched_at,
      staging.updated_at as created_at,
      source_registry.freshness_target_minutes,
      2 as source_priority
    from public.water_measurements_latest_staging staging
    join public.water_data_sources source_registry
      on source_registry.source_key = staging.source
     and source_registry.country_code = staging.country_code
     and source_registry.is_active
    join public.water_station_source_mappings mapping
      on mapping.source = staging.source
     and mapping.country_code = staging.country_code
     and mapping.source_station_id = staging.source_station_id
     and mapping.mapping_status = 'verified'
    where staging.source = 'DanubeHIS'
      and staging.country_code = 'RO'
      and staging.metric_code = 'h'
      and staging.availability_status = 'available'
      and lower(btrim(staging.unit)) = 'cm'
      and staging.value is not null
      and (
        staging.exact_observed_at is not null
        or (
          staging.observed_at_precision = 'relative'
          and staging.source_age_seconds_approx is not null
        )
      )
      and (
        p_station_id is null
        or mapping.station_id = p_station_id
      )
  ),
  danubehis_candidates as (
    select
      prepared.*,
      (
        prepared.observed_at <
        now() - make_interval(
          mins => coalesce(prepared.freshness_target_minutes, 2160)
        )
      ) as candidate_is_stale
    from danubehis_prepared prepared
    where prepared.observed_at is not null
  ),
  candidates as (
    select * from operational_candidates
    union all
    select * from danubehis_candidates
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
    latest.level_cm,
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
  'Secure Water mobile latest contract. Freshness-aware source arbitration uses AFDJ primary, DanubeHIS latest-staging fallback, then DanubeFIS. DanubeHIS relative timestamps are never promoted into canonical history.';

revoke all
  on function public.get_water_station_latest_v1(text)
  from public;

grant execute
  on function public.get_water_station_latest_v1(text)
  to anon, authenticated, service_role;