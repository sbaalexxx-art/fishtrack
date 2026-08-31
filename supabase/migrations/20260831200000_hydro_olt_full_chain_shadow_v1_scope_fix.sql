-- Preserve the legacy production pilot model_scope value without renaming it.
-- `hydro_dispatch_pilot` is production-supported for the existing 15 BARAJE.

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
            when 'hydro_dispatch_pilot' then 3
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
          and c.model_scope in ('pilot','hydro_dispatch_pilot','production','national')
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
