-- Hydro Dispatch P4 — Arges shadow foundation v1
--
-- Purpose:
--   * add a second basin without changing the current mobile/production contract;
--   * keep one app-facing identity: BARAJ;
--   * represent Arges-specific non-1:1 hydraulics in a private graph instead of
--     forcing the simpler Olt topology onto this basin;
--   * keep all Arges dispatch probabilities shadow-only until source/model and
--     calibration gates are passed.
--
-- Evidence basis (official Hidroelectrica publications):
--   - Vidraru tailrace feeds the Oiesti reservoir and the Arges cascade continues
--     downstream to Mihailesti;
--   - downstream plants include remote-dam, dam-type and diversion plants;
--   - Doamnei–Valea cu Pesti and Topolog–Cumpana are important secondary headraces;
--   - official operational listings establish the Oesti -> ... -> Golesti plant order.
--
-- This migration deliberately does NOT invent travel-time parameters.

create table if not exists public.hydro_dispatch_hydraulic_graphs (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique,
  country_code text not null check (country_code ~ '^[A-Z]{2}$'),
  basin_name text not null check (btrim(basin_name)<>''),
  name text not null check (btrim(name)<>''),
  model_scope text not null check (model_scope in ('shadow','production','national')),
  is_active boolean not null default true,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hydro_dispatch_hydraulic_nodes (
  id uuid primary key default gen_random_uuid(),
  graph_id uuid not null references public.hydro_dispatch_hydraulic_graphs(id) on delete cascade,
  canonical_key text not null,
  node_order integer not null check (node_order>0),
  node_type text not null check (node_type in ('baraj_asset','diversion_plant','transfer_inflow','junction')),
  label text not null check (btrim(label)<>''),
  baraj_id uuid references public.dams(id) on delete restrict,
  plant_id uuid references public.hydropower_plants(id) on delete restrict,
  segment_id uuid references public.water_river_segments(id) on delete restrict,
  ui_exposed boolean not null default false,
  confidence text not null check (confidence in ('high','medium','low')),
  is_active boolean not null default true,
  attributes jsonb not null default '{}'::jsonb check (jsonb_typeof(attributes)='object'),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(graph_id,canonical_key),
  unique(graph_id,node_order)
);

create table if not exists public.hydro_dispatch_hydraulic_edges (
  id uuid primary key default gen_random_uuid(),
  graph_id uuid not null references public.hydro_dispatch_hydraulic_graphs(id) on delete cascade,
  upstream_node_id uuid not null references public.hydro_dispatch_hydraulic_nodes(id) on delete cascade,
  downstream_node_id uuid not null references public.hydro_dispatch_hydraulic_nodes(id) on delete cascade,
  edge_type text not null check (edge_type in ('routing','tailrace','derivation','transfer','operational_dependency')),
  nominal_lag_minutes integer check (nominal_lag_minutes is null or nominal_lag_minutes>=0),
  lag_min_minutes integer check (lag_min_minutes is null or lag_min_minutes>=0),
  lag_max_minutes integer check (lag_max_minutes is null or lag_max_minutes>=0),
  routing_status text not null default 'unparameterized' check (routing_status in ('unparameterized','estimated','calibrated')),
  confidence text not null check (confidence in ('high','medium','low')),
  is_active boolean not null default true,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (upstream_node_id<>downstream_node_id),
  check (lag_min_minutes is null or lag_max_minutes is null or lag_max_minutes>=lag_min_minutes),
  unique(graph_id,upstream_node_id,downstream_node_id,edge_type)
);

alter table public.hydro_dispatch_hydraulic_graphs enable row level security;
alter table public.hydro_dispatch_hydraulic_nodes enable row level security;
alter table public.hydro_dispatch_hydraulic_edges enable row level security;

revoke all on public.hydro_dispatch_hydraulic_graphs from anon,authenticated;
revoke all on public.hydro_dispatch_hydraulic_nodes from anon,authenticated;
revoke all on public.hydro_dispatch_hydraulic_edges from anon,authenticated;
grant select,insert,update,delete on public.hydro_dispatch_hydraulic_graphs to service_role;
grant select,insert,update,delete on public.hydro_dispatch_hydraulic_nodes to service_role;
grant select,insert,update,delete on public.hydro_dispatch_hydraulic_edges to service_role;


do $block$
declare
  v_water_body uuid;
  v_cascade_id uuid;
  v_graph_id uuid;
  v_count integer;
begin
  select id into v_water_body
  from public.water_bodies
  where canonical_key='ro-river-v2-442147f3d93a68030c1965a2fa510880'
    and country_code='RO';

  if v_water_body is null then
    raise exception 'Arges shadow: topology-enabled canonical Arges water body missing';
  end if;

  -- Product/forecast assets: only dam-linked CHE identities. UI still exposes the
  -- linked dam name, never a separate CHE/lake identity.
  with desired(
    source_plant_id,canonical_key,plant_name,dam_name,official_name,installed_power_mw
  ) as (
    values
      ('arges-vidraru','ro:hydro-plant:arges-vidraru','Vidraru','Vidraru','Vidraru',220::numeric),
      ('arges-oesti','ro:hydro-plant:arges-oesti','Oesti','Oiesti','Oesti',null::numeric),
      ('arges-cerbureni','ro:hydro-plant:arges-cerbureni','Cerbureni','Cerbureni','Cerbureni',null::numeric),
      ('arges-curtea-de-arges','ro:hydro-plant:arges-curtea-de-arges','Curtea de Arges','Curtea de Arges','Curtea de Arges',null::numeric),
      ('arges-zigoneni','ro:hydro-plant:arges-zigoneni','Zigoneni','Zigoneni','Zigoneni',null::numeric),
      ('arges-valcele','ro:hydro-plant:arges-valcele','Valcele','Valcele','Valcele',null::numeric),
      ('arges-budeasa','ro:hydro-plant:arges-budeasa','Budeasa','Budeasa','Budeasa',null::numeric),
      ('arges-bascov','ro:hydro-plant:arges-bascov','Bascov','Bascov','Bascov',null::numeric),
      ('arges-pitesti-prundu','ro:hydro-plant:arges-pitesti-prundu','Pitesti / Prundu','Prundu','Pitesti',null::numeric),
      ('arges-golesti','ro:hydro-plant:arges-golesti','Golesti','Golesti','Golesti',null::numeric),
      ('arges-mihailesti','ro:hydro-plant:arges-mihailesti','Mihailesti','Mihailesti','Mihailesti',null::numeric)
  ), resolved as (
    select
      x.*,
      d.id as dam_id,
      d.name as canonical_dam_name,
      rel.id as relation_id,
      rel.reservoir_id
    from desired x
    join public.dams d on lower(d.name)=lower(x.dam_name)
    join public.dam_reservoir_relations rel
      on rel.dam_id=d.id and rel.confidence='high'
  )
  insert into public.hydropower_plants(
    source,country_code,source_plant_id,canonical_key,name,
    operator_name,operator_unit,sector_name,water_body_id,dam_id,reservoir_id,
    plant_kind,installed_power_mw,location_method,canonicalization_status,map_eligible,
    source_url,source_evidence
  )
  select
    'HIDROELECTRICA_OFFICIAL','RO',r.source_plant_id,r.canonical_key,r.plant_name,
    'Hidroelectrica S.A.','SH Curtea de Arges','Arges — Vidraru to Mihailesti (shadow)',
    v_water_body,r.dam_id,r.reservoir_id,'hydroelectric_power_plant',r.installed_power_mw,
    'linked_dam_coordinate','ready',true,
    'https://cdn.hidroelectrica.ro/cdn/Raport_cauze_insolventa.pdf',
    jsonb_build_object(
      'policy_version','arges_shadow_official_v1',
      'official_listing',true,
      'official_plant_name',r.official_name,
      'ui_identity','BARAJ',
      'ui_baraj_name',r.canonical_dam_name,
      'dam_reservoir_relation_id',r.relation_id,
      'location_semantics','linked dam coordinate; technical CHE location is not asserted',
      'operation_semantics','UNKNOWN until current evidence exists',
      'dispatch_scope','shadow_only',
      'source_notes','Arges contains dam-type, remote-dam and diversion plants; this record is a dam-linked forecast asset, not the complete hydraulic graph.'
    )
  from resolved r
  on conflict (canonical_key) do update
  set source=excluded.source,
      source_plant_id=excluded.source_plant_id,
      name=excluded.name,
      operator_name=excluded.operator_name,
      operator_unit=excluded.operator_unit,
      sector_name=excluded.sector_name,
      water_body_id=excluded.water_body_id,
      dam_id=excluded.dam_id,
      reservoir_id=excluded.reservoir_id,
      plant_kind=excluded.plant_kind,
      installed_power_mw=coalesce(excluded.installed_power_mw,public.hydropower_plants.installed_power_mw),
      location_method=excluded.location_method,
      canonicalization_status=excluded.canonicalization_status,
      map_eligible=excluded.map_eligible,
      source_url=excluded.source_url,
      source_evidence=excluded.source_evidence,
      updated_at=now();

  select count(*)::integer into v_count
  from public.hydropower_plants
  where canonical_key in (
    'ro:hydro-plant:arges-vidraru','ro:hydro-plant:arges-oesti',
    'ro:hydro-plant:arges-cerbureni','ro:hydro-plant:arges-curtea-de-arges',
    'ro:hydro-plant:arges-zigoneni','ro:hydro-plant:arges-valcele',
    'ro:hydro-plant:arges-budeasa','ro:hydro-plant:arges-bascov',
    'ro:hydro-plant:arges-pitesti-prundu','ro:hydro-plant:arges-golesti',
    'ro:hydro-plant:arges-mihailesti'
  );
  if v_count<>11 then
    raise exception 'Arges shadow: expected 11 dam-linked hydropower assets, got %',v_count;
  end if;

  insert into public.hydro_dispatch_cascades(
    canonical_key,country_code,name,water_body_id,
    start_sequence_number,end_sequence_number,model_scope,is_active,provenance
  ) values (
    'ro:arges:vidraru-mihailesti-shadow-v1','RO','Arges — Vidraru to Mihailesti BARAJ spine (shadow)',
    v_water_body,6,68,'shadow',true,
    jsonb_build_object(
      'policy_version','arges_baraj_spine_shadow_v1',
      'shadow_only',true,
      'ui_identity','BARAJ',
      'baraj_spine_only',true,
      'full_hydraulic_graph_key','ro:arges:vidraru-mihailesti-hydraulic-shadow-v1',
      'topology_source','ANAR canonical Arges segment sequence',
      'official_source','Hidroelectrica official Curtea de Arges / Arges cascade publications',
      'production_contract_changed',false
    )
  )
  on conflict (canonical_key) do update
  set name=excluded.name,
      water_body_id=excluded.water_body_id,
      start_sequence_number=excluded.start_sequence_number,
      end_sequence_number=excluded.end_sequence_number,
      model_scope=excluded.model_scope,
      is_active=excluded.is_active,
      provenance=excluded.provenance,
      updated_at=now()
  returning id into v_cascade_id;

  with desired(node_order,plant_key,sequence_number,node_confidence) as (
    values
      (1,'ro:hydro-plant:arges-vidraru',6,'high'),
      (2,'ro:hydro-plant:arges-oesti',13,'high'),
      (3,'ro:hydro-plant:arges-cerbureni',17,'high'),
      (4,'ro:hydro-plant:arges-curtea-de-arges',23,'high'),
      (5,'ro:hydro-plant:arges-zigoneni',29,'high'),
      (6,'ro:hydro-plant:arges-valcele',34,'high'),
      (7,'ro:hydro-plant:arges-budeasa',39,'high'),
      (8,'ro:hydro-plant:arges-bascov',43,'high'),
      (9,'ro:hydro-plant:arges-pitesti-prundu',49,'medium'),
      (10,'ro:hydro-plant:arges-golesti',52,'high'),
      (11,'ro:hydro-plant:arges-mihailesti',68,'high')
  ), resolved as (
    select
      x.*,
      h.id as plant_id,h.dam_id,h.reservoir_id,
      s.id as segment_id,s.segment_code
    from desired x
    join public.hydropower_plants h on h.canonical_key=x.plant_key
    join public.water_river_segments s
      on s.parent_water_body_id=v_water_body and s.sequence_number=x.sequence_number
  )
  insert into public.hydro_dispatch_cascade_nodes(
    cascade_id,node_order,plant_id,dam_id,reservoir_id,
    segment_id,segment_code,sequence_number,confidence,evidence
  )
  select
    v_cascade_id,r.node_order,r.plant_id,r.dam_id,r.reservoir_id,
    r.segment_id,r.segment_code,r.sequence_number,r.node_confidence,
    jsonb_build_object(
      'policy_version','arges_baraj_spine_shadow_v1',
      'shadow_only',true,
      'ui_identity','BARAJ',
      'baraj_spine_only',true,
      'canonical_arges_sequence',r.sequence_number,
      'hydraulic_graph_required',true,
      'travel_time_status','unparameterized'
    )
  from resolved r
  on conflict (cascade_id,plant_id) do update
  set node_order=excluded.node_order,
      dam_id=excluded.dam_id,
      reservoir_id=excluded.reservoir_id,
      segment_id=excluded.segment_id,
      segment_code=excluded.segment_code,
      sequence_number=excluded.sequence_number,
      confidence=excluded.confidence,
      evidence=excluded.evidence,
      updated_at=now();

  delete from public.hydro_dispatch_cascade_nodes n
  where n.cascade_id=v_cascade_id
    and not exists (
      select 1
      from public.hydropower_plants h
      where h.id=n.plant_id
        and h.canonical_key in (
          'ro:hydro-plant:arges-vidraru','ro:hydro-plant:arges-oesti',
          'ro:hydro-plant:arges-cerbureni','ro:hydro-plant:arges-curtea-de-arges',
          'ro:hydro-plant:arges-zigoneni','ro:hydro-plant:arges-valcele',
          'ro:hydro-plant:arges-budeasa','ro:hydro-plant:arges-bascov',
          'ro:hydro-plant:arges-pitesti-prundu','ro:hydro-plant:arges-golesti',
          'ro:hydro-plant:arges-mihailesti'
        )
    );

  select count(*)::integer into v_count
  from public.hydro_dispatch_cascade_nodes
  where cascade_id=v_cascade_id;
  if v_count<>11 then
    raise exception 'Arges shadow: expected 11 BARAJ spine nodes, got %',v_count;
  end if;

  -- Private hydraulic graph. The six diversion plants are intentionally technical
  -- nodes only: they are not separate mobile identities and are not yet forecast assets.
  insert into public.hydro_dispatch_hydraulic_graphs(
    canonical_key,country_code,basin_name,name,model_scope,is_active,provenance
  ) values (
    'ro:arges:vidraru-mihailesti-hydraulic-shadow-v1','RO','Arges',
    'Arges — Vidraru to Mihailesti hydraulic graph (shadow)','shadow',true,
    jsonb_build_object(
      'policy_version','arges_hydraulic_graph_shadow_v1',
      'shadow_only',true,
      'ui_identity','BARAJ',
      'official_evidence',jsonb_build_array(
        'Hidroelectrica Vidraru/cascade technical description',
        'Hidroelectrica SH Curtea de Arges operational listings'
      ),
      'travel_time_status','unparameterized',
      'accuracy_claim',false,
      'side_scheme_note','Cumpana, Valsan and Calugarita are not yet represented as separate dispatch assets.'
    )
  )
  on conflict (canonical_key) do update
  set name=excluded.name,
      model_scope=excluded.model_scope,
      is_active=excluded.is_active,
      provenance=excluded.provenance,
      updated_at=now()
  returning id into v_graph_id;

  with desired(
    node_order,node_key,node_type,label,plant_key,dam_name,sequence_number,ui_exposed,node_confidence,attributes
  ) as (
    values
      (1,'transfer-doamnei-valea-cu-pesti','transfer_inflow','Doamnei - Valea cu Pesti',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','secondary_headrace')),
      (2,'transfer-topolog-cumpana','transfer_inflow','Topolog - Cumpana',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','secondary_headrace')),
      (3,'vidraru','baraj_asset','Vidraru','ro:hydro-plant:arges-vidraru','Vidraru',6,true,'high',jsonb_build_object('role','storage_peak_upstream_anchor','turbine_family','Francis','installed_power_mw',220)),
      (4,'oesti','baraj_asset','Oesti / Baraj Oiesti','ro:hydro-plant:arges-oesti','Oiesti',13,true,'high',jsonb_build_object('role','remote_dam_plant')),
      (5,'albesti','diversion_plant','Albesti',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','diversion_plant')),
      (6,'cerbureni','baraj_asset','Cerbureni','ro:hydro-plant:arges-cerbureni','Cerbureni',17,true,'high',jsonb_build_object('role','remote_dam_plant')),
      (7,'valea-iasului','diversion_plant','Valea Iasului',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','diversion_plant')),
      (8,'curtea-de-arges','baraj_asset','Curtea de Arges','ro:hydro-plant:arges-curtea-de-arges','Curtea de Arges',23,true,'high',jsonb_build_object('role','dam_type_plant')),
      (9,'noaptes','diversion_plant','Noaptes',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','diversion_plant')),
      (10,'zigoneni','baraj_asset','Zigoneni','ro:hydro-plant:arges-zigoneni','Zigoneni',29,true,'high',jsonb_build_object('role','dam_type_plant')),
      (11,'baiculesti','diversion_plant','Baiculesti',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','diversion_plant')),
      (12,'manicesti','diversion_plant','Manicesti',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','diversion_plant')),
      (13,'valcele','baraj_asset','Valcele','ro:hydro-plant:arges-valcele','Valcele',34,true,'high',jsonb_build_object('role','dam_type_plant')),
      (14,'merisani','diversion_plant','Merisani',null::text,null::text,null::integer,false,'medium',jsonb_build_object('role','diversion_plant')),
      (15,'budeasa','baraj_asset','Budeasa','ro:hydro-plant:arges-budeasa','Budeasa',39,true,'high',jsonb_build_object('role','dam_type_plant')),
      (16,'bascov','baraj_asset','Bascov','ro:hydro-plant:arges-bascov','Bascov',43,true,'high',jsonb_build_object('role','dam_type_plant')),
      (17,'pitesti-prundu','baraj_asset','Pitesti / Baraj Prundu','ro:hydro-plant:arges-pitesti-prundu','Prundu',49,true,'medium',jsonb_build_object('role','dam_type_plant','ui_name','Prundu','technical_alias','Pitesti')),
      (18,'golesti','baraj_asset','Golesti','ro:hydro-plant:arges-golesti','Golesti',52,true,'high',jsonb_build_object('role','dam_type_plant')),
      (19,'mihailesti','baraj_asset','Mihailesti','ro:hydro-plant:arges-mihailesti','Mihailesti',68,true,'high',jsonb_build_object('role','dam_type_plant','downstream_anchor',true))
  ), resolved as (
    select
      x.*,
      h.id as plant_id,
      d.id as dam_id,
      s.id as segment_id
    from desired x
    left join public.hydropower_plants h on h.canonical_key=x.plant_key
    left join public.dams d on lower(d.name)=lower(x.dam_name)
    left join public.water_river_segments s
      on s.parent_water_body_id=v_water_body and s.sequence_number=x.sequence_number
  )
  insert into public.hydro_dispatch_hydraulic_nodes(
    graph_id,canonical_key,node_order,node_type,label,
    baraj_id,plant_id,segment_id,ui_exposed,confidence,is_active,attributes,evidence
  )
  select
    v_graph_id,r.node_key,r.node_order,r.node_type,r.label,
    r.dam_id,r.plant_id,r.segment_id,r.ui_exposed,r.node_confidence,true,r.attributes,
    jsonb_build_object(
      'policy_version','arges_hydraulic_graph_shadow_v1',
      'shadow_only',true,
      'official_order',true,
      'exact_travel_time_known',false,
      'source_url','https://cdn.hidroelectrica.ro/cdn/Raport_cauze_insolventa.pdf'
    )
  from resolved r
  on conflict (graph_id,canonical_key) do update
  set node_order=excluded.node_order,
      node_type=excluded.node_type,
      label=excluded.label,
      baraj_id=excluded.baraj_id,
      plant_id=excluded.plant_id,
      segment_id=excluded.segment_id,
      ui_exposed=excluded.ui_exposed,
      confidence=excluded.confidence,
      is_active=excluded.is_active,
      attributes=excluded.attributes,
      evidence=excluded.evidence,
      updated_at=now();

  delete from public.hydro_dispatch_hydraulic_nodes n
  where n.graph_id=v_graph_id
    and n.canonical_key not in (
      'transfer-doamnei-valea-cu-pesti','transfer-topolog-cumpana','vidraru','oesti','albesti',
      'cerbureni','valea-iasului','curtea-de-arges','noaptes','zigoneni','baiculesti',
      'manicesti','valcele','merisani','budeasa','bascov','pitesti-prundu','golesti','mihailesti'
    );

  select count(*)::integer into v_count
  from public.hydro_dispatch_hydraulic_nodes
  where graph_id=v_graph_id;
  if v_count<>19 then
    raise exception 'Arges hydraulic graph: expected 19 nodes, got %',v_count;
  end if;

  -- Rebuild only this private graph's edges. No lag is guessed; routing calibration
  -- is a later gate based on observations/backtesting.
  delete from public.hydro_dispatch_hydraulic_edges where graph_id=v_graph_id;

  with desired(up_key,down_key,edge_type,edge_confidence) as (
    values
      ('transfer-doamnei-valea-cu-pesti','vidraru','transfer','medium'),
      ('transfer-topolog-cumpana','vidraru','transfer','medium'),
      ('vidraru','oesti','tailrace','high'),
      ('oesti','albesti','routing','medium'),
      ('albesti','cerbureni','routing','medium'),
      ('cerbureni','valea-iasului','routing','medium'),
      ('valea-iasului','curtea-de-arges','routing','medium'),
      ('curtea-de-arges','noaptes','routing','medium'),
      ('noaptes','zigoneni','routing','medium'),
      ('zigoneni','baiculesti','routing','medium'),
      ('baiculesti','manicesti','routing','medium'),
      ('manicesti','valcele','routing','medium'),
      ('valcele','merisani','routing','medium'),
      ('merisani','budeasa','routing','medium'),
      ('budeasa','bascov','routing','medium'),
      ('bascov','pitesti-prundu','routing','medium'),
      ('pitesti-prundu','golesti','routing','medium'),
      ('golesti','mihailesti','routing','medium')
  )
  insert into public.hydro_dispatch_hydraulic_edges(
    graph_id,upstream_node_id,downstream_node_id,edge_type,
    nominal_lag_minutes,lag_min_minutes,lag_max_minutes,routing_status,confidence,is_active,evidence
  )
  select
    v_graph_id,u.id,d.id,x.edge_type,
    null,null,null,'unparameterized',x.edge_confidence,true,
    jsonb_build_object(
      'policy_version','arges_hydraulic_graph_shadow_v1',
      'shadow_only',true,
      'ordering_supported',true,
      'lag_supported',false,
      'source_url','https://cdn.hidroelectrica.ro/cdn/Raport_cauze_insolventa.pdf'
    )
  from desired x
  join public.hydro_dispatch_hydraulic_nodes u
    on u.graph_id=v_graph_id and u.canonical_key=x.up_key
  join public.hydro_dispatch_hydraulic_nodes d
    on d.graph_id=v_graph_id and d.canonical_key=x.down_key;

  select count(*)::integer into v_count
  from public.hydro_dispatch_hydraulic_edges
  where graph_id=v_graph_id;
  if v_count<>18 then
    raise exception 'Arges hydraulic graph: expected 18 edges, got %',v_count;
  end if;
end;
$block$;


create or replace function public.get_hydro_dispatch_arges_shadow_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=public,auth,pg_temp
as $function$
declare
  v_role text;
  v_graph_id uuid;
  v_cascade_id uuid;
  v_baraj_assets integer:=0;
  v_graph_nodes integer:=0;
  v_graph_edges integer:=0;
  v_diversion_nodes integer:=0;
  v_transfer_nodes integer:=0;
  v_parameterized_edges integer:=0;
  v_national_assets integer:=0;
  v_arges_observations integer:=0;
  v_arges_stations integer:=0;
begin
  v_role:=coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    auth.jwt()->>'role',
    case when session_user in ('service_role','postgres') then session_user end
  );
  if v_role not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select id into v_cascade_id
  from public.hydro_dispatch_cascades
  where canonical_key='ro:arges:vidraru-mihailesti-shadow-v1' and is_active=true;

  select id into v_graph_id
  from public.hydro_dispatch_hydraulic_graphs
  where canonical_key='ro:arges:vidraru-mihailesti-hydraulic-shadow-v1' and is_active=true;

  select count(*)::integer into v_baraj_assets
  from public.hydro_dispatch_cascade_nodes
  where cascade_id=v_cascade_id;

  select
    count(*)::integer,
    count(*) filter(where node_type='diversion_plant')::integer,
    count(*) filter(where node_type='transfer_inflow')::integer
  into v_graph_nodes,v_diversion_nodes,v_transfer_nodes
  from public.hydro_dispatch_hydraulic_nodes
  where graph_id=v_graph_id and is_active=true;

  select
    count(*)::integer,
    count(*) filter(where routing_status in ('estimated','calibrated'))::integer
  into v_graph_edges,v_parameterized_edges
  from public.hydro_dispatch_hydraulic_edges
  where graph_id=v_graph_id and is_active=true;

  select count(*)::integer into v_national_assets
  from public.get_hydro_dispatch_active_assets_v1();

  select count(*)::integer into v_arges_observations
  from public.water_operational_observations o
  where o.water_body_id=(select id from public.water_bodies where canonical_key='ro-river-v2-442147f3d93a68030c1965a2fa510880')
     or o.dam_id in (
       select n.dam_id from public.hydro_dispatch_cascade_nodes n where n.cascade_id=v_cascade_id and n.dam_id is not null
     )
     or o.reservoir_id in (
       select n.reservoir_id from public.hydro_dispatch_cascade_nodes n where n.cascade_id=v_cascade_id and n.reservoir_id is not null
     );

  select count(*)::integer into v_arges_stations
  from public.stations s
  where s.water_body_id=(select id from public.water_bodies where canonical_key='ro-river-v2-442147f3d93a68030c1965a2fa510880')
     or lower(coalesce(s.river,'')) in ('arges','argeș');

  return jsonb_build_object(
    'schema_version','1.0.0',
    'checked_at',clock_timestamp(),
    'basin','Arges',
    'shadow_only',true,
    'ui_identity','BARAJ',
    'baraj_forecast_assets',v_baraj_assets,
    'hydraulic_graph_nodes',v_graph_nodes,
    'hydraulic_graph_edges',v_graph_edges,
    'hidden_diversion_nodes',v_diversion_nodes,
    'secondary_transfer_nodes',v_transfer_nodes,
    'parameterized_routing_edges',v_parameterized_edges,
    'national_shadow_assets_after_arges',v_national_assets,
    'local_operational_observations',v_arges_observations,
    'canonical_live_stations',v_arges_stations,
    'routing_state',case when v_parameterized_edges=v_graph_edges and v_graph_edges>0 then 'parameterized' else 'unparameterized' end,
    'accuracy_state','topology_shadow_only',
    'dispatch_supported',false,
    'production_contract_changed',false
  );
end;
$function$;

revoke all on function public.get_hydro_dispatch_arges_shadow_health_v1() from public;
grant execute on function public.get_hydro_dispatch_arges_shadow_health_v1() to service_role;

comment on function public.get_hydro_dispatch_arges_shadow_health_v1() is
'Private Arges shadow topology/coverage health. Does not imply calibrated dispatch accuracy or production support.';
