-- Optimized Hydro Map catalog. Starts from ANAR hydropower reservoirs instead of scanning every dam.

create or replace function public.get_hydro_map_sites_v1(
  p_country_code text default 'RO',
  p_include_unresolved boolean default true,
  p_limit integer default 500
)
returns table(
  site_key text,pin_eligible boolean,display_name text,canonical_name text,
  river_name text,country_code text,county text,basin_name text,
  latitude double precision,longitude double precision,anchor_type text,
  hydropower_verified boolean,dispatch_available boolean,plant_id uuid,
  dam_id uuid,reservoir_id uuid,water_body_id uuid,
  reservoir_geometry_available boolean,volume_million_m3 numeric,
  surface_area_km2 numeric,importance_class text,relation_confidence text,
  relation_status text,relation_verified boolean
)
language sql stable security definer
set search_path = public,pg_temp
as $$
with params as (
  select upper(coalesce(nullif(btrim(p_country_code),''),'RO')) country_code,
         least(greatest(coalesce(p_limit,500),1),1000) lim
), hydro_reservoirs as (
  select r.* from public.reservoirs r cross join params p
  where upper(coalesce(r.country_code,''))=p.country_code
    and r.hydropower_use='H'
    and r.canonicalization_status='ready'
    and coalesce(r.map_eligible,true) is true
), best_relation as (
  select distinct on (dr.reservoir_id)
    dr.reservoir_id,dr.dam_id,dr.confidence,dr.proposal_status,dr.review_status,dr.match_method
  from public.dam_reservoir_relations dr
  join hydro_reservoirs r on r.id=dr.reservoir_id
  where dr.map_eligible is true and dr.confidence='high'
  order by dr.reservoir_id,
    case when dr.review_status='approved' then 0 else 1 end,
    case dr.proposal_status when 'source_confirmed' then 0 when 'manual_validated' then 1 else 2 end,
    dr.dam_id
), resolved as (
  select r.*,br.dam_id linked_dam_id,br.confidence relation_confidence,
    br.proposal_status relation_status,br.review_status,
    d.name dam_name,d.latitude dam_latitude,d.longitude dam_longitude,
    d.water_body_id dam_water_body_id,d.source_river_name dam_source_river_name,
    d.resolved_river_name dam_resolved_river_name,d.county dam_county,d.basin_name dam_basin_name
  from hydro_reservoirs r
  left join best_relation br on br.reservoir_id=r.id
  left join public.dams d on d.id=br.dam_id
    and d.canonicalization_status='ready' and coalesce(d.map_eligible,true) is true
), enriched as (
  select r.*,hp.id plant_id,hp.name plant_name,hp.water_body_id plant_water_body_id,
    exists(
      select 1 from public.hydro_dispatch_cascade_nodes n
      join public.hydro_dispatch_cascades c on c.id=n.cascade_id
      where c.is_active is true and n.plant_id=hp.id
    ) dispatch_available
  from resolved r
  left join lateral (
    select h.* from public.hydropower_plants h
    where upper(coalesce(h.country_code,''))=(select country_code from params)
      and h.canonicalization_status='ready' and coalesce(h.map_eligible,true) is true
      and (h.reservoir_id=r.id or (r.linked_dam_id is not null and h.dam_id=r.linked_dam_id))
    order by case when h.reservoir_id=r.id then 0 else 1 end,h.installed_power_mw desc nulls last,h.id
    limit 1
  ) hp on true
)
select
  case when e.linked_dam_id is not null then 'baraj:'||e.linked_dam_id::text else 'hydro-reservoir:'||e.id::text end site_key,
  (e.linked_dam_id is not null and e.dam_latitude is not null and e.dam_longitude is not null) pin_eligible,
  concat_ws(' · ',
    nullif(public.water_display_text_v1(coalesce(e.dam_name,e.name)),''),
    nullif(public.water_display_text_v1(coalesce(nullif(e.dam_resolved_river_name,''),nullif(e.dam_source_river_name,''),nullif(e.resolved_river_name,''),nullif(e.source_main_river_name,''),nullif(e.source_river_name,''))),'')
  ) display_name,
  public.water_display_text_v1(coalesce(e.dam_name,e.name)) canonical_name,
  public.water_display_text_v1(coalesce(nullif(e.dam_resolved_river_name,''),nullif(e.dam_source_river_name,''),nullif(e.resolved_river_name,''),nullif(e.source_main_river_name,''),nullif(e.source_river_name,''))) river_name,
  upper(nullif(btrim(e.country_code),'')) country_code,
  public.water_display_text_v1(coalesce(e.dam_county,e.county)) county,
  public.water_display_text_v1(coalesce(e.dam_basin_name,e.basin_name)) basin_name,
  case when e.linked_dam_id is not null then e.dam_latitude else e.latitude end latitude,
  case when e.linked_dam_id is not null then e.dam_longitude else e.longitude end longitude,
  case when e.plant_id is not null then 'hydro_verified_dam_anchor'
       when e.linked_dam_id is not null then 'dam_anchor'
       else 'reservoir_geometry_only' end anchor_type,
  (e.plant_id is not null) hydropower_verified,
  coalesce(e.dispatch_available,false) dispatch_available,
  e.plant_id,e.linked_dam_id dam_id,e.id reservoir_id,
  coalesce(e.plant_water_body_id,e.dam_water_body_id,e.water_body_id) water_body_id,
  exists(select 1 from public.water_geometry_features gf where gf.reservoir_id=e.id and gf.feature_kind='reservoir' and gf.geometry_valid is true) reservoir_geometry_available,
  e.volume_million_m3,e.surface_area_km2,e.importance_class,
  e.relation_confidence,e.relation_status,(e.review_status='approved') relation_verified
from enriched e
where coalesce(p_include_unresolved,true) or e.linked_dam_id is not null
order by (e.linked_dam_id is null),(e.plant_id is null),e.volume_million_m3 desc nulls last,canonical_name
limit (select lim from params);
$$;

create or replace function public.get_hydro_map_v1(
  p_latitude double precision,p_longitude double precision,
  p_radius_km double precision default 100,p_zoom double precision default 9,
  p_basin_query text default null,p_country_code text default 'RO',
  p_limit integer default 750
)
returns table(
  row_type text,map_key text,cluster_count integer,name text,river_name text,
  basin_name text,country_code text,latitude double precision,longitude double precision,
  distance_km double precision,priority integer,hydropower_verified boolean,
  dispatch_available boolean,plant_id uuid,dam_id uuid,reservoir_id uuid,
  water_body_id uuid,reservoir_geometry_available boolean,state_payload jsonb
)
language sql stable security definer
set search_path = public,pg_temp
as $$
with params as (
  select greatest(-90.0,least(90.0,p_latitude)) lat,
    greatest(-180.0,least(180.0,p_longitude)) lng,
    least(greatest(coalesce(p_radius_km,100),1),500) radius_km,
    greatest(0,least(coalesce(p_zoom,9),22)) zoom,
    public.water_search_normalize_v1(p_basin_query) basin_needle,
    upper(coalesce(nullif(btrim(p_country_code),''),'RO')) country_code,
    least(greatest(coalesce(p_limit,750),1),1500) lim,
    case when coalesce(p_zoom,9)<6.5 then 0.65 when coalesce(p_zoom,9)<7.5 then 0.32
         when coalesce(p_zoom,9)<8.5 then 0.16 when coalesce(p_zoom,9)<9.5 then 0.08 else 0.0 end cell_size
), source as (
  select s.* from params p cross join lateral public.get_hydro_map_sites_v1(p.country_code,false,500) s
  where s.pin_eligible is true
    and (p.basin_needle='' or public.water_search_normalize_v1(concat_ws(' ',s.river_name,s.basin_name,s.display_name)) like '%'||p.basin_needle||'%')
), candidates as (
  select s.*,
    6371.0088*2*asin(sqrt(power(sin(radians(s.latitude-p.lat)/2),2)+cos(radians(p.lat))*cos(radians(s.latitude))*power(sin(radians(s.longitude-p.lng)/2),2))) distance_km,
    case when s.dispatch_available then 100 when s.hydropower_verified then 98 else 94 end::integer priority,
    case when p.cell_size>0 then floor(s.latitude/p.cell_size)::integer end cell_y,
    case when p.cell_size>0 then floor(s.longitude/p.cell_size)::integer end cell_x
  from source s cross join params p
  where 6371.0088*2*asin(sqrt(power(sin(radians(s.latitude-p.lat)/2),2)+cos(radians(p.lat))*cos(radians(s.latitude))*power(sin(radians(s.longitude-p.lng)/2),2)))<=p.radius_km
), bucket_stats as (
  select c.cell_y,c.cell_x,count(*)::integer cnt,avg(c.latitude)::double precision cluster_lat,
    avg(c.longitude)::double precision cluster_lon,min(c.distance_km)::double precision min_distance_km,
    max(c.priority)::integer max_priority,bool_or(c.hydropower_verified) hydropower_verified,
    bool_or(c.dispatch_available) dispatch_available,
    count(*) filter(where c.hydropower_verified)::integer verified_count,
    count(*) filter(where c.dispatch_available)::integer dispatch_count,
    case when count(distinct c.river_name)=1 then min(c.river_name) end river_name,
    case when count(distinct c.basin_name)=1 then min(c.basin_name) end basin_name,
    min(c.country_code) country_code
  from candidates c cross join params p where p.cell_size>0 group by c.cell_y,c.cell_x
), clusters as (
  select 'cluster'::text row_type,('hydro-cluster:'||b.cell_y||':'||b.cell_x)::text map_key,b.cnt cluster_count,
    case when b.river_name is not null then b.river_name||' · '||b.cnt else b.cnt||' baraje' end::text name,
    b.river_name,b.basin_name,b.country_code,b.cluster_lat latitude,b.cluster_lon longitude,b.min_distance_km distance_km,
    b.max_priority priority,b.hydropower_verified,b.dispatch_available,null::uuid plant_id,null::uuid dam_id,
    null::uuid reservoir_id,null::uuid water_body_id,false reservoir_geometry_available,
    jsonb_build_object('semantic','hydro_cluster','site_count',b.cnt,'hydropower_verified_count',b.verified_count,'dispatch_available_count',b.dispatch_count) state_payload
  from bucket_stats b where b.cnt>1
), singles as (
  select 'site'::text row_type,c.site_key map_key,1::integer cluster_count,c.canonical_name name,c.river_name,c.basin_name,
    c.country_code,c.latitude,c.longitude,c.distance_km,c.priority,c.hydropower_verified,c.dispatch_available,
    c.plant_id,c.dam_id,c.reservoir_id,c.water_body_id,c.reservoir_geometry_available,
    jsonb_strip_nulls(jsonb_build_object('semantic',case when c.dispatch_available then 'hydro_dispatch_baraj' when c.hydropower_verified then 'hydro_verified_baraj' else 'hydro_baraj' end,
      'display_name',c.display_name,'anchor_type',c.anchor_type,'volume_million_m3',c.volume_million_m3,'surface_area_km2',c.surface_area_km2,
      'importance_class',c.importance_class,'relation_confidence',c.relation_confidence,'relation_status',c.relation_status,'relation_verified',c.relation_verified)) state_payload
  from candidates c cross join params p left join bucket_stats b on b.cell_y=c.cell_y and b.cell_x=c.cell_x
  where p.cell_size=0 or b.cnt=1
), combined as (select * from clusters union all select * from singles)
select * from combined
order by case when row_type='site' and dispatch_available then 0 when row_type='site' and hydropower_verified then 1 when row_type='site' then 2 else 3 end,
  priority desc,distance_km,name
limit (select lim from params);
$$;

revoke all on function public.get_hydro_map_sites_v1(text,boolean,integer) from public,anon;
revoke all on function public.get_hydro_map_v1(double precision,double precision,double precision,double precision,text,text,integer) from public,anon;
grant execute on function public.get_hydro_map_sites_v1(text,boolean,integer) to authenticated,service_role;
grant execute on function public.get_hydro_map_v1(double precision,double precision,double precision,double precision,text,text,integer) to authenticated,service_role;
