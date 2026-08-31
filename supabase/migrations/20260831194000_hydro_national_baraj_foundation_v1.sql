-- Hydro Dispatch P1 — National BARAJ foundation v1
--
-- Product rule: the mobile/UI identity is one BARAJ. CHE and reservoir identities
-- remain technical backend links. This migration does not replace the current Olt
-- production contract. It creates a generic, dynamic foundation and a private shadow
-- market engine so future basins can be added through data/configuration rather than
-- by hardcoding plant counts or cascade keys in the algorithm.

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
  select
    c.id,
    c.canonical_key,
    c.name,
    c.model_scope,
    n.node_order,
    h.id,
    h.canonical_key,
    h.name,
    h.dam_id,
    coalesce(d.name,h.name),
    h.reservoir_id,
    r.name,
    h.water_body_id,
    coalesce(d.basin_name,r.basin_name),
    coalesce(d.resolved_river_name,d.source_river_name,r.resolved_river_name,r.source_river_name),
    coalesce(d.latitude,r.latitude),
    coalesce(d.longitude,r.longitude),
    h.canonicalization_status,
    h.map_eligible
  from public.hydro_dispatch_cascades c
  join public.hydro_dispatch_cascade_nodes n on n.cascade_id=c.id
  join public.hydropower_plants h on h.id=n.plant_id
  left join public.dams d on d.id=h.dam_id
  left join public.reservoirs r on r.id=h.reservoir_id
  where c.is_active=true
    and h.country_code='RO'
    and h.canonicalization_status='ready'
  order by c.canonical_key,n.node_order,h.id;
$function$;

revoke all on function public.get_hydro_dispatch_active_assets_v1() from public;
grant execute on function public.get_hydro_dispatch_active_assets_v1() to service_role;

comment on function public.get_hydro_dispatch_active_assets_v1() is
'Private dynamic Hydro Dispatch asset registry. No fixed plant count/cascade key. One configured plant links to its canonical dam (BARAJ) and reservoir.';


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
      ) as configured
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
    bool_or(p.configured) as engine_configured,
    bool_or(p.configured) as dispatch_supported,
    bool_or(p.map_eligible and coalesce(p.dam_map_eligible,true)) as map_eligible
  from plants p
  group by p.dam_id
  order by coalesce(max(p.dam_basin_name),''),coalesce(max(p.dam_name),min(p.name)),p.dam_id;
$function$;

revoke all on function public.get_hydro_dispatch_baraj_registry_v1(text) from public;
grant execute on function public.get_hydro_dispatch_baraj_registry_v1(text) to anon, authenticated, service_role;

comment on function public.get_hydro_dispatch_baraj_registry_v1(text) is
'Canonical app-facing BARAJ registry. One UI identity per dam; CHE/reservoir remain linked backend entities. No raw Hydro Dispatch evidence is exposed.';


create or replace function public.refresh_hydro_dispatch_national_shadow_v1(
  p_delivery_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth, pg_temp
as $function$
declare
  v_role text;
  v_source_id uuid;
  v_delivery_date date;
  v_expected_slots integer;
  v_market_count integer := 0;
  v_asset_count integer := 0;
  v_cascade_count integer := 0;
  v_run_id uuid;
  v_existing uuid;
  v_existing_values integer := 0;
  v_inserted integer := 0;
  v_min_start timestamptz;
  v_max_end timestamptz;
  v_market_fingerprint text;
  v_asset_fingerprint text;
  v_fingerprint text;
begin
  v_role := coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    auth.jwt()->>'role',
    case when session_user in ('service_role','postgres') then session_user end
  );
  if v_role not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select id into v_source_id
  from public.water_data_sources
  where source_key='fluviai-hydro-dispatch-v1' and is_active=true
  order by created_at desc
  limit 1;
  if v_source_id is null then
    raise exception 'Missing active data source fluviai-hydro-dispatch-v1';
  end if;

  select count(*)::integer,count(distinct cascade_id)::integer
    into v_asset_count,v_cascade_count
  from public.get_hydro_dispatch_active_assets_v1();
  if v_asset_count=0 then
    return jsonb_build_object('status','no_active_assets','forecast_values',0);
  end if;

  if p_delivery_date is not null then
    v_delivery_date := p_delivery_date;
  else
    select x.delivery_date into v_delivery_date
    from (
      select
        (m.delivery_start at time zone 'Europe/Bucharest')::date as delivery_date,
        count(distinct m.delivery_start)::integer as slots
      from public.hydro_dispatch_market_observations m
      where m.source_key='ENTSOE_DA_RO' and m.market_zone='RO'
      group by (m.delivery_start at time zone 'Europe/Bucharest')::date
    ) x
    where x.slots=(
      extract(epoch from (
        (((x.delivery_date+1)::date)::timestamp at time zone 'Europe/Bucharest')
        - ((x.delivery_date::date)::timestamp at time zone 'Europe/Bucharest')
      ))/900
    )::integer
    order by x.delivery_date desc
    limit 1;
  end if;

  if v_delivery_date is null then
    return jsonb_build_object('status','no_complete_market_day','forecast_values',0);
  end if;

  v_expected_slots := (
    extract(epoch from (
      (((v_delivery_date+1)::date)::timestamp at time zone 'Europe/Bucharest')
      - ((v_delivery_date::date)::timestamp at time zone 'Europe/Bucharest')
    ))/900
  )::integer;

  select count(distinct m.delivery_start)::integer,min(m.delivery_start),max(m.delivery_end)
    into v_market_count,v_min_start,v_max_end
  from public.hydro_dispatch_market_observations m
  where m.source_key='ENTSOE_DA_RO'
    and m.market_zone='RO'
    and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_delivery_date;

  if v_market_count<>v_expected_slots then
    return jsonb_build_object(
      'status','target_market_incomplete',
      'delivery_date',v_delivery_date,
      'market_intervals',v_market_count,
      'expected_intervals',v_expected_slots,
      'forecast_values',0
    );
  end if;

  select encode(digest(string_agg(m.source_record_fingerprint,',' order by m.delivery_start),'sha256'),'hex')
    into v_market_fingerprint
  from public.hydro_dispatch_market_observations m
  where m.source_key='ENTSOE_DA_RO'
    and m.market_zone='RO'
    and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_delivery_date;

  select encode(digest(string_agg(
      a.cascade_key||':'||a.node_order::text||':'||a.plant_id::text||':'||coalesce(a.baraj_id::text,'-'),
      ',' order by a.cascade_key,a.node_order,a.plant_id
    ),'sha256'),'hex')
    into v_asset_fingerprint
  from public.get_hydro_dispatch_active_assets_v1() a;

  v_fingerprint := encode(digest(
    'hydro_dispatch_ro_national_shadow_v1|'||v_delivery_date::text||'|'||
    coalesce(v_market_fingerprint,'')||'|'||coalesce(v_asset_fingerprint,''),
    'sha256'
  ),'hex');

  select id into v_existing
  from public.water_forecast_runs
  where country_code='RO'
    and model_key='hydro_dispatch_ro_national_market_shadow_v1'
    and source_record_fingerprint=v_fingerprint
  order by created_at desc
  limit 1;

  if v_existing is not null then
    select count(*)::integer into v_existing_values
    from public.water_forecast_values
    where forecast_run_id=v_existing
      and metric_code='hydro_dispatch_probability';
    return jsonb_build_object(
      'status','already_current',
      'delivery_date',v_delivery_date,
      'forecast_run_id',v_existing,
      'market_intervals',v_market_count,
      'expected_intervals',v_expected_slots,
      'active_cascades',v_cascade_count,
      'active_assets',v_asset_count,
      'forecast_values',v_existing_values,
      'expected_forecast_values',v_expected_slots*v_asset_count,
      'shadow',true
    );
  end if;

  insert into public.water_forecast_runs(
    source_id,country_code,model_key,model_version,forecast_kind,
    run_at,fetched_at,horizon_hours,spatial_resolution_km,ensemble_size,
    quality_status,source_record_id,source_record_fingerprint,provenance
  ) values (
    v_source_id,'RO','hydro_dispatch_ro_national_market_shadow_v1','0.1.0-shadow-market-baseline','scenario',
    now(),now(),greatest(0,ceil(extract(epoch from(v_max_end-v_min_start))/3600.0)::integer),
    null,null,'validated','ENTSOE_DA_RO:'||v_delivery_date::text,v_fingerprint,
    jsonb_build_object(
      'scope','national_configured_cascades',
      'shadow',true,
      'evidence_class','ESTIMATED',
      'confidence','low',
      'driver','day_ahead_market',
      'market_source','ENTSOE_DA_RO',
      'raw_price_exposed',false,
      'calibration_status','uncalibrated',
      'active_cascades',v_cascade_count,
      'active_assets',v_asset_count,
      'warning','Shadow baseline only. Market pressure is not proof that a specific CHE operates.'
    )
  ) returning id into v_run_id;

  with market_base as (
    select
      m.delivery_start,m.delivery_end,m.price::double precision as price,
      percent_rank() over(order by m.price) as price_percentile,
      min(m.price) over()::double precision as min_price,
      max(m.price) over()::double precision as max_price,
      lag(m.price) over(order by m.delivery_start)::double precision as previous_price
    from public.hydro_dispatch_market_observations m
    where m.source_key='ENTSOE_DA_RO'
      and m.market_zone='RO'
      and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_delivery_date
  ), scored as (
    select
      delivery_start,delivery_end,price_percentile,
      case when max_price<=min_price then 0.5
           else greatest(0.0,least(1.0,(price-min_price)/(max_price-min_price))) end as relative_peak,
      case when previous_price is null then 0.0
           else greatest(0.0,least(1.0,(price-previous_price)/greatest(abs(previous_price)*0.20,1.0))) end as positive_ramp
    from market_base
  ), market_signal as (
    select
      delivery_start,delivery_end,
      greatest(0.0,least(1.0,0.55*price_percentile+0.35*relative_peak+0.10*positive_ramp)) as pressure_score
    from scored
  ), assets as (
    select * from public.get_hydro_dispatch_active_assets_v1()
  )
  insert into public.water_forecast_values(
    forecast_run_id,station_id,water_body_id,reservoir_id,external_entity_key,
    source_entity_id,metric_code,valid_at,lead_hours,value,value_statistic,p25,p75,
    unit,confidence,quality_status,source_grid_lon,source_grid_lat,provenance,period_start,period_end
  )
  select
    v_run_id,null,a.water_body_id,a.reservoir_id,a.plant_key,
    a.plant_id::text,'hydro_dispatch_probability',s.delivery_start,
    greatest(0,floor(extract(epoch from(s.delivery_start-now()))/3600.0)::integer),
    round(greatest(0.10,least(0.85,0.10+0.75*s.pressure_score))::numeric,4),
    'probability',null,null,'ratio','low','validated',a.longitude,a.latitude,
    jsonb_build_object(
      'shadow',true,
      'cascade_key',a.cascade_key,
      'node_order',a.node_order,
      'plant_name',a.plant_name,
      'baraj_id',a.baraj_id,
      'baraj_name',a.baraj_name,
      'evidence_class','ESTIMATED',
      'confidence','low',
      'model','hydro_dispatch_ro_national_market_shadow_v1',
      'market_source','ENTSOE_DA_RO',
      'market_pressure_score',round(s.pressure_score::numeric,4),
      'market_only',true,
      'raw_price_exposed',false,
      'calibration_status','uncalibrated'
    ),
    s.delivery_start,s.delivery_end
  from market_signal s
  cross join assets a;

  get diagnostics v_inserted=row_count;

  if v_inserted<>v_expected_slots*v_asset_count then
    raise exception 'National shadow coverage mismatch: inserted %, expected %',
      v_inserted,v_expected_slots*v_asset_count;
  end if;

  return jsonb_build_object(
    'status','created',
    'delivery_date',v_delivery_date,
    'forecast_run_id',v_run_id,
    'market_intervals',v_market_count,
    'expected_intervals',v_expected_slots,
    'active_cascades',v_cascade_count,
    'active_assets',v_asset_count,
    'forecast_values',v_inserted,
    'expected_forecast_values',v_expected_slots*v_asset_count,
    'shadow',true,
    'confidence','low',
    'evidence_class','ESTIMATED'
  );
end;
$function$;

revoke all on function public.refresh_hydro_dispatch_national_shadow_v1(date) from public;
grant execute on function public.refresh_hydro_dispatch_national_shadow_v1(date) to service_role;

comment on function public.refresh_hydro_dispatch_national_shadow_v1(date) is
'Private national shadow baseline. Dynamically scores every asset in every active configured cascade for an exact, DST-complete ENTSO-E RO day. Does not replace production Olt RPCs.';


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
         count(*) filter(where not engine_configured)::integer
    into v_baraje,v_configured_baraje,v_unconfigured_baraje
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
    'schema_version','1.0.0',
    'checked_at',clock_timestamp(),
    'baraj_registry',jsonb_build_object(
      'total_baraje',v_baraje,
      'engine_configured_baraje',v_configured_baraje,
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

comment on function public.get_hydro_dispatch_national_foundation_health_v1() is
'Private P1 foundation health: canonical BARAJ coverage, active configured assets/cascades, and dynamic national shadow coverage.';
