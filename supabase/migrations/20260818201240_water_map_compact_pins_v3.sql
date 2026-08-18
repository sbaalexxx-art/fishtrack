create or replace function public.get_water_map_pins_v3(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision default 100,
  p_zoom double precision default 9,
  p_limit integer default 500
)
returns table(
  entity_type text,
  entity_id text,
  canonical_key text,
  name text,
  river_name text,
  country_code text,
  latitude double precision,
  longitude double precision,
  water_body_id uuid,
  trend_state text,
  operation_state text,
  priority integer,
  has_operational_data boolean,
  community_report_count integer
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select
    p.entity_type,
    p.entity_id,
    p.canonical_key,
    p.name,
    p.river_name,
    p.country_code,
    p.latitude,
    p.longitude,
    p.water_body_id,
    p.trend_state,
    p.operation_state,
    p.priority,
    p.has_operational_data,
    p.community_report_count
  from public.get_water_map_pins_v2(
    p_latitude,
    p_longitude,
    p_radius_km,
    p_zoom,
    least(greatest(coalesce(p_limit,500),1),750)
  ) as p
  where p.entity_type in ('dam','reservoir','hydro_plant')
  order by p.priority desc, p.name
  limit least(greatest(coalesce(p_limit,500),1),750);
$function$;

revoke all on function public.get_water_map_pins_v3(double precision,double precision,double precision,double precision,integer) from public;
grant execute on function public.get_water_map_pins_v3(double precision,double precision,double precision,double precision,integer) to anon, authenticated, service_role;

comment on function public.get_water_map_pins_v3(double precision,double precision,double precision,double precision,integer)
is 'Compact Hydro Map discovery contract. Static geometry/details remain in Mapbox/detail RPCs; returns only map-rendering and lightweight dynamic-state fields.';