-- Canonical Baraje map contract with deterministic zoom-based clustering.

create or replace function public.get_water_baraj_map_v2(
  p_latitude double precision,
  p_longitude double precision,
  p_radius_km double precision default 100,
  p_zoom double precision default 9,
  p_hydropower_only boolean default true,
  p_basin_query text default null,
  p_country_code text default 'RO',
  p_limit integer default 750
)
returns table(
  row_type text,map_key text,site_id uuid,cluster_count integer,name text,
  river_name text,basin_name text,country_code text,latitude double precision,
  longitude double precision,distance_km double precision,priority integer,
  has_hydropower boolean,hydropower_verified boolean,dispatch_available boolean,
  plant_id uuid,dam_id uuid,reservoir_id uuid,water_body_id uuid,
  reservoir_geometry_available boolean,state_payload jsonb
)
language sql stable security definer
set search_path = public, pg_temp
as $$
with params as (
  select greatest(-90.0,least(90.0,p_latitude))::double precision lat,
         greatest(-180.0,least(180.0,p_longitude))::double precision lng,
         least(greatest(coalesce(p_radius_km,100),1),500)::double precision radius_km,
         greatest(0,least(coalesce(p_zoom,9),22))::double precision zoom,
         coalesce(p_hydropower_only,true) hydro_only,
         public.water_search_normalize_v1(p_basin_query) basin_needle,
         upper(coalesce(nullif(btrim(p_country_code),''),'RO')) country_code,
         least(greatest(coalesce(p_limit,750),1),1500)::integer lim,
         case when coalesce(p_zoom,9)<6.5 then 0.65
              when coalesce(p_zoom,9)<7.5 then 0.32
              when coalesce(p_zoom,9)<8.5 then 0.16
              when coalesce(p_zoom,9)<9.5 then 0.08
              else 0.0 end::double precision cell_size
), sites as (
  select s.*
  from params p
  cross join lateral public.get_water_baraj_sites_v1(p.country_code,p.hydro_only,2500) s
  where p.basin_needle=''
     or public.water_search_normalize_v1(concat_ws(' ',s.river_name,s.basin_name,s.display_name)) like '%'||p.basin_needle||'%'
), candidates as (
  select s.*,
    6371.0088*2*asin(sqrt(power(sin(radians(s.latitude-p.lat)/2),2)+cos(radians(p.lat))*cos(radians(s.latitude))*power(sin(radians(s.longitude-p.lng)/2),2)))::double precision distance_km,
    case when s.hydropower_verified then 98 when s.has_hydropower then 95 else 90 end::integer priority,
    exists(
      select 1 from public.hydro_dispatch_cascade_nodes n
      join public.hydro_dispatch_cascades c on c.id=n.cascade_id and c.is_active is true
      where n.plant_id=s.plant_id
    ) dispatch_available,
    case when p.cell_size>0 then floor(s.latitude/p.cell_size)::integer end cell_y,
    case when p.cell_size>0 then floor(s.longitude/p.cell_size)::integer end cell_x
  from sites s cross join params p
  where 6371.0088*2*asin(sqrt(power(sin(radians(s.latitude-p.lat)/2),2)+cos(radians(p.lat))*cos(radians(s.latitude))*power(sin(radians(s.longitude-p.lng)/2),2)))<=p.radius_km
), bucket_stats as (
  select c.cell_y,c.cell_x,count(*)::integer cnt,
    avg(c.latitude)::double precision cluster_lat,
    avg(c.longitude)::double precision cluster_lon,
    min(c.distance_km)::double precision min_distance_km,
    max(c.priority)::integer max_priority,
    bool_or(c.has_hydropower) has_hydropower,
    bool_or(c.hydropower_verified) hydropower_verified,
    bool_or(c.dispatch_available) dispatch_available,
    count(*) filter(where c.hydropower_verified)::integer verified_count,
    count(*) filter(where c.dispatch_available)::integer dispatch_count,
    case when count(distinct c.river_name)=1 then min(c.river_name) end river_name,
    case when count(distinct c.basin_name)=1 then min(c.basin_name) end basin_name,
    min(c.country_code) country_code
  from candidates c cross join params p
  where p.cell_size>0
  group by c.cell_y,c.cell_x
), cluster_rows as (
  select 'cluster'::text row_type,
    ('baraj-cluster:'||b.cell_y::text||':'||b.cell_x::text)::text map_key,
    null::uuid site_id,b.cnt cluster_count,
    case when b.river_name is not null then b.river_name||' · '||b.cnt::text else b.cnt::text||' baraje' end::text name,
    b.river_name,b.basin_name,b.country_code,b.cluster_lat latitude,b.cluster_lon longitude,
    b.min_distance_km distance_km,b.max_priority priority,b.has_hydropower,b.hydropower_verified,b.dispatch_available,
    null::uuid plant_id,null::uuid dam_id,null::uuid reservoir_id,null::uuid water_body_id,false reservoir_geometry_available,
    jsonb_build_object('site_count',b.cnt,'hydropower_verified_count',b.verified_count,'dispatch_available_count',b.dispatch_count,'semantic','baraj_cluster') state_payload
  from bucket_stats b where b.cnt>1
), single_cluster_sites as (
  select 'site'::text row_type,c.site_key map_key,c.site_id,1::integer cluster_count,c.canonical_name name,
    c.river_name,c.basin_name,c.country_code,c.latitude,c.longitude,c.distance_km,c.priority,c.has_hydropower,
    c.hydropower_verified,c.dispatch_available,c.plant_id,c.dam_id,c.reservoir_id,c.water_body_id,c.reservoir_geometry_available,
    jsonb_strip_nulls(jsonb_build_object('display_name',c.display_name,'anchor_type',c.anchor_type,'plant_name',c.plant_name,
      'reservoir_name',c.reservoir_name,'relation_confidence',c.relation_confidence,'relation_status',c.relation_status,
      'relation_verified',c.relation_verified,'semantic',case when c.hydropower_verified then 'hydro_verified_baraj' when c.has_hydropower then 'hydropower_baraj' else 'baraj' end)) state_payload
  from candidates c join bucket_stats b on b.cell_y=c.cell_y and b.cell_x=c.cell_x and b.cnt=1
), unclustered_sites as (
  select 'site'::text row_type,c.site_key map_key,c.site_id,1::integer cluster_count,c.canonical_name name,
    c.river_name,c.basin_name,c.country_code,c.latitude,c.longitude,c.distance_km,c.priority,c.has_hydropower,
    c.hydropower_verified,c.dispatch_available,c.plant_id,c.dam_id,c.reservoir_id,c.water_body_id,c.reservoir_geometry_available,
    jsonb_strip_nulls(jsonb_build_object('display_name',c.display_name,'anchor_type',c.anchor_type,'plant_name',c.plant_name,
      'reservoir_name',c.reservoir_name,'relation_confidence',c.relation_confidence,'relation_status',c.relation_status,
      'relation_verified',c.relation_verified,'semantic',case when c.hydropower_verified then 'hydro_verified_baraj' when c.has_hydropower then 'hydropower_baraj' else 'baraj' end)) state_payload
  from candidates c cross join params p where p.cell_size=0
), combined as (
  select * from cluster_rows union all select * from single_cluster_sites union all select * from unclustered_sites
)
select * from combined
order by case when row_type='site' and hydropower_verified then 0 when row_type='site' and has_hydropower then 1 when row_type='cluster' then 2 else 3 end,
  priority desc,distance_km,name
limit (select lim from params);
$$;

revoke all on function public.get_water_baraj_map_v2(double precision,double precision,double precision,double precision,boolean,text,text,integer) from public,anon;
grant execute on function public.get_water_baraj_map_v2(double precision,double precision,double precision,double precision,boolean,text,text,integer) to authenticated,service_role;
