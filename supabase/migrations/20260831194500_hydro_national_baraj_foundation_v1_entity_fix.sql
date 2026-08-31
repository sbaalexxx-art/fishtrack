-- P1 repair: water_forecast_values permits exactly one canonical entity column.
-- Hydro Dispatch probabilities are indexed by external_entity_key (plant canonical key).
-- BARAJ/reservoir/water-body links remain explicit provenance metadata.

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
    v_source_id,'RO','hydro_dispatch_ro_national_market_shadow_v1','0.1.1-shadow-market-baseline','scenario',
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
      'entity_contract','external_entity_key_only',
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
    v_run_id,null,null,null,a.plant_key,
    a.plant_id::text,'hydro_dispatch_probability',s.delivery_start,
    greatest(0,floor(extract(epoch from(s.delivery_start-now()))/3600.0)::integer),
    round(greatest(0.10,least(0.85,0.10+0.75*s.pressure_score))::numeric,4),
    'probability',null,null,'ratio','low','validated',a.longitude,a.latitude,
    jsonb_build_object(
      'shadow',true,
      'cascade_key',a.cascade_key,
      'node_order',a.node_order,
      'plant_id',a.plant_id,
      'plant_name',a.plant_name,
      'baraj_id',a.baraj_id,
      'baraj_name',a.baraj_name,
      'reservoir_id',a.reservoir_id,
      'water_body_id',a.water_body_id,
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
