-- Dynamic Hydro overlay and selected-site intelligence.
-- Map refresh stays light; heavier intelligence is fetched only after selection.

create or replace function public.get_hydro_map_dispatch_overlay_v1(
  p_at timestamp with time zone default now()
)
returns table(
  site_key text,plant_id uuid,dam_id uuid,reservoir_id uuid,name text,
  latitude double precision,longitude double precision,availability_status text,
  window_start timestamp with time zone,window_end timestamp with time zone,
  window_probability double precision,peak_probability double precision,
  confidence text,evidence_class text,updated_at timestamp with time zone,
  observed_state text,observed_confidence double precision,
  observed_freshness text,observed_report_count integer
)
language sql stable security definer
set search_path = public,pg_temp
as $$
with forecast as (
  select f.* from public.get_hydro_dispatch_olt_today_tomorrow_v3(null,p_at) f
  where f.day_offset=0
), observed as (
  select o.* from public.get_hydro_dispatch_olt_observed_state_v1(p_at) o
), identity as (
  select s.* from public.get_hydro_map_sites_v1('RO',false,1000) s
  where s.dispatch_available is true and s.plant_id is not null
)
select i.site_key,i.plant_id,i.dam_id,i.reservoir_id,i.canonical_name,
  i.latitude,i.longitude,
  coalesce(f.availability_status,'UNAVAILABLE'),f.window_start,f.window_end,
  f.window_probability,f.peak_probability,coalesce(f.confidence,'unknown'),
  coalesce(f.evidence_class,'UNKNOWN'),f.updated_at,
  coalesce(o.observed_state,'NO_RECENT_OBSERVATION'),
  coalesce(o.confidence,0.0)::double precision,
  coalesce(o.freshness_status,'unavailable'),coalesce(o.report_count,0)::integer
from identity i
left join forecast f on f.plant_id=i.plant_id
left join observed o on o.plant_id=i.plant_id
order by i.canonical_name;
$$;

create or replace function public.get_hydro_map_site_intelligence_v1(
  p_dam_id uuid,
  p_at timestamp with time zone default now()
)
returns jsonb
language plpgsql stable security definer
set search_path = public,pg_temp
as $$
declare
  s record;
  measured jsonb := '[]'::jsonb;
  dispatch_json jsonb := null;
  observed_json jsonb := null;
  community_json jsonb := null;
begin
  select * into s
  from public.get_hydro_map_sites_v1('RO',true,1000) x
  where x.dam_id=p_dam_id
  limit 1;

  if s.dam_id is null then
    return jsonb_build_object('status','not_found','dam_id',p_dam_id);
  end if;

  select coalesce(jsonb_agg(to_jsonb(m) order by m.metric_code),'[]'::jsonb)
  into measured
  from (
    select distinct on (o.metric_code)
      o.metric_code,o.metric_name,o.value,o.unit,o.observed_at,
      o.quality_status,o.confidence,o.source_url
    from public.water_operational_observations o
    where o.evidence_state='MEASURED'
      and o.availability_status='available'
      and (o.dam_id=s.dam_id or o.reservoir_id=s.reservoir_id)
    order by o.metric_code,coalesce(o.observed_at,o.fetched_at) desc
  ) m;

  if s.dispatch_available and s.plant_id is not null then
    select jsonb_build_object(
      'today',jsonb_strip_nulls(jsonb_build_object(
        'delivery_date',f.delivery_date,'availability_status',f.availability_status,
        'window_start',f.window_start,'window_end',f.window_end,
        'window_probability',f.window_probability,'peak_probability',f.peak_probability,
        'confidence',f.confidence,'evidence_class',f.evidence_class,'updated_at',f.updated_at)),
      'tomorrow',(
        select jsonb_strip_nulls(jsonb_build_object(
          'delivery_date',t.delivery_date,'availability_status',t.availability_status,
          'window_start',t.window_start,'window_end',t.window_end,
          'window_probability',t.window_probability,'peak_probability',t.peak_probability,
          'confidence',t.confidence,'evidence_class',t.evidence_class,'updated_at',t.updated_at))
        from public.get_hydro_dispatch_olt_today_tomorrow_v3(null,p_at) t
        where t.plant_id=s.plant_id and t.day_offset=1 limit 1),
      'truth','Probabilitate estimată, nu confirmare oficială a operatorului.'
    ) into dispatch_json
    from public.get_hydro_dispatch_olt_today_tomorrow_v3(null,p_at) f
    where f.plant_id=s.plant_id and f.day_offset=0 limit 1;

    select jsonb_strip_nulls(jsonb_build_object(
      'state',o.observed_state,'started_at',o.started_at,
      'last_confirmed_at',o.last_confirmed_at,'ended_at',o.ended_at,
      'report_count',o.report_count,'confidence',o.confidence,
      'evidence_class',o.evidence_class,'freshness_status',o.freshness_status,
      'disclaimer',o.disclaimer))
    into observed_json
    from public.get_hydro_dispatch_olt_observed_state_v1(p_at) o
    where o.plant_id=s.plant_id limit 1;
  end if;

  select jsonb_build_object(
    'recent_report_count',count(*)::integer,
    'latest_observed_at',max(w.observed_at))
  into community_json
  from public.water_community_observations w
  join public.reports r on r.id=w.report_id
  where r.is_suspicious=false
    and w.observed_at>=p_at-interval '24 hours'
    and (w.dam_id=s.dam_id or w.reservoir_id=s.reservoir_id);

  return jsonb_build_object(
    'status','ok',
    'identity',jsonb_strip_nulls(jsonb_build_object(
      'site_key',s.site_key,'display_name',s.display_name,'name',s.canonical_name,
      'river_name',s.river_name,'basin_name',public.water_basin_display_name_v1(s.basin_name),
      'county',s.county,'latitude',s.latitude,'longitude',s.longitude,
      'anchor_type',s.anchor_type,'plant_id',s.plant_id,'dam_id',s.dam_id,
      'reservoir_id',s.reservoir_id,'water_body_id',s.water_body_id,
      'hydropower_verified',s.hydropower_verified,'dispatch_available',s.dispatch_available,
      'reservoir_geometry_available',s.reservoir_geometry_available)),
    'reservoir',jsonb_strip_nulls(jsonb_build_object(
      'volume_million_m3',s.volume_million_m3,
      'surface_area_km2',s.surface_area_km2,'importance_class',s.importance_class)),
    'measured_metrics',measured,
    'dispatch',dispatch_json,
    'observed_operation',observed_json,
    'community',community_json,
    'truth',jsonb_build_object(
      'measured_metrics_evidence','MEASURED only',
      'dispatch_evidence','ESTIMATED when available',
      'community_evidence','OBSERVED when validated',
      'operator_confirmation',false));
end;
$$;

revoke all on function public.get_hydro_map_dispatch_overlay_v1(timestamp with time zone) from public,anon;
revoke all on function public.get_hydro_map_site_intelligence_v1(uuid,timestamp with time zone) from public,anon;
grant execute on function public.get_hydro_map_dispatch_overlay_v1(timestamp with time zone) to authenticated,service_role;
grant execute on function public.get_hydro_map_site_intelligence_v1(uuid,timestamp with time zone) to authenticated,service_role;
