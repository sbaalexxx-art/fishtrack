begin;

-- W4E-1: operational Water evidence foundation.
-- This migration does not fabricate measurements, infer numeric values from
-- community reports, or expose raw operational data directly to mobile clients.

create table public.water_data_sources (
  id uuid primary key default gen_random_uuid(),
  source_key text not null unique,
  display_name text not null,
  authority_name text not null,
  country_code text not null,
  source_kind text not null,
  acquisition_mode text not null,
  rights_class text not null,
  commercial_reuse_status text not null,
  base_url text,
  terms_url text,
  license_name text,
  data_format text,
  publication_cadence text,
  freshness_target_minutes integer,
  collector_enabled boolean not null default false,
  is_active boolean not null default true,
  last_reviewed_at timestamptz,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint water_data_sources_source_key_not_blank
    check (btrim(source_key) <> ''),
  constraint water_data_sources_display_name_not_blank
    check (btrim(display_name) <> ''),
  constraint water_data_sources_authority_name_not_blank
    check (btrim(authority_name) <> ''),
  constraint water_data_sources_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),
  constraint water_data_sources_source_kind_check
    check (
      source_kind in (
        'official_authority',
        'system_operator',
        'open_data_portal',
        'satellite_provider',
        'licensed_partner',
        'internal'
      )
    ),
  constraint water_data_sources_acquisition_mode_check
    check (
      acquisition_mode in (
        'official_public',
        'official_permissioned',
        'open_licensed',
        'entsoe',
        'satellite',
        'contracted',
        'internal'
      )
    ),
  constraint water_data_sources_rights_class_check
    check (
      rights_class in (
        'open_licensed',
        'public_display',
        'permission_required',
        'contracted',
        'internal'
      )
    ),
  constraint water_data_sources_commercial_reuse_status_check
    check (
      commercial_reuse_status in (
        'allowed',
        'permissioned',
        'restricted',
        'unknown'
      )
    ),
  constraint water_data_sources_freshness_target_check
    check (
      freshness_target_minutes is null
      or freshness_target_minutes >= 0
    ),
  constraint water_data_sources_provenance_object_check
    check (jsonb_typeof(provenance) = 'object'),
  constraint water_data_sources_collector_approval_check
    check (
      collector_enabled = false
      or (
        is_active = true
        and commercial_reuse_status in ('allowed', 'permissioned')
        and last_reviewed_at is not null
      )
    ),
  constraint water_data_sources_id_country_unique
    unique (id, country_code)
);

comment on table public.water_data_sources is
  'Registry of operational Water sources, acquisition methods, provenance and reuse rights.';

comment on column public.water_data_sources.collector_enabled is
  'Must remain false until technical access and legal reuse have both been approved.';

create table public.water_operational_observations (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null,
  country_code text not null,
  source_entity_id text not null,

  station_id text references public.stations(id) on delete restrict,
  water_body_id uuid references public.water_bodies(id) on delete restrict,
  dam_id uuid references public.dams(id) on delete restrict,
  reservoir_id uuid references public.reservoirs(id) on delete restrict,
  external_entity_key text,

  metric_code text not null,
  metric_name text,
  value numeric,
  unit text,
  availability_status text not null default 'available',

  observed_at timestamptz,
  observed_at_precision text not null default 'exact',
  period_start timestamptz,
  period_end timestamptz,

  quality_status text not null default 'raw',
  confidence text not null default 'unknown',

  source_record_id text,
  source_record_fingerprint text not null,
  source_url text,
  ingestion_run_id text,
  fetched_at timestamptz not null,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  constraint water_operational_observations_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),
  constraint water_operational_observations_source_country_fk
    foreign key (source_id, country_code)
    references public.water_data_sources(id, country_code)
    on delete restrict,
  constraint water_operational_observations_source_entity_not_blank
    check (btrim(source_entity_id) <> ''),
  constraint water_operational_observations_metric_not_blank
    check (btrim(metric_code) <> ''),
  constraint water_operational_observations_fingerprint_format_check
    check (source_record_fingerprint ~ '^[0-9a-f]{64}$'),
  constraint water_operational_observations_single_entity_check
    check (
      num_nonnulls(
        station_id,
        water_body_id,
        dam_id,
        reservoir_id,
        external_entity_key
      ) = 1
    ),
  constraint water_operational_observations_external_key_not_blank
    check (
      external_entity_key is null
      or btrim(external_entity_key) <> ''
    ),
  constraint water_operational_observations_availability_check
    check (
      availability_status in (
        'available',
        'unavailable',
        'not_published',
        'suspect'
      )
    ),
  constraint water_operational_observations_available_value_check
    check (
      availability_status <> 'available'
      or (
        value is not null
        and unit is not null
        and btrim(unit) <> ''
        and observed_at is not null
      )
    ),
  constraint water_operational_observations_precision_check
    check (
      observed_at_precision in (
        'exact',
        'date',
        'interval',
        'relative',
        'unknown'
      )
    ),
  constraint water_operational_observations_period_check
    check (
      period_start is null
      or period_end is null
      or period_end >= period_start
    ),
  constraint water_operational_observations_quality_check
    check (
      quality_status in (
        'raw',
        'validated',
        'suspect',
        'rejected',
        'corrected'
      )
    ),
  constraint water_operational_observations_confidence_check
    check (confidence in ('high', 'medium', 'low', 'unknown')),
  constraint water_operational_observations_raw_payload_object_check
    check (jsonb_typeof(raw_payload) = 'object')
);

comment on table public.water_operational_observations is
  'Append-only official or licensed operational observations for stations, water bodies, dams and reservoirs.';

comment on column public.water_operational_observations.metric_code is
  'Examples: water_level_cm, discharge_m3s, reservoir_level_m, reservoir_volume_million_m3, filling_percent, inflow_m3s, outflow_m3s, turbine_flow_m3s, spill_flow_m3s, generation_mw.';

create unique index if not exists water_operational_observations_fingerprint_unique_idx
  on public.water_operational_observations (
    source_id,
    source_entity_id,
    metric_code,
    source_record_fingerprint
  );

create index if not exists water_operational_observations_source_time_idx
  on public.water_operational_observations (source_id, observed_at desc);

create index if not exists water_operational_observations_station_time_idx
  on public.water_operational_observations (station_id, metric_code, observed_at desc)
  where station_id is not null;

create index if not exists water_operational_observations_water_body_time_idx
  on public.water_operational_observations (water_body_id, metric_code, observed_at desc)
  where water_body_id is not null;

create index if not exists water_operational_observations_dam_time_idx
  on public.water_operational_observations (dam_id, metric_code, observed_at desc)
  where dam_id is not null;

create index if not exists water_operational_observations_reservoir_time_idx
  on public.water_operational_observations (reservoir_id, metric_code, observed_at desc)
  where reservoir_id is not null;

create table public.water_community_observations (
  report_id uuid primary key
    references public.reports(id) on delete cascade,

  station_id text references public.stations(id) on delete restrict,
  water_body_id uuid references public.water_bodies(id) on delete restrict,
  dam_id uuid references public.dams(id) on delete restrict,
  reservoir_id uuid references public.reservoirs(id) on delete restrict,

  association_status text not null default 'unresolved',
  observed_at timestamptz not null,
  observed_at_precision text not null default 'reported',

  flow_state text not null default 'unknown',
  level_trend text not null default 'unknown',
  operation_signal text not null default 'unknown',
  water_clarity text not null default 'unknown',
  fish_activity text not null default 'unknown',

  species_name text,
  bait_or_lure text,
  fishing_method text,
  catch_count integer,

  classification_origin text not null default 'user_selected',
  classification_confidence numeric,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint water_community_observations_single_entity_check
    check (
      num_nonnulls(
        station_id,
        water_body_id,
        dam_id,
        reservoir_id
      ) <= 1
    ),
  constraint water_community_observations_association_status_check
    check (
      association_status in (
        'unresolved',
        'auto_matched',
        'user_confirmed',
        'moderator_confirmed'
      )
    ),
  constraint water_community_observations_resolved_entity_check
    check (
      association_status = 'unresolved'
      or num_nonnulls(
        station_id,
        water_body_id,
        dam_id,
        reservoir_id
      ) = 1
    ),
  constraint water_community_observations_precision_check
    check (
      observed_at_precision in (
        'exact',
        'approximate',
        'reported'
      )
    ),
  constraint water_community_observations_flow_state_check
    check (
      flow_state in (
        'strong',
        'moderate',
        'weak',
        'stagnant',
        'unknown'
      )
    ),
  constraint water_community_observations_level_trend_check
    check (
      level_trend in (
        'rising',
        'stable',
        'falling',
        'unknown'
      )
    ),
  constraint water_community_observations_operation_signal_check
    check (
      operation_signal in (
        'none',
        'possible_release',
        'possible_turbining',
        'possible_spill',
        'unknown'
      )
    ),
  constraint water_community_observations_clarity_check
    check (
      water_clarity in (
        'clear',
        'slightly_turbid',
        'turbid',
        'very_turbid',
        'unknown'
      )
    ),
  constraint water_community_observations_fish_activity_check
    check (
      fish_activity in (
        'very_good',
        'good',
        'low',
        'none',
        'unknown'
      )
    ),
  constraint water_community_observations_catch_count_check
    check (catch_count is null or catch_count >= 0),
  constraint water_community_observations_species_name_check
    check (
      species_name is null
      or btrim(species_name) <> ''
    ),
  constraint water_community_observations_bait_or_lure_check
    check (
      bait_or_lure is null
      or btrim(bait_or_lure) <> ''
    ),
  constraint water_community_observations_fishing_method_check
    check (
      fishing_method is null
      or btrim(fishing_method) <> ''
    ),
  constraint water_community_observations_origin_check
    check (
      classification_origin in (
        'user_selected',
        'ai_suggested',
        'ai_confirmed',
        'moderator'
      )
    ),
  constraint water_community_observations_confidence_check
    check (
      classification_confidence is null
      or (
        classification_confidence >= 0
        and classification_confidence <= 1
      )
    ),

  constraint water_community_observations_signal_required_check
    check (
      flow_state <> 'unknown'
      or level_trend <> 'unknown'
      or operation_signal <> 'unknown'
      or water_clarity <> 'unknown'
      or fish_activity <> 'unknown'
      or species_name is not null
      or bait_or_lure is not null
      or fishing_method is not null
    )
);

comment on table public.water_community_observations is
  'Structured, qualitative Water evidence attached one-to-one to a community report. It never stores inferred official centimetres, flows or reservoir volumes.';

create index if not exists water_community_observations_observed_at_idx
  on public.water_community_observations (observed_at desc);

create index if not exists water_community_observations_station_time_idx
  on public.water_community_observations (station_id, observed_at desc)
  where station_id is not null;

create index if not exists water_community_observations_water_body_time_idx
  on public.water_community_observations (water_body_id, observed_at desc)
  where water_body_id is not null;

create index if not exists water_community_observations_dam_time_idx
  on public.water_community_observations (dam_id, observed_at desc)
  where dam_id is not null;

create index if not exists water_community_observations_reservoir_time_idx
  on public.water_community_observations (reservoir_id, observed_at desc)
  where reservoir_id is not null;

create or replace function public.validate_water_data_source_runtime()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.last_reviewed_at is not null
     and new.last_reviewed_at > clock_timestamp() + interval '5 minutes' then
    raise exception
      'last_reviewed_at cannot be more than five minutes in the future.'
      using errcode = '22007';
  end if;

  if new.collector_enabled
     and (
       not new.is_active
       or new.commercial_reuse_status not in ('allowed', 'permissioned')
       or new.last_reviewed_at is null
     ) then
    raise exception
      'Collector activation requires an active, legally approved and reviewed source.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all privileges
  on function public.validate_water_data_source_runtime()
  from public, anon, authenticated;


create or replace function public.validate_water_operational_observation_runtime()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  future_limit timestamptz := clock_timestamp() + interval '5 minutes';
begin
  if new.fetched_at > future_limit then
    raise exception
      'fetched_at cannot be more than five minutes in the future.'
      using errcode = '22007';
  end if;

  if new.observed_at is not null
     and new.observed_at > future_limit then
    raise exception
      'observed_at cannot be more than five minutes in the future.'
      using errcode = '22007';
  end if;

  if new.period_start is not null
     and new.period_start > future_limit then
    raise exception
      'period_start cannot be more than five minutes in the future.'
      using errcode = '22007';
  end if;

  if new.period_end is not null
     and new.period_end > future_limit then
    raise exception
      'period_end cannot be more than five minutes in the future.'
      using errcode = '22007';
  end if;

  return new;
end;
$$;

revoke all privileges
  on function public.validate_water_operational_observation_runtime()
  from public, anon, authenticated;


create or replace function public.prevent_water_operational_observation_mutation()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception
    'Water operational observations are append-only; insert a corrected observation instead.'
    using errcode = '55000';
end;
$$;

revoke all privileges
  on function public.prevent_water_operational_observation_mutation()
  from public, anon, authenticated;


create or replace function public.validate_water_community_observation_runtime()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.observed_at > clock_timestamp() + interval '5 minutes' then
    raise exception
      'Community observed_at cannot be more than five minutes in the future.'
      using errcode = '22007';
  end if;

  return new;
end;
$$;

revoke all privileges
  on function public.validate_water_community_observation_runtime()
  from public, anon, authenticated;


drop trigger if exists water_data_sources_validate_runtime
  on public.water_data_sources;
create trigger water_data_sources_validate_runtime
before insert or update on public.water_data_sources
for each row
execute function public.validate_water_data_source_runtime();

drop trigger if exists water_operational_observations_validate_runtime
  on public.water_operational_observations;
create trigger water_operational_observations_validate_runtime
before insert on public.water_operational_observations
for each row
execute function public.validate_water_operational_observation_runtime();

drop trigger if exists water_operational_observations_prevent_mutation
  on public.water_operational_observations;
create trigger water_operational_observations_prevent_mutation
before update or delete on public.water_operational_observations
for each row
execute function public.prevent_water_operational_observation_mutation();

drop trigger if exists water_community_observations_validate_runtime
  on public.water_community_observations;
create trigger water_community_observations_validate_runtime
before insert or update on public.water_community_observations
for each row
execute function public.validate_water_community_observation_runtime();

drop trigger if exists water_data_sources_set_updated_at
  on public.water_data_sources;
create trigger water_data_sources_set_updated_at
before update on public.water_data_sources
for each row execute function public.set_updated_at();

drop trigger if exists water_community_observations_set_updated_at
  on public.water_community_observations;
create trigger water_community_observations_set_updated_at
before update on public.water_community_observations
for each row execute function public.set_updated_at();

alter table public.water_data_sources enable row level security;
alter table public.water_operational_observations enable row level security;
alter table public.water_community_observations enable row level security;

-- Source registry and raw operational observations remain backend-only.
revoke all privileges
  on table public.water_data_sources
  from public, anon, authenticated;

revoke all privileges
  on table public.water_operational_observations
  from public, anon, authenticated;

grant select, insert, update, delete
  on table public.water_data_sources
  to service_role;

grant select, insert
  on table public.water_operational_observations
  to service_role;

-- Structured community evidence follows ownership of its parent report.
revoke all privileges
  on table public.water_community_observations
  from public, anon, authenticated;

drop policy if exists "water_community_observations_authenticated_read"
  on public.water_community_observations;
create policy "water_community_observations_authenticated_read"
on public.water_community_observations
for select to authenticated
using (
  exists (
    select 1
    from public.reports as report
    where report.id = report_id
  )
);

drop policy if exists "water_community_observations_owner_insert"
  on public.water_community_observations;
create policy "water_community_observations_owner_insert"
on public.water_community_observations
for insert to authenticated
with check (
  exists (
    select 1
    from public.reports as report
    where report.id = report_id
      and report.user_id = auth.uid()
  )
  and association_status = 'unresolved'
  and classification_origin = 'user_selected'
  and classification_confidence is null

);

grant select
  on table public.water_community_observations
  to authenticated;

grant insert (
  report_id,
  station_id,
  water_body_id,
  dam_id,
  reservoir_id,
  observed_at,
  observed_at_precision,
  flow_state,
  level_trend,
  operation_signal,
  water_clarity,
  fish_activity,
  species_name,
  bait_or_lure,
  fishing_method,
  catch_count
)
on table public.water_community_observations
to authenticated;

grant select, insert, update, delete
  on table public.water_community_observations
  to service_role;

commit;
