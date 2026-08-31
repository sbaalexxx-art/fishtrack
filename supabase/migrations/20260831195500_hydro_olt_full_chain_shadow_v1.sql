-- Hydro Dispatch P1.1 — Olt full-chain shadow v1
--
-- Preserve the current 15-node production pilot unchanged. Add a separate 25-node
-- Olt shadow topology, backed by official Hidroelectrica ordering and canonical ANAR
-- segment sequence numbers. National shadow selection deduplicates plants and prefers
-- national/production/shadow configuration over the legacy pilot. App-facing
-- dispatch_supported remains false for shadow-only BARAJE.

create or replace function public.get_hydro_dispatch_active_assets_v1()
returns table(
  cascade_id uuid,
  cascade_key text,
  cascade_name text,
  model_scope text,
  node_order integer,
  plant_id uuid,
  plant_key text,
  plant_name text,
  baraj_id uuid,
  baraj_name text,
  reservoir_id uuid,
  reservoir_name text,
  water_body_id uuid,
  basin_name text,
  river_name text,
  latitude double precision,
  longitude double precision,
  canonicalization_status text,
  map_eligible boolean
)
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
  with candidates as (
    select
      c.id as cascade_id,
      c.canonical_key as cascade_key,
      c.name as cascade_name,
      c.model_scope,
      n.node_order,
      h.id as plant_id,
      h.canonical_key as plant_key,
      h.name as plant_name,
      h.dam_id as baraj_id,
      coalesce(d.name,h.name) as baraj_name,
      h.reservoir_id,
      r.name as reservoir_name,
      h.water_body_id,
      coalesce(d.basin_name,r.basin_name) as basin_name,
      coalesce(d.resolved_river_name,d.source_river_name,r.resolved_river_name,r.source_river_name) as river_name,
      coalesce(d.latitude,r.latitude) as latitude,
      coalesce(d.longitude,r.longitude) as longitude,
      h.canonicalization_status,
      h.map_eligible,
      row_number() over (
        partition by h.id
        order by
          case c.model_scope
            when 'national' then 0
            when 'production' then 1
            when 'shadow' then 2
            when 'pilot' then 3
            else 4
          end,
          c.updated_at desc,
          c.canonical_key
      ) as preferred_rank
    from public.hydro_dispatch_cascades c
    join public.hydro_dispatch_cascade_nodes n on n.cascade_id=c.id
    join public.hydropower_plants h on h.id=n.plant_id
    left join public.dams d on d.id=h.dam_id
    left join public.reservoirs r on r.id=h.reservoir_id
    where c.is_active=true
      and h.country_code='RO'
      and h.canonicalization_status='ready'
  )
  select
    cascade_id,cascade_key,cascade_name,model_scope,node_order,
    plant_id,plant_key,plant_name,baraj_id,baraj_name,
    reservoir_id,reservoir_name,water_body_id,basin_name,river_name,
    latitude,longitude,canonicalization_status,map_eligible
  from candidates
  where preferred_rank=1
  order by cascade_key,node_order,plant_id;
$function$;

revoke all on function public.get_hydro_dispatch_active_assets_v1() from public;
grant execute on function public.get_hydro_dispatch_active_assets_v1() to service_role;


create or replace function public.get_hydro_dispatch_baraj_registry_v1(
  p_country_code text default 'RO'
)
returns table(
  baraj_id uuid,
  baraj_name text,
  country_code text,
  basin_name text,
  river_name text,
  county text,
  latitude double precision,
  longitude double precision,
  reservoir_id uuid,
  reservoir_name text,
  water_body_id uuid,
  hydro_plant_ids uuid[],
  hydro_plant_names text[],
  operator_names text[],
  engine_configured boolean,
  dispatch_supported boolean,
  map_eligible boolean
)
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
  with plants as (
    select
      h.*,
      d.name as dam_name,
      d.basin_name as dam_basin_name,
      d.resolved_river_name as dam_resolved_river_name,
      d.source_river_name as dam_source_river_name,
      d.county as dam_county,
      d.latitude as dam_latitude,
      d.longitude as dam_longitude,
      d.map_eligible as dam_map_eligible,
      r.name as linked_reservoir_name,
      exists (
        select 1
        from public.hydro_dispatch_cascade_nodes n
        join public.hydro_dispatch_cascades c on c.id=n.cascade_id
        where n.plant_id=h.id and c.is_active=true
      ) as configured_any,
      exists (
        select 1
        from public.hydro_dispatch_cascade_nodes n
        join public.hydro_dispatch_cascades c on c.id=n.cascade_id
        where n.plant_id=h.id
          and c.is_active=true
          and c.model_scope in ('pilot','production','national')
      ) as configured_product
    from public.hydropower_plants h
    left join public.dams d on d.id=h.dam_id
    left join public.reservoirs r on r.id=h.reservoir_id
    where h.country_code=upper(coalesce(nullif(trim(p_country_code),''),'RO'))
      and h.canonicalization_status='ready'
      and h.dam_id is not null
  )
  select
    p.dam_id as baraj_id,
    coalesce(max(p.dam_name),min(p.name)) as baraj_name,
    min(p.country_code) as country_code,
    max(p.dam_basin_name) as basin_name,
    coalesce(max(p.dam_resolved_river_name),max(p.dam_source_river_name)) as river_name,
    max(p.dam_county) as county,
    max(p.dam_latitude) as latitude,
    max(p.dam_longitude) as longitude,
    (array_agg(p.reservoir_id order by p.name) filter (where p.reservoir_id is not null))[1] as reservoir_id,
    (array_agg(p.linked_reservoir_name order by p.name) filter (where p.linked_reservoir_name is not null))[1] as reservoir_name,
    (array_agg(p.water_body_id order by p.name) filter (where p.water_body_id is not null))[1] as water_body_id,
    array_agg(p.id order by p.name,p.id) as hydro_plant_ids,
    array_agg(p.name order by p.name,p.id) as hydro_plant_names,
    array_remove(array_agg(distinct p.operator_name),null) as operator_names,
    bool_or(p.configured_any) as engine_configured,
    bool_or(p.configured_product) as dispatch_supported,
    bool_or(p.map_eligible and coalesce(p.dam_map_eligible,true)) as map_eligible
  from plants p
  group by p.dam_id
  order by coalesce(max(p.dam_basin_name),''),coalesce(max(p.dam_name),min(p.name)),p.dam_id;
$function$;

revoke all on function public.get_hydro_dispatch_baraj_registry_v1(text) from public;
grant execute on function public.get_hydro_dispatch_baraj_registry_v1(text) to anon, authenticated, service_role;


-- Full Olt ordering verified against official Hidroelectrica publications and the
-- canonical ANAR Olt sequence. The existing pilot begins at Râmnicu Vâlcea (seq 175).
do $block$
declare
  v_water_body uuid;
  v_cascade_id uuid;
  v_match_count integer;
  v_node_count integer;
begin
  select water_body_id into v_water_body
  from public.hydropower_plants
  where canonical_key='ro:hydro-plant:olt-voila'
    and country_code='RO'
    and canonicalization_status='ready';

  if v_water_body is null then
    raise exception 'Olt full-chain shadow: canonical Olt water body missing';
  end if;

  insert into public.hydro_dispatch_cascades(
    canonical_key,country_code,name,water_body_id,
    start_sequence_number,end_sequence_number,model_scope,is_active,provenance
  ) values (
    'ro:olt:full-chain-shadow-v1','RO','Olt — Voila to Izbiceni (full-chain shadow)',v_water_body,
    101,238,'shadow',true,
    jsonb_build_object(
      'policy_version','olt_full_chain_shadow_v1',
      'shadow_only',true,
      'official_order_sources',jsonb_build_array(
        'Hidroelectrica SEICA AHE Olt CA',
        'Hidroelectrica Annual Report 2024',
        'Hidroelectrica official Olt development documentation'
      ),
      'topology_source','ANAR canonical Olt segment sequence',
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
      (1 ,'ro:hydro-plant:olt-voila',101,'medium'),
      (2 ,'ro:hydro-plant:olt-vistea',108,'medium'),
      (3 ,'ro:hydro-plant:olt-arpasu',120,'medium'),
      (4 ,'ro:hydro-plant:olt-scoreiu',126,'medium'),
      (5 ,'ro:hydro-plant:olt-avrig',131,'medium'),
      (6 ,'ro:hydro-plant:olt-cornetu',151,'medium'),
      (7 ,'ro:hydro-plant:olt-gura-lotrului',157,'medium'),
      (8 ,'ro:hydro-plant:olt-turnu',161,'medium'),
      (9 ,'ro:hydro-plant:olt-calimanesti',165,'medium'),
      (10,'ro:hydro-plant:olt-daesti',169,'medium'),
      (11,'ro:hydro-plant:olt-ramnicu-valcea',175,'high'),
      (12,'ro:hydro-plant:olt-raureni',177,'high'),
      (13,'ro:hydro-plant:olt-govora',183,'high'),
      (14,'ro:hydro-plant:olt-babeni',189,'high'),
      (15,'ro:hydro-plant:olt-ionesti',196,'high'),
      (16,'ro:hydro-plant:olt-zavideni',200,'high'),
      (17,'ro:hydro-plant:olt-dragasani',205,'high'),
      (18,'ro:hydro-plant:olt-strejesti',210,'high'),
      (19,'ro:hydro-plant:olt-arcesti',214,'high'),
      (20,'ro:hydro-plant:olt-slatina',218,'high'),
      (21,'ro:hydro-plant:olt-ipotesti',224,'high'),
      (22,'ro:hydro-plant:olt-draganesti',229,'high'),
      (23,'ro:hydro-plant:olt-frunzaru',232,'high'),
      (24,'ro:hydro-plant:olt-rusanesti',236,'high'),
      (25,'ro:hydro-plant:olt-izbiceni',238,'high')
  ), resolved as (
    select d.node_order,d.plant_key,d.sequence_number,d.node_confidence,
           h.id as plant_id,h.dam_id,h.reservoir_id,h.water_body_id,
           s.id as segment_id,s.segment_code,s.topology_status,s.source_direction_validated
    from desired d
    join public.hydropower_plants h
      on h.canonical_key=d.plant_key
     and h.country_code='RO'
     and h.canonicalization_status='ready'
    join public.water_river_segments s
      on s.parent_water_body_id=h.water_body_id
     and s.sequence_number=d.sequence_number
  )
  select count(*)::integer into v_match_count from resolved;

  if v_match_count<>25 then
    raise exception 'Olt full-chain shadow resolved %/25 canonical plant-segment pairs',v_match_count;
  end if;

  with desired(node_order,plant_key,sequence_number,node_confidence) as (
    values
      (1 ,'ro:hydro-plant:olt-voila',101,'medium'),
      (2 ,'ro:hydro-plant:olt-vistea',108,'medium'),
      (3 ,'ro:hydro-plant:olt-arpasu',120,'medium'),
      (4 ,'ro:hydro-plant:olt-scoreiu',126,'medium'),
      (5 ,'ro:hydro-plant:olt-avrig',131,'medium'),
      (6 ,'ro:hydro-plant:olt-cornetu',151,'medium'),
      (7 ,'ro:hydro-plant:olt-gura-lotrului',157,'medium'),
      (8 ,'ro:hydro-plant:olt-turnu',161,'medium'),
      (9 ,'ro:hydro-plant:olt-calimanesti',165,'medium'),
      (10,'ro:hydro-plant:olt-daesti',169,'medium'),
      (11,'ro:hydro-plant:olt-ramnicu-valcea',175,'high'),
      (12,'ro:hydro-plant:olt-raureni',177,'high'),
      (13,'ro:hydro-plant:olt-govora',183,'high'),
      (14,'ro:hydro-plant:olt-babeni',189,'high'),
      (15,'ro:hydro-plant:olt-ionesti',196,'high'),
      (16,'ro:hydro-plant:olt-zavideni',200,'high'),
      (17,'ro:hydro-plant:olt-dragasani',205,'high'),
      (18,'ro:hydro-plant:olt-strejesti',210,'high'),
      (19,'ro:hydro-plant:olt-arcesti',214,'high'),
      (20,'ro:hydro-plant:olt-slatina',218,'high'),
      (21,'ro:hydro-plant:olt-ipotesti',224,'high'),
      (22,'ro:hydro-plant:olt-draganesti',229,'high'),
      (23,'ro:hydro-plant:olt-frunzaru',232,'high'),
      (24,'ro:hydro-plant:olt-rusanesti',236,'high'),
      (25,'ro:hydro-plant:olt-izbiceni',238,'high')
  ), resolved as (
    select d.node_order,d.sequence_number,d.node_confidence,
           h.id as plant_id,h.name as plant_name,h.dam_id,h.reservoir_id,
           s.id as segment_id,s.segment_code,s.topology_status,s.source_direction_validated
    from desired d
    join public.hydropower_plants h
      on h.canonical_key=d.plant_key
     and h.country_code='RO'
     and h.canonicalization_status='ready'
    join public.water_river_segments s
      on s.parent_water_body_id=h.water_body_id
     and s.sequence_number=d.sequence_number
  )
  insert into public.hydro_dispatch_cascade_nodes(
    cascade_id,node_order,plant_id,dam_id,reservoir_id,
    segment_id,segment_code,sequence_number,confidence,evidence
  )
  select
    v_cascade_id,r.node_order,r.plant_id,r.dam_id,r.reservoir_id,
    r.segment_id,r.segment_code,r.sequence_number,r.node_confidence,
    jsonb_build_object(
      'policy_version','olt_full_chain_shadow_v1',
      'shadow_only',true,
      'plant_name',r.plant_name,
      'official_order_verified',true,
      'anar_sequence_number',r.sequence_number,
      'segment_topology_status',r.topology_status,
      'source_direction_validated',coalesce(r.source_direction_validated,false),
      'link_method',case when r.node_order<=10 then 'official_order_plus_canonical_segment_sequence' else 'existing_pilot_order_plus_canonical_segment_sequence' end,
      'production_contract_changed',false
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

  select count(*)::integer into v_node_count
  from public.hydro_dispatch_cascade_nodes
  where cascade_id=v_cascade_id;

  if v_node_count<>25 then
    raise exception 'Olt full-chain shadow contains %/25 nodes after upsert',v_node_count;
  end if;
end;
$block$;


create or replace function public.get_hydro_dispatch_national_foundation_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_role text;
  v_baraje integer := 0;
  v_configured_baraje integer := 0;
  v_supported_baraje integer := 0;
  v_unconfigured_baraje integer := 0;
  v_active_assets integer := 0;
  v_active_cascades integer := 0;
  v_last_run uuid;
  v_last_run_at timestamptz;
  v_last_date date;
  v_values integer := 0;
  v_expected integer := 0;
begin
  v_role := coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    auth.jwt()->>'role',
    case when session_user in ('service_role','postgres') then session_user end
  );
  if v_role not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select count(*)::integer,
         count(*) filter(where engine_configured)::integer,
         count(*) filter(where dispatch_supported)::integer,
         count(*) filter(where not engine_configured)::integer
    into v_baraje,v_configured_baraje,v_supported_baraje,v_unconfigured_baraje
  from public.get_hydro_dispatch_baraj_registry_v1('RO');

  select count(*)::integer,count(distinct cascade_id)::integer
    into v_active_assets,v_active_cascades
  from public.get_hydro_dispatch_active_assets_v1();

  select r.id,r.run_at,(v.valid_at at time zone 'Europe/Bucharest')::date
    into v_last_run,v_last_run_at,v_last_date
  from public.water_forecast_runs r
  join public.water_forecast_values v on v.forecast_run_id=r.id
  where r.country_code='RO'
    and r.model_key='hydro_dispatch_ro_national_market_shadow_v1'
    and v.metric_code='hydro_dispatch_probability'
  order by r.run_at desc,r.created_at desc
  limit 1;

  if v_last_run is not null then
    select count(*)::integer into v_values
    from public.water_forecast_values v
    where v.forecast_run_id=v_last_run
      and v.metric_code='hydro_dispatch_probability';
    v_expected := (
      extract(epoch from (
        (((v_last_date+1)::date)::timestamp at time zone 'Europe/Bucharest')
        - ((v_last_date::date)::timestamp at time zone 'Europe/Bucharest')
      ))/900
    )::integer * v_active_assets;
  end if;

  return jsonb_build_object(
    'schema_version','1.1.0',
    'checked_at',clock_timestamp(),
    'baraj_registry',jsonb_build_object(
      'total_baraje',v_baraje,
      'engine_configured_baraje',v_configured_baraje,
      'dispatch_supported_baraje',v_supported_baraje,
      'unconfigured_baraje',v_unconfigured_baraje
    ),
    'engine',jsonb_build_object(
      'active_cascades',v_active_cascades,
      'active_assets',v_active_assets,
      'hardcoded_asset_count',false
    ),
    'shadow',jsonb_build_object(
      'last_run_id',v_last_run,
      'last_run_at',v_last_run_at,
      'delivery_date',v_last_date,
      'forecast_values',v_values,
      'expected_forecast_values',v_expected,
      'coverage_complete',v_last_run is not null and v_values=v_expected
    )
  );
end;
$function$;

revoke all on function public.get_hydro_dispatch_national_foundation_health_v1() from public;
grant execute on function public.get_hydro_dispatch_national_foundation_health_v1() to service_role;
