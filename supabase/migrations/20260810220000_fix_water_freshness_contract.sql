-- Separate hydrological measurement time from user-facing data freshness.
-- AFDJ currently publishes a date-only observation whose normalized midnight
-- must remain the measurement timestamp, never the freshness timestamp.

alter table public.water_observations_staging
  add column if not exists observed_at_precision text not null default 'date',
  add column if not exists source_changed_at timestamptz;

alter table public.water_observations_staging
  drop constraint if exists water_observations_staging_precision_check;

alter table public.water_observations_staging
  add constraint water_observations_staging_precision_check
  check (observed_at_precision in ('exact', 'date', 'unknown'));

alter table public.water_operational_observations
  add column if not exists source_changed_at timestamptz;

create or replace function public.promote_afdj_water_level_observations()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  inserted_rows integer := 0;
begin
  if not exists (
    select 1
    from public.water_data_sources
    where source_key = 'AFDJ'
      and country_code = 'RO'
      and is_active
  ) then
    raise exception
      'AFDJ promotion failed: active source registry entry is missing.';
  end if;

  if exists (
    select 1
    from public.water_observations_staging staging
    left join public.water_station_source_mappings mapping
      on mapping.source = staging.source
     and mapping.country_code = staging.country_code
     and mapping.source_station_id = staging.station_key
     and mapping.mapping_status = 'verified'
    where staging.source = 'AFDJ'
      and staging.country_code = 'RO'
      and mapping.station_id is null
  ) then
    raise exception
      'AFDJ promotion failed: one or more staging stations are not verified.';
  end if;

  insert into public.water_operational_observations (
    source_id,
    country_code,
    source_entity_id,
    station_id,
    metric_code,
    metric_name,
    value,
    unit,
    availability_status,
    observed_at,
    observed_at_precision,
    source_changed_at,
    quality_status,
    confidence,
    source_record_id,
    source_record_fingerprint,
    source_url,
    ingestion_run_id,
    fetched_at,
    raw_payload
  )
  select
    source_registry.id,
    staging.country_code,
    staging.station_key,
    mapping.station_id,
    'water_level_cm',
    'Water level',
    staging.water_level_cm,
    'cm',
    'available',
    staging.observed_at,
    staging.observed_at_precision,
    coalesce(
      staging.source_changed_at,
      case
        when coalesce(staging.raw_payload ->> 'source_changed_at', '') ~
          '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
          then (staging.raw_payload ->> 'source_changed_at')::timestamptz
        else null
      end
    ),
    'validated',
    case
      when staging.observed_at_precision = 'exact' then 'high'
      else 'medium'
    end,
    coalesce(
      staging.source_record_uuid,
      staging.source_record_id::text,
      staging.id::text
    ),
    encode(
      digest(
        concat_ws(
          '|',
          staging.source,
          staging.country_code,
          staging.station_key,
          'water_level_cm',
          extract(epoch from staging.observed_at)::text,
          staging.water_level_cm::text,
          coalesce(
            staging.source_record_uuid,
            staging.source_record_id::text,
            ''
          )
        ),
        'sha256'
      ),
      'hex'
    ),
    staging.source_url,
    concat(
      'afdj-staging-',
      to_char(staging.ingested_at at time zone 'UTC', 'YYYYMMDDHH24MISS')
    ),
    staging.fetched_at,
    coalesce(staging.raw_payload, '{}'::jsonb)
      || jsonb_build_object(
        'promoted_from', 'water_observations_staging',
        'staging_id', staging.id,
        'observed_at_precision', staging.observed_at_precision,
        'source_changed_at', staging.source_changed_at
      )
  from public.water_observations_staging staging
  join public.water_data_sources source_registry
    on source_registry.source_key = staging.source
   and source_registry.country_code = staging.country_code
   and source_registry.is_active
  join public.water_station_source_mappings mapping
    on mapping.source = staging.source
   and mapping.country_code = staging.country_code
   and mapping.source_station_id = staging.station_key
   and mapping.mapping_status = 'verified'
  where staging.source = 'AFDJ'
    and staging.country_code = 'RO'
  on conflict (
    source_id,
    source_entity_id,
    metric_code,
    source_record_fingerprint
  ) do nothing;

  get diagnostics inserted_rows = row_count;
  return inserted_rows;
end;
$$;

revoke all
  on function public.promote_afdj_water_level_observations()
  from public, anon, authenticated;

grant execute
  on function public.promote_afdj_water_level_observations()
  to service_role;

drop function if exists public.get_water_station_latest_v1(text);

create function public.get_water_station_latest_v1(
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
  source_changed_at timestamptz,
  freshness_at timestamptz,
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
  with operational_effective as (
    select
      observation.station_id,
      observation.value::numeric as level_cm,
      observation.observed_at,
      case
        when source_registry.source_key = 'AFDJ'
          and observation.observed_at_precision = 'exact'
          and observation.observed_at = (
            date_trunc(
              'day',
              observation.observed_at at time zone 'UTC'
            ) at time zone 'UTC'
          )
          then 'date'
        else observation.observed_at_precision
      end as observed_at_precision,
      case
        when observation.source_changed_at is not null
          then observation.source_changed_at
        when coalesce(observation.raw_payload ->> 'source_changed_at', '') ~
          '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
          then (observation.raw_payload ->> 'source_changed_at')::timestamptz
        else null
      end as source_changed_at,
      case
        when observation.source_changed_at is not null
          then coalesce(observation.source_changed_at, observation.fetched_at)
        when coalesce(observation.raw_payload ->> 'source_changed_at', '') ~
          '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
          then (observation.raw_payload ->> 'source_changed_at')::timestamptz
        else observation.fetched_at
      end as afdj_freshness_at,
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
      end as source_priority
    from public.water_operational_observations observation
    join public.water_data_sources source_registry
      on source_registry.id = observation.source_id
     and source_registry.country_code = observation.country_code
     and source_registry.is_active
    where observation.station_id is not null
      and observation.metric_code = 'water_level_cm'
      and observation.availability_status = 'available'
      and observation.quality_status in ('validated', 'corrected')
      and (p_station_id is null or observation.station_id = p_station_id)
  ),
  operational_prepared as (
    select
      effective.station_id,
      effective.level_cm,
      effective.observed_at,
      effective.observed_at_precision,
      effective.source_changed_at,
      case
        when effective.source_key = 'AFDJ'
          and effective.observed_at_precision = 'date'
          then effective.afdj_freshness_at
        else effective.observed_at
      end as freshness_at,
      effective.source_key,
      effective.source_name,
      effective.source_url,
      effective.quality_status,
      effective.confidence,
      effective.fetched_at,
      effective.created_at,
      effective.freshness_target_minutes,
      effective.source_priority
    from operational_effective effective
  ),
  operational_candidates as (
    select
      prepared.*,
      prepared.freshness_at <
        now() - make_interval(
          mins => coalesce(prepared.freshness_target_minutes, 2160)
        ) as candidate_is_stale
    from operational_prepared prepared
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
      null::timestamptz as source_changed_at,
      case
        when staging.exact_observed_at is not null
          then staging.exact_observed_at
        when staging.observed_at_precision = 'relative'
          and staging.source_age_seconds_approx is not null
          then staging.fetched_at - make_interval(
            secs => staging.source_age_seconds_approx::double precision
          )
        else null
      end as freshness_at,
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
      and (p_station_id is null or mapping.station_id = p_station_id)
  ),
  danubehis_candidates as (
    select
      prepared.*,
      prepared.freshness_at <
        now() - make_interval(
          mins => coalesce(prepared.freshness_target_minutes, 2160)
        ) as candidate_is_stale
    from danubehis_prepared prepared
    where prepared.observed_at is not null
      and prepared.freshness_at is not null
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
          candidate.freshness_at desc nulls last,
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
    latest.source_changed_at,
    latest.freshness_at,
    latest.source_key,
    latest.source_name,
    latest.source_url,
    latest.quality_status,
    latest.confidence,
    latest.fetched_at,
    floor(
      greatest(0, extract(epoch from (now() - latest.freshness_at)) / 60.0)
    )::integer,
    latest.candidate_is_stale
  from ranked latest
  join public.stations station
    on station.id = latest.station_id
  where latest.row_rank = 1
  order by station.display_order nulls last, station.name;
$$;

comment on function public.get_water_station_latest_v1(text) is
  'Secure Water latest contract separating observed_at measurement time from freshness_at. AFDJ date-only observations, including legacy exact-at-UTC-midnight rows, derive effective precision at query time and use source_changed_at, valid raw source_changed_at, then fetched_at. Arbitration remains fresh before stale and AFDJ before DanubeHIS before DanubeFIS.';

revoke all
  on function public.get_water_station_latest_v1(text)
  from public;

grant execute
  on function public.get_water_station_latest_v1(text)
  to anon, authenticated, service_role;
