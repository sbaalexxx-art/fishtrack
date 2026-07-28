-- FluviAI W4D-2: canonical Water identity reconciliation.
-- Additive only. No ANAR catalog import and no Flutter changes.
-- Preserves all existing station IDs and daily water snapshots.

begin;

-- Capture the runtime baseline inside this transaction. Snapshot history may
-- grow legitimately after the 178-row checkpoint, but W4D-2 must not change it.
create temporary table w4d2_runtime_baseline (
  station_count integer not null,
  snapshot_count bigint not null,
  snapshot_station_count integer not null
) on commit drop;

insert into w4d2_runtime_baseline (
  station_count,
  snapshot_count,
  snapshot_station_count
)
select
  (select count(*)::integer from public.stations),
  (select count(*) from public.daily_water_snapshots),
  (
    select count(distinct station_id)::integer
    from public.daily_water_snapshots
  );

-- Fail safely when the verified remote identity baseline has drifted.
do $baseline$
declare
  station_count integer;
  snapshot_count bigint;
  snapshot_station_count integer;
begin
  select
    baseline.station_count,
    baseline.snapshot_count,
    baseline.snapshot_station_count
  into
    station_count,
    snapshot_count,
    snapshot_station_count
  from w4d2_runtime_baseline as baseline;

  if station_count <> 27 then
    raise exception
      'W4D-2 baseline mismatch: expected 27 stations, found %.',
      station_count;
  end if;

  if snapshot_count < 178 then
    raise exception
      'W4D-2 baseline mismatch: expected at least 178 snapshots, found %.',
      snapshot_count;
  end if;

  if snapshot_station_count <> 23 then
    raise exception
      'W4D-2 baseline mismatch: expected 23 canonical snapshot stations, found %.',
      snapshot_station_count;
  end if;

  if exists (
    select 1
    from public.daily_water_snapshots as snapshot
    left join public.stations as station
      on station.id = snapshot.station_id
    where station.id is null
  ) then
    raise exception
      'W4D-2 baseline mismatch: orphan daily water snapshot detected.';
  end if;
end;
$baseline$;

create table if not exists public.water_bodies (
  id uuid primary key default gen_random_uuid(),
  type text not null,
  parent_water_body_id uuid,
  country_code text not null,
  region_id text,
  canonical_key text not null,
  name text not null,
  name_en text,
  normalized_name text not null,
  latitude double precision,
  longitude double precision,
  canonicalization_status text not null default 'ready',
  map_eligible boolean not null default true,
  provenance_source text not null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint water_bodies_type_check
    check (type in ('river', 'branch', 'reservoir', 'lake')),
  constraint water_bodies_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),
  constraint water_bodies_canonical_key_not_blank_check
    check (btrim(canonical_key) <> ''),
  constraint water_bodies_name_not_blank_check
    check (btrim(name) <> ''),
  constraint water_bodies_normalized_name_not_blank_check
    check (btrim(normalized_name) <> ''),
  constraint water_bodies_provenance_source_not_blank_check
    check (btrim(provenance_source) <> ''),
  constraint water_bodies_provenance_object_check
    check (jsonb_typeof(provenance) = 'object'),
  constraint water_bodies_latitude_check
    check (latitude is null or latitude between -90 and 90),
  constraint water_bodies_longitude_check
    check (longitude is null or longitude between -180 and 180),
  constraint water_bodies_canonicalization_status_check
    check (canonicalization_status in ('ready', 'review_required')),
  constraint water_bodies_review_visibility_check
    check (
      canonicalization_status <> 'review_required'
      or map_eligible = false
    ),
  constraint water_bodies_parent_shape_check
    check (
      (type = 'branch' and parent_water_body_id is not null)
      or
      (type <> 'branch' and parent_water_body_id is null)
    ),
  constraint water_bodies_not_own_parent_check
    check (parent_water_body_id is null or parent_water_body_id <> id),
  constraint water_bodies_country_canonical_key_unique
    unique (country_code, canonical_key),
  constraint water_bodies_parent_fkey
    foreign key (parent_water_body_id)
    references public.water_bodies(id)
    on update cascade
    on delete restrict
);

create or replace function public.validate_water_body_hierarchy()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  parent_type text;
  parent_country_code text;
begin
  if new.type = 'branch' then
    select type, country_code
      into parent_type, parent_country_code
    from public.water_bodies
    where id = new.parent_water_body_id;

    if parent_type is null then
      raise exception 'Branch parent water body does not exist.';
    end if;

    if parent_type <> 'river' then
      raise exception 'A branch parent must be a river.';
    end if;

    if parent_country_code <> new.country_code then
      raise exception
        'A branch and its parent river must share country_code.';
    end if;
  elsif new.parent_water_body_id is not null then
    raise exception
      'Only branch water bodies may use parent_water_body_id in W4D-2.';
  end if;

  return new;
end;
$function$;

revoke all privileges
  on function public.validate_water_body_hierarchy()
  from public, anon, authenticated;

drop trigger if exists water_bodies_validate_hierarchy
  on public.water_bodies;

create trigger water_bodies_validate_hierarchy
before insert or update of type, parent_water_body_id, country_code
on public.water_bodies
for each row execute function public.validate_water_body_hierarchy();

drop trigger if exists water_bodies_set_updated_at
  on public.water_bodies;

create trigger water_bodies_set_updated_at
before update on public.water_bodies
for each row execute function public.set_updated_at();

create index if not exists water_bodies_type_idx
  on public.water_bodies (type);

create index if not exists water_bodies_parent_idx
  on public.water_bodies (parent_water_body_id)
  where parent_water_body_id is not null;

create index if not exists water_bodies_country_normalized_name_idx
  on public.water_bodies (country_code, normalized_name);

create index if not exists water_bodies_public_map_idx
  on public.water_bodies (country_code, type, map_eligible)
  where map_eligible = true;

create table if not exists public.water_station_source_mappings (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  country_code text not null,
  source_station_id text not null,
  station_id text not null,
  mapping_status text not null default 'verified',
  confidence text not null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint water_station_source_mappings_source_not_blank_check
    check (btrim(source) <> ''),
  constraint water_station_source_mappings_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),
  constraint water_station_source_mappings_source_id_not_blank_check
    check (btrim(source_station_id) <> ''),
  constraint water_station_source_mappings_status_check
    check (mapping_status in ('verified', 'review_required')),
  constraint water_station_source_mappings_confidence_check
    check (confidence in ('high', 'medium', 'low')),
  constraint water_station_source_mappings_provenance_object_check
    check (jsonb_typeof(provenance) = 'object'),
  constraint water_station_source_mappings_source_identity_unique
    unique (source, country_code, source_station_id),
  constraint water_station_source_mappings_station_fkey
    foreign key (station_id)
    references public.stations(id)
    on update cascade
    on delete restrict
);

drop trigger if exists water_station_source_mappings_set_updated_at
  on public.water_station_source_mappings;

create trigger water_station_source_mappings_set_updated_at
before update on public.water_station_source_mappings
for each row execute function public.set_updated_at();

create index if not exists water_station_source_mappings_station_idx
  on public.water_station_source_mappings (station_id);

create table if not exists public.water_body_source_mappings (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  country_code text not null,
  source_water_body_id text not null,
  water_body_id uuid not null,
  mapping_status text not null default 'verified',
  confidence text not null,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint water_body_source_mappings_source_not_blank_check
    check (btrim(source) <> ''),
  constraint water_body_source_mappings_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),
  constraint water_body_source_mappings_source_id_not_blank_check
    check (btrim(source_water_body_id) <> ''),
  constraint water_body_source_mappings_status_check
    check (mapping_status in ('verified', 'review_required')),
  constraint water_body_source_mappings_confidence_check
    check (confidence in ('high', 'medium', 'low')),
  constraint water_body_source_mappings_provenance_object_check
    check (jsonb_typeof(provenance) = 'object'),
  constraint water_body_source_mappings_source_identity_unique
    unique (source, country_code, source_water_body_id),
  constraint water_body_source_mappings_water_body_fkey
    foreign key (water_body_id)
    references public.water_bodies(id)
    on update cascade
    on delete restrict
);

drop trigger if exists water_body_source_mappings_set_updated_at
  on public.water_body_source_mappings;

create trigger water_body_source_mappings_set_updated_at
before update on public.water_body_source_mappings
for each row execute function public.set_updated_at();

create index if not exists water_body_source_mappings_water_body_idx
  on public.water_body_source_mappings (water_body_id);

alter table public.stations
  add column if not exists water_body_id uuid;

alter table public.dams
  add column if not exists water_body_id uuid;

alter table public.reservoirs
  add column if not exists water_body_id uuid;

do $foreign_keys$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.stations'::regclass
      and conname = 'stations_water_body_fkey'
  ) then
    alter table public.stations
      add constraint stations_water_body_fkey
      foreign key (water_body_id)
      references public.water_bodies(id)
      on update cascade
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.dams'::regclass
      and conname = 'dams_water_body_fkey'
  ) then
    alter table public.dams
      add constraint dams_water_body_fkey
      foreign key (water_body_id)
      references public.water_bodies(id)
      on update cascade
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.reservoirs'::regclass
      and conname = 'reservoirs_water_body_fkey'
  ) then
    alter table public.reservoirs
      add constraint reservoirs_water_body_fkey
      foreign key (water_body_id)
      references public.water_bodies(id)
      on update cascade
      on delete restrict;
  end if;
end;
$foreign_keys$;

create index if not exists stations_water_body_idx
  on public.stations (water_body_id)
  where water_body_id is not null;

create index if not exists dams_water_body_idx
  on public.dams (water_body_id)
  where water_body_id is not null;

create index if not exists reservoirs_water_body_idx
  on public.reservoirs (water_body_id)
  where water_body_id is not null;

create table if not exists public.water_entity_relations (
  id uuid primary key default gen_random_uuid(),
  relation_type text not null,

  source_water_body_id uuid,
  source_station_id text,
  source_dam_id uuid,
  source_reservoir_id uuid,

  target_water_body_id uuid,
  target_station_id text,
  target_dam_id uuid,
  target_reservoir_id uuid,

  source_entity_key text generated always as (
    case
      when source_water_body_id is not null
        then 'water_body:' || source_water_body_id::text
      when source_station_id is not null
        then 'station:' || source_station_id
      when source_dam_id is not null
        then 'dam:' || source_dam_id::text
      when source_reservoir_id is not null
        then 'reservoir:' || source_reservoir_id::text
    end
  ) stored,

  target_entity_key text generated always as (
    case
      when target_water_body_id is not null
        then 'water_body:' || target_water_body_id::text
      when target_station_id is not null
        then 'station:' || target_station_id
      when target_dam_id is not null
        then 'dam:' || target_dam_id::text
      when target_reservoir_id is not null
        then 'reservoir:' || target_reservoir_id::text
    end
  ) stored,

  relation_origin text not null,
  match_method text not null,
  confidence text not null,
  proposal_status text not null,
  review_status text not null,
  review_reason text,
  distance_km numeric,
  map_eligible boolean not null default false,
  source text not null,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint water_entity_relations_type_not_blank_check
    check (btrim(relation_type) <> ''),
  constraint water_entity_relations_source_endpoint_check
    check (
      num_nonnulls(
        source_water_body_id,
        source_station_id,
        source_dam_id,
        source_reservoir_id
      ) = 1
    ),
  constraint water_entity_relations_target_endpoint_check
    check (
      num_nonnulls(
        target_water_body_id,
        target_station_id,
        target_dam_id,
        target_reservoir_id
      ) = 1
    ),
  constraint water_entity_relations_distinct_endpoints_check
    check (source_entity_key <> target_entity_key),
  constraint water_entity_relations_origin_check
    check (
      relation_origin in (
        'source_confirmed',
        'manual_validated',
        'automatic_rule_qualified'
      )
    ),
  constraint water_entity_relations_match_method_not_blank_check
    check (btrim(match_method) <> ''),
  constraint water_entity_relations_confidence_check
    check (confidence in ('high', 'medium', 'low')),
  constraint water_entity_relations_proposal_status_check
    check (
      proposal_status in (
        'source_confirmed',
        'manual_validated',
        'automatic_rule_qualified'
      )
    ),
  constraint water_entity_relations_review_status_check
    check (
      review_status in (
        'approved',
        'rule_qualified_not_manually_verified',
        'review_required'
      )
    ),
  constraint water_entity_relations_review_visibility_check
    check (
      review_status <> 'review_required'
      or map_eligible = false
    ),
  constraint water_entity_relations_distance_check
    check (distance_km is null or distance_km >= 0),
  constraint water_entity_relations_source_not_blank_check
    check (btrim(source) <> ''),
  constraint water_entity_relations_evidence_object_check
    check (jsonb_typeof(evidence) = 'object'),

  constraint water_entity_relations_source_water_body_fkey
    foreign key (source_water_body_id)
    references public.water_bodies(id)
    on update cascade
    on delete restrict,
  constraint water_entity_relations_source_station_fkey
    foreign key (source_station_id)
    references public.stations(id)
    on update cascade
    on delete restrict,
  constraint water_entity_relations_source_dam_fkey
    foreign key (source_dam_id)
    references public.dams(id)
    on update cascade
    on delete restrict,
  constraint water_entity_relations_source_reservoir_fkey
    foreign key (source_reservoir_id)
    references public.reservoirs(id)
    on update cascade
    on delete restrict,

  constraint water_entity_relations_target_water_body_fkey
    foreign key (target_water_body_id)
    references public.water_bodies(id)
    on update cascade
    on delete restrict,
  constraint water_entity_relations_target_station_fkey
    foreign key (target_station_id)
    references public.stations(id)
    on update cascade
    on delete restrict,
  constraint water_entity_relations_target_dam_fkey
    foreign key (target_dam_id)
    references public.dams(id)
    on update cascade
    on delete restrict,
  constraint water_entity_relations_target_reservoir_fkey
    foreign key (target_reservoir_id)
    references public.reservoirs(id)
    on update cascade
    on delete restrict,

  constraint water_entity_relations_identity_unique
    unique (relation_type, source_entity_key, target_entity_key)
);

drop trigger if exists water_entity_relations_set_updated_at
  on public.water_entity_relations;

create trigger water_entity_relations_set_updated_at
before update on public.water_entity_relations
for each row execute function public.set_updated_at();

create index if not exists water_entity_relations_source_idx
  on public.water_entity_relations (source_entity_key);

create index if not exists water_entity_relations_target_idx
  on public.water_entity_relations (target_entity_key);

create index if not exists water_entity_relations_type_idx
  on public.water_entity_relations (relation_type);

create index if not exists water_entity_relations_public_map_idx
  on public.water_entity_relations (relation_type, map_eligible)
  where map_eligible = true;

-- Canonical Romania seed only. This is not the ANAR catalog import.
insert into public.water_bodies (
  type,
  country_code,
  region_id,
  canonical_key,
  name,
  name_en,
  normalized_name,
  canonicalization_status,
  map_eligible,
  provenance_source,
  provenance
)
values (
  'river',
  'RO',
  null,
  'ro-danube',
  'Dunărea',
  'Danube',
  'dunarea',
  'ready',
  true,
  'FLUVIAI_W4D2',
  '{"classification":"canonical_seed","scope":"Romania"}'::jsonb
)
on conflict (country_code, canonical_key) do nothing;

insert into public.water_bodies (
  type,
  parent_water_body_id,
  country_code,
  region_id,
  canonical_key,
  name,
  name_en,
  normalized_name,
  canonicalization_status,
  map_eligible,
  provenance_source,
  provenance
)
select
  'branch',
  danube.id,
  'RO',
  null,
  branch.canonical_key,
  branch.name,
  branch.name_en,
  branch.normalized_name,
  'ready',
  true,
  'FLUVIAI_W4D2',
  '{"classification":"canonical_seed","scope":"Romania"}'::jsonb
from public.water_bodies as danube
cross join (
  values
    (
      'ro-danube-borcea',
      'Brațul Borcea',
      'Borcea Branch',
      'bratul borcea'
    ),
    (
      'ro-danube-chilia',
      'Brațul Chilia',
      'Chilia Branch',
      'bratul chilia'
    ),
    (
      'ro-danube-sulina',
      'Brațul Sulina',
      'Sulina Branch',
      'bratul sulina'
    ),
    (
      'ro-danube-sfantu-gheorghe',
      'Brațul Sfântu Gheorghe',
      'Saint George Branch',
      'bratul sfantu gheorghe'
    )
) as branch(canonical_key, name, name_en, normalized_name)
where danube.country_code = 'RO'
  and danube.canonical_key = 'ro-danube'
on conflict (country_code, canonical_key) do nothing;

-- Link only the verified 23 canonical stations that already own snapshots.
-- The four legacy rows without snapshots remain explicitly unclassified.
with danube as (
  select id
  from public.water_bodies
  where country_code = 'RO'
    and canonical_key = 'ro-danube'
)
update public.stations as station
set water_body_id = danube.id
from danube
where station.water_body_id is null
  and exists (
    select 1
    from public.daily_water_snapshots as snapshot
    where snapshot.station_id = station.id
  );

-- Represent the four branch relationships without turning branches into stations.
insert into public.water_entity_relations (
  relation_type,
  source_water_body_id,
  target_water_body_id,
  relation_origin,
  match_method,
  confidence,
  proposal_status,
  review_status,
  review_reason,
  distance_km,
  map_eligible,
  source,
  evidence
)
select
  'branch_of',
  branch.id,
  danube.id,
  'source_confirmed',
  'canonical_hierarchy_seed',
  'high',
  'source_confirmed',
  'approved',
  null,
  null,
  true,
  'FLUVIAI_W4D2',
  jsonb_build_object(
    'basis',
    'parent_water_body_id',
    'canonical_key',
    branch.canonical_key
  )
from public.water_bodies as branch
join public.water_bodies as danube
  on danube.id = branch.parent_water_body_id
where branch.country_code = 'RO'
  and branch.type = 'branch'
  and danube.country_code = 'RO'
  and danube.canonical_key = 'ro-danube'
on conflict on constraint water_entity_relations_identity_unique
do nothing;

-- RLS and least-privilege public access.
alter table public.water_bodies enable row level security;
alter table public.water_station_source_mappings enable row level security;
alter table public.water_body_source_mappings enable row level security;
alter table public.water_entity_relations enable row level security;

drop policy if exists "water_bodies_public_map_read"
  on public.water_bodies;

create policy "water_bodies_public_map_read"
on public.water_bodies
for select
to anon, authenticated
using (
  map_eligible = true
  and canonicalization_status = 'ready'
);

drop policy if exists "water_entity_relations_public_map_read"
  on public.water_entity_relations;

create policy "water_entity_relations_public_map_read"
on public.water_entity_relations
for select
to anon, authenticated
using (
  map_eligible = true
  and review_status <> 'review_required'
);

revoke all privileges
  on table public.water_bodies
  from public, anon, authenticated;

revoke all privileges
  on table public.water_station_source_mappings
  from public, anon, authenticated;

revoke all privileges
  on table public.water_body_source_mappings
  from public, anon, authenticated;

revoke all privileges
  on table public.water_entity_relations
  from public, anon, authenticated;

revoke all privileges
  on table public.dams
  from public, anon, authenticated;

revoke all privileges
  on table public.reservoirs
  from public, anon, authenticated;

revoke all privileges
  on table public.dam_reservoir_relations
  from public, anon, authenticated;

grant all privileges
  on table public.water_bodies
  to service_role;

grant all privileges
  on table public.water_station_source_mappings
  to service_role;

grant all privileges
  on table public.water_body_source_mappings
  to service_role;

grant all privileges
  on table public.water_entity_relations
  to service_role;

grant all privileges
  on table public.dams
  to service_role;

grant all privileges
  on table public.reservoirs
  to service_role;

grant all privileges
  on table public.dam_reservoir_relations
  to service_role;

grant select (
  id,
  type,
  parent_water_body_id,
  country_code,
  region_id,
  canonical_key,
  name,
  name_en,
  normalized_name,
  latitude,
  longitude,
  canonicalization_status,
  map_eligible,
  created_at,
  updated_at
)
on table public.water_bodies
to anon, authenticated;

grant select (
  id,
  water_body_id,
  country_code,
  name,
  name_en,
  resolved_river_name,
  river_resolution_status,
  county,
  basin_code,
  basin_name,
  latitude,
  longitude,
  importance_class,
  importance_category,
  reservoir_type,
  dam_type,
  uses,
  cadastre_code,
  canonicalization_status,
  map_eligible,
  created_at,
  updated_at
)
on table public.dams
to anon, authenticated;

grant select (
  id,
  water_body_id,
  country_code,
  name,
  alternative_name,
  name_en,
  resolved_river_name,
  river_resolution_status,
  county,
  basin_code,
  basin_name,
  latitude,
  longitude,
  surface_area_km2,
  perimeter_km,
  volume_million_m3,
  flood_attenuation_volume_million_m3,
  dam_height_m,
  mean_depth_m,
  elevation_m,
  risk_index,
  importance_class,
  importance_category,
  reservoir_type,
  dam_type,
  commissioned_year,
  hydropower_use,
  fishery_use,
  water_supply_use,
  recreation_use,
  canonicalization_status,
  map_eligible,
  created_at,
  updated_at
)
on table public.reservoirs
to anon, authenticated;

grant select (
  id,
  relation_type,
  dam_id,
  reservoir_id,
  relation_origin,
  confidence,
  proposal_status,
  review_status,
  review_reason,
  distance_km,
  map_eligible,
  created_at,
  updated_at
)
on table public.dam_reservoir_relations
to anon, authenticated;

grant select (
  id,
  relation_type,
  source_water_body_id,
  source_station_id,
  source_dam_id,
  source_reservoir_id,
  target_water_body_id,
  target_station_id,
  target_dam_id,
  target_reservoir_id,
  source_entity_key,
  target_entity_key,
  relation_origin,
  confidence,
  proposal_status,
  review_status,
  review_reason,
  distance_km,
  map_eligible,
  created_at,
  updated_at
)
on table public.water_entity_relations
to anon, authenticated;

create or replace view public.water_bodies_public
with (security_invoker = true, security_barrier = true)
as
select
  id,
  type,
  parent_water_body_id,
  country_code,
  region_id,
  canonical_key,
  name,
  name_en,
  normalized_name,
  latitude,
  longitude,
  map_eligible,
  created_at,
  updated_at
from public.water_bodies
where map_eligible = true
  and canonicalization_status = 'ready';

create or replace view public.water_stations_public
with (security_invoker = true, security_barrier = true)
as
select
  id,
  water_body_id,
  name,
  river,
  level,
  trend,
  latitude,
  longitude,
  last_update,
  display_order
from public.stations
where water_body_id is not null;

create or replace view public.water_dams_public
with (security_invoker = true, security_barrier = true)
as
select
  id,
  water_body_id,
  country_code,
  name,
  name_en,
  resolved_river_name,
  river_resolution_status,
  county,
  basin_code,
  basin_name,
  latitude,
  longitude,
  importance_class,
  importance_category,
  reservoir_type,
  dam_type,
  uses,
  cadastre_code,
  map_eligible,
  created_at,
  updated_at
from public.dams
where map_eligible = true
  and canonicalization_status = 'ready';

create or replace view public.water_reservoirs_public
with (security_invoker = true, security_barrier = true)
as
select
  id,
  water_body_id,
  country_code,
  name,
  alternative_name,
  name_en,
  resolved_river_name,
  river_resolution_status,
  county,
  basin_code,
  basin_name,
  latitude,
  longitude,
  surface_area_km2,
  perimeter_km,
  volume_million_m3,
  flood_attenuation_volume_million_m3,
  dam_height_m,
  mean_depth_m,
  elevation_m,
  risk_index,
  importance_class,
  importance_category,
  reservoir_type,
  dam_type,
  commissioned_year,
  hydropower_use,
  fishery_use,
  water_supply_use,
  recreation_use,
  map_eligible,
  created_at,
  updated_at
from public.reservoirs
where map_eligible = true
  and canonicalization_status = 'ready';

create or replace view public.dam_reservoir_relations_public
with (security_invoker = true, security_barrier = true)
as
select
  id,
  relation_type,
  dam_id,
  reservoir_id,
  relation_origin,
  confidence,
  proposal_status,
  review_status,
  review_reason,
  distance_km,
  map_eligible,
  created_at,
  updated_at
from public.dam_reservoir_relations
where map_eligible = true;

create or replace view public.water_entity_relations_public
with (security_invoker = true, security_barrier = true)
as
select
  id,
  relation_type,
  source_water_body_id,
  source_station_id,
  source_dam_id,
  source_reservoir_id,
  target_water_body_id,
  target_station_id,
  target_dam_id,
  target_reservoir_id,
  source_entity_key,
  target_entity_key,
  relation_origin,
  confidence,
  proposal_status,
  review_status,
  review_reason,
  distance_km,
  map_eligible,
  created_at,
  updated_at
from public.water_entity_relations
where map_eligible = true
  and review_status <> 'review_required';

revoke all privileges
  on table public.water_bodies_public
  from public, anon, authenticated;

revoke all privileges
  on table public.water_stations_public
  from public, anon, authenticated;

revoke all privileges
  on table public.water_dams_public
  from public, anon, authenticated;

revoke all privileges
  on table public.water_reservoirs_public
  from public, anon, authenticated;

revoke all privileges
  on table public.dam_reservoir_relations_public
  from public, anon, authenticated;

revoke all privileges
  on table public.water_entity_relations_public
  from public, anon, authenticated;

grant select
  on table public.water_bodies_public
  to anon, authenticated;

grant select
  on table public.water_stations_public
  to anon, authenticated;

grant select
  on table public.water_dams_public
  to anon, authenticated;

grant select
  on table public.water_reservoirs_public
  to anon, authenticated;

grant select
  on table public.dam_reservoir_relations_public
  to anon, authenticated;

grant select
  on table public.water_entity_relations_public
  to anon, authenticated;

-- Prove that W4D-2 changed only canonical identity and safe linkage.
do $postconditions$
declare
  danube_id uuid;
  baseline_snapshot_count bigint;
begin
  select snapshot_count
    into baseline_snapshot_count
  from w4d2_runtime_baseline;
  select id into danube_id
  from public.water_bodies
  where country_code = 'RO'
    and canonical_key = 'ro-danube';

  if danube_id is null then
    raise exception 'W4D-2 postcondition failed: Danube water body missing.';
  end if;

  if (
    select count(*)
    from public.water_bodies
    where country_code = 'RO'
      and type = 'branch'
      and parent_water_body_id = danube_id
  ) <> 4 then
    raise exception
      'W4D-2 postcondition failed: expected exactly four Danube branches.';
  end if;

  if (
    select count(*)
    from public.stations
    where water_body_id = danube_id
  ) <> 23 then
    raise exception
      'W4D-2 postcondition failed: expected exactly 23 canonical Danube stations.';
  end if;

  if (
    select count(*)
    from public.stations
    where water_body_id is null
  ) <> 4 then
    raise exception
      'W4D-2 postcondition failed: four legacy stations must remain unclassified.';
  end if;

  if exists (
    select 1
    from public.stations as station
    join public.water_bodies as body
      on body.id = station.water_body_id
    where body.type = 'branch'
  ) then
    raise exception
      'W4D-2 postcondition failed: a branch was incorrectly treated as a station.';
  end if;

  if (
    select count(*)
    from public.water_entity_relations
    where relation_type = 'branch_of'
      and source_water_body_id in (
        select id
        from public.water_bodies
        where parent_water_body_id = danube_id
          and type = 'branch'
      )
      and target_water_body_id = danube_id
  ) <> 4 then
    raise exception
      'W4D-2 postcondition failed: branch hierarchy relations are incomplete.';
  end if;

  if (select count(*) from public.water_station_source_mappings) <> 0 then
    raise exception
      'W4D-2 postcondition failed: source station mappings must remain empty.';
  end if;

  if (select count(*) from public.water_body_source_mappings) <> 0 then
    raise exception
      'W4D-2 postcondition failed: source water-body mappings must remain empty.';
  end if;

  if (select count(*) from public.dams) <> 0 then
    raise exception
      'W4D-2 postcondition failed: dams catalog must remain empty.';
  end if;

  if (select count(*) from public.reservoirs) <> 0 then
    raise exception
      'W4D-2 postcondition failed: reservoirs catalog must remain empty.';
  end if;

  if (select count(*) from public.dam_reservoir_relations) <> 0 then
    raise exception
      'W4D-2 postcondition failed: dam-reservoir catalog must remain empty.';
  end if;

  if (select count(*) from public.stations) <> 27 then
    raise exception
      'W4D-2 postcondition failed: station count changed.';
  end if;

  if (
    select count(*)
    from public.daily_water_snapshots
  ) <> baseline_snapshot_count then
    raise exception
      'W4D-2 postcondition failed: snapshot count changed.';
  end if;

  if (
    select count(distinct station_id)
    from public.daily_water_snapshots
  ) <> 23 then
    raise exception
      'W4D-2 postcondition failed: snapshot station identity changed.';
  end if;
end;
$postconditions$;

comment on table public.water_bodies is
  'Canonical FluviAI identity for rivers, branches, reservoirs and lakes.';

comment on column public.water_bodies.parent_water_body_id is
  'Canonical hierarchy link; W4D-2 uses it only for branch-to-river identity.';

comment on table public.water_station_source_mappings is
  'Maps one or more official provider station IDs to one canonical FluviAI station.';

comment on table public.water_body_source_mappings is
  'Maps provider water-body IDs to canonical FluviAI water bodies.';

comment on table public.water_entity_relations is
  'Typed and auditable hydrological relations across water bodies, stations, dams and reservoirs.';

comment on view public.water_bodies_public is
  'Restricted public Water API without internal provenance payloads.';

comment on view public.water_dams_public is
  'Restricted public dam API; owner and raw_payload are not exposed.';

comment on view public.water_reservoirs_public is
  'Restricted public reservoir API; owner and raw_payload are not exposed.';

comment on view public.water_entity_relations_public is
  'Restricted public hydrological-relation API; source evidence is not exposed.';

commit;