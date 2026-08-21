-- Canonical Baraje identity for Water/Hydro presentation.
-- One fisherman-facing site per dam; reservoir and hydropower remain linked technical entities.

create or replace function public.get_water_baraj_sites_v1(
  p_country_code text default 'RO',
  p_hydropower_only boolean default false,
  p_limit integer default 500
)
returns table(
  site_id uuid, site_key text, display_name text, canonical_name text,
  river_name text, country_code text, county text, basin_name text,
  latitude double precision, longitude double precision, anchor_type text,
  has_hydropower boolean, hydropower_verified boolean, plant_id uuid,
  plant_name text, dam_id uuid, reservoir_id uuid, reservoir_name text,
  water_body_id uuid, reservoir_geometry_available boolean,
  relation_confidence text, relation_status text, relation_verified boolean,
  aliases text[]
)
language sql stable security definer
set search_path = public, pg_temp
as $$
with params as (
  select upper(coalesce(nullif(btrim(p_country_code),''),'RO')) as country_code,
         least(greatest(coalesce(p_limit,500),1),2500) as lim
), primary_reservoir as (
  select distinct on (dr.dam_id)
    dr.dam_id, r.id as reservoir_id, r.name as reservoir_name,
    r.alternative_name, r.water_body_id, r.hydropower_use,
    dr.confidence as relation_confidence, dr.proposal_status,
    dr.review_status, dr.match_method
  from public.dam_reservoir_relations dr
  join public.reservoirs r on r.id=dr.reservoir_id
  cross join params p
  where dr.map_eligible is true
    and dr.confidence='high'
    and upper(coalesce(r.country_code,''))=p.country_code
    and r.canonicalization_status='ready'
    and coalesce(r.map_eligible,true) is true
  order by dr.dam_id,
    case when r.hydropower_use='H' then 0 else 1 end,
    case when dr.review_status='approved' then 0 else 1 end,
    case dr.proposal_status when 'source_confirmed' then 0 when 'manual_validated' then 1 else 2 end,
    r.id
), primary_plant as (
  select distinct on (h.dam_id)
    h.dam_id, h.id as plant_id, h.name as plant_name,
    h.reservoir_id as plant_reservoir_id,
    h.water_body_id as plant_water_body_id
  from public.hydropower_plants h
  cross join params p
  where h.dam_id is not null
    and upper(coalesce(h.country_code,''))=p.country_code
    and h.canonicalization_status='ready'
    and coalesce(h.map_eligible,true) is true
  order by h.dam_id,h.installed_power_mw desc nulls last,h.name,h.id
), sites as (
  select
    d.id as site_id,
    ('baraj:'||d.id::text)::text as site_key,
    concat_ws(' · ',
      nullif(public.water_display_text_v1(d.name),''),
      nullif(public.water_display_text_v1(coalesce(nullif(d.resolved_river_name,''),nullif(d.source_river_name,''),wb.name)),'')
    ) as display_name,
    public.water_display_text_v1(d.name) as canonical_name,
    public.water_display_text_v1(coalesce(nullif(d.resolved_river_name,''),nullif(d.source_river_name,''),wb.name)) as river_name,
    upper(nullif(btrim(d.country_code),'')) as country_code,
    public.water_display_text_v1(d.county) as county,
    public.water_display_text_v1(d.basin_name) as basin_name,
    d.latitude,d.longitude,
    case when pp.plant_id is not null then 'hydro_verified_dam_anchor' else 'dam_anchor' end::text as anchor_type,
    (pp.plant_id is not null or pr.hydropower_use='H') as has_hydropower,
    (pp.plant_id is not null) as hydropower_verified,
    pp.plant_id,
    public.water_display_text_v1(pp.plant_name) as plant_name,
    d.id as dam_id,
    pr.reservoir_id,
    public.water_display_text_v1(pr.reservoir_name) as reservoir_name,
    coalesce(pp.plant_water_body_id,pr.water_body_id,d.water_body_id) as water_body_id,
    case when pr.reservoir_id is null then false else exists(
      select 1 from public.water_geometry_features gf
      where gf.reservoir_id=pr.reservoir_id
        and gf.geometry_valid is true
        and gf.feature_kind='reservoir'
        and upper(coalesce(gf.country_code,''))=upper(coalesce(d.country_code,''))
    ) end as reservoir_geometry_available,
    pr.relation_confidence,
    pr.proposal_status as relation_status,
    (pr.review_status='approved') as relation_verified,
    array_remove(array[
      public.water_display_text_v1(d.name),
      public.water_display_text_v1(pr.reservoir_name),
      public.water_display_text_v1(pr.alternative_name),
      public.water_display_text_v1(pp.plant_name),
      case when d.name is not null then 'Baraj '||public.water_display_text_v1(d.name) end,
      case when pr.reservoir_name is not null then 'Acumulare '||public.water_display_text_v1(pr.reservoir_name) end,
      case when pp.plant_name is not null then 'Hidro '||public.water_display_text_v1(pp.plant_name) end,
      case when d.name is not null and coalesce(nullif(d.resolved_river_name,''),nullif(d.source_river_name,''),wb.name) is not null
        then public.water_display_text_v1(d.name)||' '||public.water_display_text_v1(coalesce(nullif(d.resolved_river_name,''),nullif(d.source_river_name,''),wb.name)) end
    ],null)::text[] as aliases
  from public.dams d
  cross join params p
  left join primary_reservoir pr on pr.dam_id=d.id
  left join primary_plant pp on pp.dam_id=d.id
  left join public.water_bodies wb on wb.id=coalesce(pp.plant_water_body_id,pr.water_body_id,d.water_body_id)
  where upper(coalesce(d.country_code,''))=p.country_code
    and d.canonicalization_status='ready'
    and coalesce(d.map_eligible,true) is true
    and d.latitude is not null and d.longitude is not null
    and (not coalesce(p_hydropower_only,false) or pp.plant_id is not null or pr.hydropower_use='H')
)
select * from sites
order by hydropower_verified desc,has_hydropower desc,canonical_name,site_id
limit (select lim from params);
$$;

create or replace function public.search_water_baraje_v1(
  p_query text default null,
  p_country_code text default 'RO',
  p_limit integer default 50
)
returns table(
  site_id uuid, site_key text, display_name text, canonical_name text,
  river_name text, country_code text, county text, basin_name text,
  latitude double precision, longitude double precision, anchor_type text,
  has_hydropower boolean, hydropower_verified boolean, plant_id uuid,
  plant_name text, dam_id uuid, reservoir_id uuid, reservoir_name text,
  water_body_id uuid, reservoir_geometry_available boolean,
  relation_confidence text, relation_status text, relation_verified boolean,
  aliases text[]
)
language sql stable security definer
set search_path = public, pg_temp
as $$
with q as (
  select public.water_search_normalize_v1(p_query) as needle,
         least(greatest(coalesce(p_limit,50),1),100) as lim
), tokens as (
  select token
  from q,regexp_split_to_table(q.needle,'[[:space:]]+') token
  where token<>''
    and token not in ('baraj','barajul','acumulare','acumularea','hidro','che','hidrocentrala','hidrocentrale','lac','lacul')
), candidates as (
  select s.*,
    public.water_search_normalize_v1(concat_ws(' ',s.canonical_name,s.display_name,s.river_name,s.county,s.basin_name,array_to_string(s.aliases,' '))) as haystack
  from public.get_water_baraj_sites_v1(p_country_code,false,2500) s
)
select c.site_id,c.site_key,c.display_name,c.canonical_name,c.river_name,c.country_code,
  c.county,c.basin_name,c.latitude,c.longitude,c.anchor_type,c.has_hydropower,
  c.hydropower_verified,c.plant_id,c.plant_name,c.dam_id,c.reservoir_id,
  c.reservoir_name,c.water_body_id,c.reservoir_geometry_available,
  c.relation_confidence,c.relation_status,c.relation_verified,c.aliases
from candidates c,q
where q.needle=''
   or not exists(select 1 from tokens t where c.haystack not like '%'||t.token||'%')
order by
  case when public.water_search_normalize_v1(c.canonical_name)=q.needle then 0
       when public.water_search_normalize_v1(c.display_name)=q.needle then 1
       when public.water_search_normalize_v1(c.canonical_name) like q.needle||'%' then 2
       else 3 end,
  c.hydropower_verified desc,c.has_hydropower desc,c.canonical_name,c.site_id
limit (select lim from q);
$$;

create or replace function public.resolve_water_baraj_site_v1(
  p_entity_type text,
  p_entity_id uuid,
  p_country_code text default 'RO'
)
returns table(
  site_id uuid, site_key text, display_name text, canonical_name text,
  river_name text, country_code text, county text, basin_name text,
  latitude double precision, longitude double precision, anchor_type text,
  has_hydropower boolean, hydropower_verified boolean, plant_id uuid,
  plant_name text, dam_id uuid, reservoir_id uuid, reservoir_name text,
  water_body_id uuid, reservoir_geometry_available boolean,
  relation_confidence text, relation_status text, relation_verified boolean,
  aliases text[]
)
language sql stable security definer
set search_path = public, pg_temp
as $$
select s.* from public.get_water_baraj_sites_v1(p_country_code,false,2500) s
where case lower(coalesce(p_entity_type,''))
  when 'dam' then s.dam_id=p_entity_id
  when 'baraj' then s.dam_id=p_entity_id
  when 'reservoir' then s.reservoir_id=p_entity_id
  when 'acumulare' then s.reservoir_id=p_entity_id
  when 'hydro' then s.plant_id=p_entity_id
  when 'hydro_plant' then s.plant_id=p_entity_id
  when 'hydropower_plant' then s.plant_id=p_entity_id
  when 'site' then s.site_id=p_entity_id
  when 'baraj_site' then s.site_id=p_entity_id
  else false end
limit 1;
$$;

create or replace function public.get_water_baraj_pins_v1(
  p_latitude double precision,p_longitude double precision,
  p_radius_km double precision default 100,p_zoom double precision default 9,
  p_limit integer default 750
)
returns table(
  entity_type text,entity_id text,canonical_key text,name text,river_name text,
  country_code text,latitude double precision,longitude double precision,
  water_body_id uuid,distance_km double precision,priority integer,state_payload jsonb
)
language sql stable security definer
set search_path = public, pg_temp
as $$
with params as (
  select greatest(-90.0,least(90.0,p_latitude)) lat,
         greatest(-180.0,least(180.0,p_longitude)) lng,
         least(greatest(coalesce(p_radius_km,100),1),500) radius_km,
         greatest(0,least(coalesce(p_zoom,9),22)) zoom,
         least(greatest(coalesce(p_limit,750),1),1500) lim
), candidates as (
  select s.*,
    6371.0088*2*asin(sqrt(power(sin(radians(s.latitude-p.lat)/2),2)+cos(radians(p.lat))*cos(radians(s.latitude))*power(sin(radians(s.longitude-p.lng)/2),2))) distance_km,
    case when s.hydropower_verified then 98 when s.has_hydropower then 95 else 90 end::integer priority
  from public.get_water_baraj_sites_v1('RO',false,2500) s cross join params p
)
select 'baraj_site'::text,c.site_id::text,c.site_key,c.canonical_name,c.river_name,c.country_code,
  c.latitude,c.longitude,c.water_body_id,c.distance_km,c.priority,
  jsonb_strip_nulls(jsonb_build_object(
    'display_name',c.display_name,'anchor_type',c.anchor_type,'has_hydropower',c.has_hydropower,
    'hydropower_verified',c.hydropower_verified,'plant_id',c.plant_id,'plant_name',c.plant_name,
    'dam_id',c.dam_id,'reservoir_id',c.reservoir_id,'reservoir_name',c.reservoir_name,
    'reservoir_geometry_available',c.reservoir_geometry_available,'relation_confidence',c.relation_confidence,
    'relation_status',c.relation_status,'relation_verified',c.relation_verified))
from candidates c cross join params p
where c.distance_km<=p.radius_km and (p.zoom>=6 or c.hydropower_verified or c.has_hydropower)
order by c.priority desc,c.distance_km,c.canonical_name
limit (select lim from params);
$$;

revoke all on function public.get_water_baraj_sites_v1(text,boolean,integer) from public,anon;
revoke all on function public.search_water_baraje_v1(text,text,integer) from public,anon;
revoke all on function public.resolve_water_baraj_site_v1(text,uuid,text) from public,anon;
revoke all on function public.get_water_baraj_pins_v1(double precision,double precision,double precision,double precision,integer) from public,anon;
grant execute on function public.get_water_baraj_sites_v1(text,boolean,integer) to authenticated,service_role;
grant execute on function public.search_water_baraje_v1(text,text,integer) to authenticated,service_role;
grant execute on function public.resolve_water_baraj_site_v1(text,uuid,text) to authenticated,service_role;
grant execute on function public.get_water_baraj_pins_v1(double precision,double precision,double precision,double precision,integer) to authenticated,service_role;
