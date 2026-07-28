-- FluviAI Water Premium
-- W4C external Supabase migration draft
-- DRY-RUN ONLY: this file is not yet a repository migration.
-- No Supabase write is authorized by this document.

begin;

-- ============================================================
-- 1. DAMS
-- ============================================================

create table if not exists public.dams (
  id uuid primary key default gen_random_uuid(),

  source text not null,
  country_code text not null,
  asset_type text not null default 'dam',

  source_asset_id text not null,
  source_record_number integer not null,
  source_record_fingerprint text not null,
  source_numeric_id integer not null,
  register_id text not null,

  name text not null,
  name_en text,

  source_river_name text,
  resolved_river_name text,
  river_resolution_status text not null,

  county text,
  basin_code text,
  basin_name text,

  latitude double precision not null,
  longitude double precision not null,

  importance_class text,
  importance_category text,
  owner text,
  reservoir_type text,
  dam_type text,
  uses text,
  cadastre_code text,
  match_key text,

  canonicalization_status text not null default 'ready',
  map_eligible boolean not null default true,

  raw_payload jsonb not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint dams_source_asset_unique
    unique (source, country_code, source_asset_id),

  constraint dams_source_record_number_unique
    unique (source, country_code, source_record_number),

  constraint dams_source_record_fingerprint_unique
    unique (source, country_code, source_record_fingerprint),

  constraint dams_asset_type_check
    check (asset_type = 'dam'),

  constraint dams_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),

  constraint dams_source_not_blank_check
    check (btrim(source) <> ''),

  constraint dams_source_asset_id_not_blank_check
    check (btrim(source_asset_id) <> ''),

  constraint dams_name_not_blank_check
    check (btrim(name) <> ''),

  constraint dams_source_record_number_check
    check (source_record_number > 0),

  constraint dams_source_numeric_id_check
    check (source_numeric_id > 0),

  constraint dams_latitude_check
    check (latitude between -90.0 and 90.0),

  constraint dams_longitude_check
    check (longitude between -180.0 and 180.0),

  constraint dams_river_resolution_status_check
    check (
      river_resolution_status in (
        'source_provided',
        'manual_validated',
        'unresolved'
      )
    ),

  constraint dams_canonicalization_status_check
    check (
      canonicalization_status in (
        'ready',
        'review_required'
      )
    ),

  constraint dams_review_map_visibility_check
    check (
      canonicalization_status <> 'review_required'
      or map_eligible = false
    ),

  constraint dams_raw_payload_object_check
    check (jsonb_typeof(raw_payload) = 'object')
);

create index if not exists dams_country_map_basin_idx
  on public.dams (country_code, map_eligible, basin_code);

create index if not exists dams_river_resolution_status_idx
  on public.dams (river_resolution_status);

create index if not exists dams_map_coordinates_idx
  on public.dams (latitude, longitude)
  where map_eligible = true;

comment on table public.dams is
  'Canonical FluviAI dam catalog. Source records and provenance are preserved.';

comment on column public.dams.source_asset_id is
  'Stable asset identifier supplied by the normalized source catalog.';

comment on column public.dams.source_river_name is
  'River value preserved exactly from the normalized source record.';

comment on column public.dams.resolved_river_name is
  'Separately validated river value; never overwrites source_river_name.';

comment on column public.dams.canonicalization_status is
  'Catalog readiness state. review_required rows remain stored but hidden from the public map.';

comment on column public.dams.map_eligible is
  'Controls exposure through public read policies and map discovery.';

comment on column public.dams.raw_payload is
  'Original normalized source payload retained as JSON for provenance and audit.';


-- ============================================================
-- 2. RESERVOIRS
-- ============================================================

create table if not exists public.reservoirs (
  id uuid primary key default gen_random_uuid(),

  source text not null,
  country_code text not null,
  asset_type text not null default 'reservoir',

  source_asset_id text not null,
  source_record_number integer not null,
  source_record_fingerprint text not null,
  source_numeric_id integer not null,
  national_lake_code text not null,

  name text not null,
  alternative_name text,
  name_en text,

  source_river_name text,
  source_main_river_name text,
  resolved_river_name text,
  river_resolution_status text not null,

  county text,
  basin_code text,
  basin_name text,

  latitude double precision not null,
  longitude double precision not null,

  surface_area_km2 numeric,
  perimeter_km numeric,
  volume_million_m3 numeric,
  flood_attenuation_volume_million_m3 numeric,
  dam_height_m numeric,
  mean_depth_m numeric,
  elevation_m numeric,
  risk_index numeric,

  importance_class text,
  importance_category text,
  owner text,
  reservoir_type text,
  dam_type text,
  commissioned_year text,

  hydropower_use text,
  fishery_use text,
  water_supply_use text,
  recreation_use text,

  match_key text,

  canonicalization_status text not null default 'ready',
  map_eligible boolean not null default true,

  raw_payload jsonb not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint reservoirs_source_asset_unique
    unique (source, country_code, source_asset_id),

  constraint reservoirs_source_record_number_unique
    unique (source, country_code, source_record_number),

  constraint reservoirs_source_record_fingerprint_unique
    unique (source, country_code, source_record_fingerprint),

  constraint reservoirs_national_lake_code_unique
    unique (source, country_code, national_lake_code),

  constraint reservoirs_asset_type_check
    check (asset_type = 'reservoir'),

  constraint reservoirs_country_code_check
    check (country_code ~ '^[A-Z]{2}$'),

  constraint reservoirs_source_not_blank_check
    check (btrim(source) <> ''),

  constraint reservoirs_source_asset_id_not_blank_check
    check (btrim(source_asset_id) <> ''),

  constraint reservoirs_national_lake_code_not_blank_check
    check (btrim(national_lake_code) <> ''),

  constraint reservoirs_name_not_blank_check
    check (btrim(name) <> ''),

  constraint reservoirs_source_record_number_check
    check (source_record_number > 0),

  constraint reservoirs_source_numeric_id_check
    check (source_numeric_id > 0),

  constraint reservoirs_latitude_check
    check (latitude between -90.0 and 90.0),

  constraint reservoirs_longitude_check
    check (longitude between -180.0 and 180.0),

  constraint reservoirs_surface_area_check
    check (surface_area_km2 is null or surface_area_km2 >= 0),

  constraint reservoirs_perimeter_check
    check (perimeter_km is null or perimeter_km >= 0),

  constraint reservoirs_volume_check
    check (volume_million_m3 is null or volume_million_m3 >= 0),

  constraint reservoirs_flood_volume_check
    check (
      flood_attenuation_volume_million_m3 is null
      or flood_attenuation_volume_million_m3 >= 0
    ),

  constraint reservoirs_dam_height_check
    check (dam_height_m is null or dam_height_m >= 0),

  constraint reservoirs_mean_depth_check
    check (mean_depth_m is null or mean_depth_m >= 0),

  constraint reservoirs_risk_index_check
    check (risk_index is null or risk_index >= 0),

  constraint reservoirs_river_resolution_status_check
    check (
      river_resolution_status in (
        'source_provided',
        'manual_validated',
        'unresolved'
      )
    ),

  constraint reservoirs_canonicalization_status_check
    check (
      canonicalization_status in (
        'ready',
        'review_required'
      )
    ),

  constraint reservoirs_review_map_visibility_check
    check (
      canonicalization_status <> 'review_required'
      or map_eligible = false
    ),

  constraint reservoirs_raw_payload_object_check
    check (jsonb_typeof(raw_payload) = 'object')
);

create index if not exists reservoirs_country_map_basin_idx
  on public.reservoirs (country_code, map_eligible, basin_code);

create index if not exists reservoirs_river_resolution_status_idx
  on public.reservoirs (river_resolution_status);

create index if not exists reservoirs_map_coordinates_idx
  on public.reservoirs (latitude, longitude)
  where map_eligible = true;

comment on table public.reservoirs is
  'Canonical FluviAI reservoir and accumulation catalog with preserved source provenance.';

comment on column public.reservoirs.national_lake_code is
  'National source lake or accumulation identifier.';

comment on column public.reservoirs.source_river_name is
  'River value preserved exactly from the normalized source record.';

comment on column public.reservoirs.source_main_river_name is
  'Main-river value preserved separately from the source record.';

comment on column public.reservoirs.resolved_river_name is
  'Separately validated river value; never overwrites source river values.';

comment on column public.reservoirs.commissioned_year is
  'Preserved as text because the source includes values such as 0 and historical source formatting.';

comment on column public.reservoirs.raw_payload is
  'Original normalized source payload retained as JSON for provenance and audit.';


-- ============================================================
-- 3. DAM–RESERVOIR RELATIONS
-- ============================================================

create table if not exists public.dam_reservoir_relations (
  id uuid primary key default gen_random_uuid(),

  relation_type text not null default 'dam_reservoir',

  dam_id uuid not null,
  reservoir_id uuid not null,

  relation_origin text not null,
  match_method text not null,
  confidence text not null,
  proposal_status text not null,
  review_status text not null,
  review_reason text,
  distance_km numeric,

  map_eligible boolean not null default true,
  source text not null,
  evidence jsonb not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint dam_reservoir_relations_dam_fk
    foreign key (dam_id)
    references public.dams (id)
    on update cascade
    on delete restrict,

  constraint dam_reservoir_relations_reservoir_fk
    foreign key (reservoir_id)
    references public.reservoirs (id)
    on update cascade
    on delete restrict,

  constraint dam_reservoir_relations_pair_unique
    unique (relation_type, dam_id, reservoir_id),

  constraint dam_reservoir_relations_type_check
    check (relation_type = 'dam_reservoir'),

  constraint dam_reservoir_relations_origin_check
    check (
      relation_origin in (
        'source_confirmed',
        'manual_validated',
        'automatic_rule_qualified'
      )
    ),

  constraint dam_reservoir_relations_proposal_status_check
    check (
      proposal_status in (
        'source_confirmed',
        'manual_validated',
        'automatic_rule_qualified'
      )
    ),

  constraint dam_reservoir_relations_review_status_check
    check (
      review_status in (
        'approved',
        'rule_qualified_not_manually_verified'
      )
    ),

  constraint dam_reservoir_relations_distance_check
    check (distance_km is null or distance_km >= 0),

  constraint dam_reservoir_relations_source_not_blank_check
    check (btrim(source) <> ''),

  constraint dam_reservoir_relations_match_method_not_blank_check
    check (btrim(match_method) <> ''),

  constraint dam_reservoir_relations_confidence_not_blank_check
    check (btrim(confidence) <> ''),

  constraint dam_reservoir_relations_evidence_object_check
    check (jsonb_typeof(evidence) = 'object')
);

create index if not exists dam_reservoir_relations_dam_idx
  on public.dam_reservoir_relations (dam_id);

create index if not exists dam_reservoir_relations_reservoir_idx
  on public.dam_reservoir_relations (reservoir_id);

create index if not exists dam_reservoir_relations_origin_idx
  on public.dam_reservoir_relations (relation_origin);

create index if not exists dam_reservoir_relations_map_dam_idx
  on public.dam_reservoir_relations (dam_id, reservoir_id)
  where map_eligible = true;

comment on table public.dam_reservoir_relations is
  'Validated or rule-qualified canonical relationships between dams and reservoirs.';

comment on column public.dam_reservoir_relations.relation_origin is
  'Source-confirmed, manually validated, or automatic rule-qualified provenance class.';

comment on column public.dam_reservoir_relations.review_status is
  'Distinguishes approved relations from rule-qualified relations not manually verified.';

comment on column public.dam_reservoir_relations.evidence is
  'Structured matching evidence retained for audit and future review.';


-- ============================================================
-- 4. UPDATED_AT TRIGGERS
-- ============================================================

drop trigger if exists dams_set_updated_at
  on public.dams;

create trigger dams_set_updated_at
before update on public.dams
for each row
execute function public.set_updated_at();

drop trigger if exists reservoirs_set_updated_at
  on public.reservoirs;

create trigger reservoirs_set_updated_at
before update on public.reservoirs
for each row
execute function public.set_updated_at();

drop trigger if exists dam_reservoir_relations_set_updated_at
  on public.dam_reservoir_relations;

create trigger dam_reservoir_relations_set_updated_at
before update on public.dam_reservoir_relations
for each row
execute function public.set_updated_at();


-- ============================================================
-- 5. RLS, POLICIES AND GRANTS
-- ============================================================

alter table public.dams enable row level security;
alter table public.reservoirs enable row level security;
alter table public.dam_reservoir_relations enable row level security;

revoke all privileges on table public.dams
  from anon, authenticated;

revoke all privileges on table public.reservoirs
  from anon, authenticated;

revoke all privileges on table public.dam_reservoir_relations
  from anon, authenticated;

grant select on table public.dams
  to anon, authenticated;

grant select on table public.reservoirs
  to anon, authenticated;

grant select on table public.dam_reservoir_relations
  to anon, authenticated;

grant all privileges on table public.dams
  to service_role;

grant all privileges on table public.reservoirs
  to service_role;

grant all privileges on table public.dam_reservoir_relations
  to service_role;

drop policy if exists "dams_public_map_read"
  on public.dams;

create policy "dams_public_map_read"
on public.dams
for select
to anon, authenticated
using (map_eligible = true);

drop policy if exists "reservoirs_public_map_read"
  on public.reservoirs;

create policy "reservoirs_public_map_read"
on public.reservoirs
for select
to anon, authenticated
using (map_eligible = true);

drop policy if exists "dam_reservoir_relations_public_map_read"
  on public.dam_reservoir_relations;

create policy "dam_reservoir_relations_public_map_read"
on public.dam_reservoir_relations
for select
to anon, authenticated
using (map_eligible = true);

commit;