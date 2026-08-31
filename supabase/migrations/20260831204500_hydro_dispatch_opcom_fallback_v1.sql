-- Hydro Dispatch production resilience: official OPCOM PZU exact-day fallback.
-- ENTSO-E remains preferred. OPCOM is accepted only as a complete PT15M source
-- for the exact Europe/Bucharest product date. Raw market prices remain private.

create or replace function public.refresh_hydro_dispatch_olt_pilot_v3(
  p_delivery_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth, pg_temp
as $function$
declare
  v_source_id uuid;
  v_delivery_date date;
  v_market_source text;
  v_count integer;
  v_expected_slots integer;
  v_run_id uuid;
  v_fingerprint text;
  v_existing uuid;
  v_inserted integer := 0;
  v_min_start timestamptz;
  v_max_end timestamptz;
  v_model_version text;
begin
  select id into v_source_id
  from public.water_data_sources
  where source_key='fluviai-hydro-dispatch-v1' and is_active=true
  order by created_at desc
  limit 1;
  if v_source_id is null then
    raise exception 'Missing active data source fluviai-hydro-dispatch-v1';
  end if;

  with candidates as (
    select
      m.source_key,
      (m.delivery_start at time zone 'Europe/Bucharest')::date as delivery_date,
      count(distinct m.delivery_start)::integer as cnt,
      min(m.delivery_start) as min_start,
      max(m.delivery_end) as max_end,
      (extract(epoch from (
        ((((m.delivery_start at time zone 'Europe/Bucharest')::date + 1)::timestamp at time zone 'Europe/Bucharest') -
         (((m.delivery_start at time zone 'Europe/Bucharest')::date)::timestamp at time zone 'Europe/Bucharest'))
      ))/900)::integer as expected_slots
    from public.hydro_dispatch_market_observations m
    where m.market_zone='RO'
      and m.source_key in ('ENTSOE_DA_RO','OPCOM_PZU')
    group by m.source_key,(m.delivery_start at time zone 'Europe/Bucharest')::date
  )
  select c.delivery_date,c.source_key,c.cnt,c.expected_slots,c.min_start,c.max_end
    into v_delivery_date,v_market_source,v_count,v_expected_slots,v_min_start,v_max_end
  from candidates c
  where c.cnt=c.expected_slots
    and (p_delivery_date is null or c.delivery_date=p_delivery_date)
  order by c.delivery_date desc,
           case c.source_key when 'ENTSOE_DA_RO' then 0 else 1 end
  limit 1;

  if v_delivery_date is null then
    return jsonb_build_object(
      'status','no_complete_market_day',
      'delivery_date',p_delivery_date,
      'forecast_values',0
    );
  end if;

  v_model_version := case
    when v_market_source='ENTSOE_DA_RO' then '1.2.0-entsoe-exact-target'
    else '1.1.0-opcom-production-fallback'
  end;

  select encode(
    digest(
      'hydro_dispatch_olt_market_v1|' || v_market_source || '|' || v_delivery_date::text || '|' ||
      string_agg(source_record_fingerprint,',' order by delivery_start),
      'sha256'
    ),'hex'
  ) into v_fingerprint
  from public.hydro_dispatch_market_observations
  where source_key=v_market_source
    and market_zone='RO'
    and (delivery_start at time zone 'Europe/Bucharest')::date=v_delivery_date;

  select id into v_existing
  from public.water_forecast_runs
  where country_code='RO'
    and model_key='hydro_dispatch_olt_market_v1'
    and source_record_fingerprint=v_fingerprint
  order by created_at desc
  limit 1;

  if v_existing is not null then
    select count(*)::integer into v_inserted
    from public.water_forecast_values
    where forecast_run_id=v_existing
      and metric_code='hydro_dispatch_probability';
    if v_inserted<>v_expected_slots*15 then
      raise exception 'Existing Olt Hydro forecast coverage mismatch for %',v_delivery_date;
    end if;
    return jsonb_build_object(
      'status','already_current',
      'delivery_date',v_delivery_date,
      'market_source',v_market_source,
      'forecast_run_id',v_existing,
      'market_intervals',v_count,
      'expected_intervals',v_expected_slots,
      'forecast_values',v_inserted,
      'expected_forecast_values',v_expected_slots*15
    );
  end if;

  insert into public.water_forecast_runs (
    source_id,country_code,model_key,model_version,forecast_kind,
    run_at,fetched_at,horizon_hours,spatial_resolution_km,ensemble_size,
    quality_status,source_record_id,source_record_fingerprint,provenance
  ) values (
    v_source_id,'RO','hydro_dispatch_olt_market_v1',v_model_version,'scenario',
    now(),now(),greatest(0,ceil(extract(epoch from (v_max_end-v_min_start))/3600.0)::integer),
    null,null,'validated',v_market_source || ':' || v_delivery_date::text,v_fingerprint,
    jsonb_build_object(
      'cascade_key','ro:olt:ramnicu-valcea-izbiceni',
      'evidence_class','ESTIMATED',
      'confidence','low',
      'driver','day_ahead_market',
      'market_source',v_market_source,
      'raw_price_exposed',false,
      'calibration_status','uncalibrated',
      'source_preference',case
        when v_market_source='ENTSOE_DA_RO' then 'primary_open_data'
        else 'official_market_operator_fallback'
      end,
      'warning','Market pressure is a signal, not proof that a specific CHE will operate.'
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
    where m.source_key=v_market_source
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
  ), nodes as (
    select n.node_order,h.id as plant_id,h.canonical_key,h.name as plant_name
    from public.hydro_dispatch_cascades c
    join public.hydro_dispatch_cascade_nodes n on n.cascade_id=c.id
    join public.hydropower_plants h on h.id=n.plant_id
    where c.canonical_key='ro:olt:ramnicu-valcea-izbiceni'
      and c.is_active=true
  )
  insert into public.water_forecast_values (
    forecast_run_id,station_id,water_body_id,reservoir_id,external_entity_key,
    source_entity_id,metric_code,valid_at,lead_hours,value,value_statistic,p25,p75,
    unit,confidence,quality_status,source_grid_lon,source_grid_lat,provenance,period_start,period_end
  )
  select
    v_run_id,null,null,null,n.canonical_key,n.plant_id::text,
    'hydro_dispatch_probability',s.delivery_start,
    greatest(0,floor(extract(epoch from (s.delivery_start-now()))/3600.0)::integer),
    round((greatest(0.10,least(0.85,0.10+0.75*s.pressure_score)))::numeric,4),
    'probability',null,null,'ratio','low','validated',null,null,
    jsonb_build_object(
      'cascade_key','ro:olt:ramnicu-valcea-izbiceni',
      'node_order',n.node_order,
      'plant_name',n.plant_name,
      'evidence_class','ESTIMATED',
      'confidence','low',
      'model','hydro_dispatch_olt_market_v1',
      'market_source',v_market_source,
      'market_pressure_score',round(s.pressure_score::numeric,4),
      'market_only',true,
      'raw_price_exposed',false,
      'calibration_status','uncalibrated'
    ),
    s.delivery_start,s.delivery_end
  from market_signal s
  cross join nodes n;

  get diagnostics v_inserted=row_count;
  if v_inserted<>v_expected_slots*15 then
    raise exception 'Olt Hydro forecast coverage mismatch: inserted %, expected %',
      v_inserted,v_expected_slots*15;
  end if;

  return jsonb_build_object(
    'status','created',
    'delivery_date',v_delivery_date,
    'market_source',v_market_source,
    'forecast_run_id',v_run_id,
    'market_intervals',v_count,
    'expected_intervals',v_expected_slots,
    'cascade_nodes',15,
    'forecast_values',v_inserted,
    'expected_forecast_values',v_expected_slots*15,
    'confidence','low',
    'evidence_class','ESTIMATED'
  );
end;
$function$;

create or replace function public.refresh_hydro_dispatch_national_shadow_v2(
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
  v_market_source text;
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

  with candidates as (
    select
      m.source_key,
      (m.delivery_start at time zone 'Europe/Bucharest')::date as delivery_date,
      count(distinct m.delivery_start)::integer as cnt,
      min(m.delivery_start) as min_start,
      max(m.delivery_end) as max_end,
      (extract(epoch from (
        ((((m.delivery_start at time zone 'Europe/Bucharest')::date + 1)::timestamp at time zone 'Europe/Bucharest') -
         (((m.delivery_start at time zone 'Europe/Bucharest')::date)::timestamp at time zone 'Europe/Bucharest'))
      ))/900)::integer as expected_slots
    from public.hydro_dispatch_market_observations m
    where m.market_zone='RO'
      and m.source_key in ('ENTSOE_DA_RO','OPCOM_PZU')
    group by m.source_key,(m.delivery_start at time zone 'Europe/Bucharest')::date
  )
  select c.delivery_date,c.source_key,c.cnt,c.expected_slots,c.min_start,c.max_end
    into v_delivery_date,v_market_source,v_market_count,v_expected_slots,v_min_start,v_max_end
  from candidates c
  where c.cnt=c.expected_slots
    and (p_delivery_date is null or c.delivery_date=p_delivery_date)
  order by c.delivery_date desc,
           case c.source_key when 'ENTSOE_DA_RO' then 0 else 1 end
  limit 1;

  if v_delivery_date is null then
    return jsonb_build_object(
      'status','no_complete_market_day',
      'delivery_date',p_delivery_date,
      'forecast_values',0,
      'shadow',true
    );
  end if;

  select encode(digest(string_agg(m.source_record_fingerprint,',' order by m.delivery_start),'sha256'),'hex')
    into v_market_fingerprint
  from public.hydro_dispatch_market_observations m
  where m.source_key=v_market_source
    and m.market_zone='RO'
    and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_delivery_date;

  select encode(digest(string_agg(
      a.cascade_key||':'||a.node_order::text||':'||a.plant_id::text||':'||coalesce(a.baraj_id::text,'-'),
      ',' order by a.cascade_key,a.node_order,a.plant_id
    ),'sha256'),'hex')
    into v_asset_fingerprint
  from public.get_hydro_dispatch_active_assets_v1() a;

  v_fingerprint := encode(digest(
    'hydro_dispatch_ro_national_shadow_v2|'||v_market_source||'|'||v_delivery_date::text||'|'||
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
    if v_existing_values<>v_expected_slots*v_asset_count then
      raise exception 'Existing national Hydro shadow coverage mismatch for %',v_delivery_date;
    end if;
    return jsonb_build_object(
      'status','already_current',
      'delivery_date',v_delivery_date,
      'market_source',v_market_source,
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
    v_source_id,'RO','hydro_dispatch_ro_national_market_shadow_v1',
    case when v_market_source='ENTSOE_DA_RO' then '0.2.0-shadow-entsoe' else '0.2.0-shadow-opcom-fallback' end,
    'scenario',now(),now(),
    greatest(0,ceil(extract(epoch from(v_max_end-v_min_start))/3600.0)::integer),
    null,null,'validated',v_market_source||':'||v_delivery_date::text,v_fingerprint,
    jsonb_build_object(
      'scope','national_configured_cascades',
      'shadow',true,
      'evidence_class','ESTIMATED',
      'confidence','low',
      'driver','day_ahead_market',
      'market_source',v_market_source,
      'raw_price_exposed',false,
      'calibration_status','uncalibrated',
      'active_cascades',v_cascade_count,
      'active_assets',v_asset_count,
      'entity_contract','external_entity_key_only',
      'source_preference',case when v_market_source='ENTSOE_DA_RO' then 'primary_open_data' else 'official_market_operator_fallback' end,
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
    where m.source_key=v_market_source
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
      'market_source',v_market_source,
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
    'market_source',v_market_source,
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

create or replace function public.ingest_hydro_dispatch_market_v2(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_affected integer := 0;
  v_refresh jsonb;
  v_national_shadow jsonb;
  v_input_source text;
  v_source_count integer := 0;
  v_target_date date;
  v_day_count integer := 0;
  v_shadow_status text;
begin
  if jsonb_typeof(p_rows)<>'array' then
    raise exception 'p_rows must be a JSON array';
  end if;
  if jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>200 then
    raise exception 'p_rows length must be between 1 and 200';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_rows) as r(
      source_key text,market_zone text,delivery_start timestamptz,delivery_end timestamptz,
      price numeric,currency text,unit text,observed_at timestamptz,source_url text,
      source_record_fingerprint text,raw_payload jsonb
    )
    where r.source_key not in ('ENTSOE_DA_RO','OPCOM_PZU')
       or r.market_zone<>'RO'
       or (r.source_key='ENTSOE_DA_RO' and r.currency<>'EUR')
       or (r.source_key='OPCOM_PZU' and r.currency<>'RON')
       or r.unit<>'MWh'
       or r.delivery_start is null
       or r.delivery_end is null
       or r.delivery_end<=r.delivery_start
       or r.price is null
       or r.source_record_fingerprint !~ '^[0-9a-f]{64}$'
       or jsonb_typeof(coalesce(r.raw_payload,'{}'::jsonb))<>'object'
  ) then
    raise exception 'Invalid Hydro Dispatch day-ahead market payload';
  end if;

  select
    count(distinct r.source_key)::integer,
    min(r.source_key),
    count(distinct (r.delivery_start at time zone 'Europe/Bucharest')::date)::integer,
    min((r.delivery_start at time zone 'Europe/Bucharest')::date)
  into v_source_count,v_input_source,v_day_count,v_target_date
  from jsonb_to_recordset(p_rows) as r(
    source_key text,market_zone text,delivery_start timestamptz,delivery_end timestamptz,
    price numeric,currency text,unit text,observed_at timestamptz,source_url text,
    source_record_fingerprint text,raw_payload jsonb
  );

  if v_source_count<>1 then
    raise exception 'Hydro Dispatch market ingest requires exactly one source per call';
  end if;
  if v_day_count<>1 or v_target_date is null then
    raise exception 'Hydro Dispatch market ingest requires exactly one Romanian delivery date per call';
  end if;

  insert into public.hydro_dispatch_market_observations(
    source_key,market_zone,delivery_start,delivery_end,price,currency,unit,
    observed_at,fetched_at,source_url,source_record_fingerprint,raw_payload
  )
  select
    r.source_key,r.market_zone,r.delivery_start,r.delivery_end,r.price,r.currency,r.unit,
    coalesce(r.observed_at,now()),now(),r.source_url,r.source_record_fingerprint,
    coalesce(r.raw_payload,'{}'::jsonb)
  from jsonb_to_recordset(p_rows) as r(
    source_key text,market_zone text,delivery_start timestamptz,delivery_end timestamptz,
    price numeric,currency text,unit text,observed_at timestamptz,source_url text,
    source_record_fingerprint text,raw_payload jsonb
  )
  on conflict (source_key,market_zone,delivery_start) do update
  set delivery_end=excluded.delivery_end,
      price=excluded.price,
      currency=excluded.currency,
      unit=excluded.unit,
      observed_at=excluded.observed_at,
      fetched_at=now(),
      source_url=excluded.source_url,
      source_record_fingerprint=excluded.source_record_fingerprint,
      raw_payload=excluded.raw_payload;

  get diagnostics v_affected=row_count;

  v_refresh := public.refresh_hydro_dispatch_olt_pilot_v3(v_target_date);
  if coalesce(v_refresh->>'status','') not in ('created','already_current') then
    raise exception 'Olt Hydro exact-target refresh failed for %: %',v_target_date,coalesce(v_refresh::text,'null');
  end if;
  if coalesce((v_refresh->>'delivery_date')::date,date '1900-01-01')<>v_target_date then
    raise exception 'Olt Hydro exact-target refresh mismatch: expected %, got %',v_target_date,v_refresh->>'delivery_date';
  end if;
  if coalesce((v_refresh->>'forecast_values')::integer,-1)
     <>coalesce((v_refresh->>'expected_forecast_values')::integer,-2) then
    raise exception 'Olt Hydro exact-target coverage mismatch for %',v_target_date;
  end if;

  v_national_shadow := public.refresh_hydro_dispatch_national_shadow_v2(v_target_date);
  v_shadow_status := coalesce(v_national_shadow->>'status','');
  if v_shadow_status not in ('created','already_current') then
    raise exception 'National Hydro shadow refresh failed for %: %',v_target_date,coalesce(v_national_shadow::text,'null');
  end if;
  if coalesce((v_national_shadow->>'delivery_date')::date,date '1900-01-01')<>v_target_date then
    raise exception 'National Hydro shadow target mismatch: expected %, got %',v_target_date,v_national_shadow->>'delivery_date';
  end if;
  if coalesce((v_national_shadow->>'forecast_values')::integer,-1)
     <>coalesce((v_national_shadow->>'expected_forecast_values')::integer,-2) then
    raise exception 'National Hydro shadow coverage mismatch for %',v_target_date;
  end if;

  return jsonb_build_object(
    'status','ok',
    'affected_market_rows',v_affected,
    'input_source',v_input_source,
    'delivery_date',v_target_date,
    'refresh',v_refresh,
    'national_shadow',v_national_shadow
  );
end;
$function$;

create or replace function public.get_hydro_dispatch_runtime_health_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_today date := (clock_timestamp() at time zone 'Europe/Bucharest')::date;
  v_tomorrow date := ((clock_timestamp() at time zone 'Europe/Bucharest')::date + 1);
  v_hour integer := extract(hour from (clock_timestamp() at time zone 'Europe/Bucharest'))::integer;
  v_today_slots integer;
  v_tomorrow_slots integer;
  v_today_market integer := 0;
  v_tomorrow_market integer := 0;
  v_today_market_source text;
  v_tomorrow_market_source text;
  v_today_run uuid;
  v_tomorrow_run uuid;
  v_today_forecast integer := 0;
  v_tomorrow_forecast integer := 0;
  v_entsoe_actual_at timestamptz;
  v_tran_actual_at timestamptz;
  v_radar_at timestamptz;
  v_market_today_status text;
  v_market_tomorrow_status text;
  v_forecast_today_status text;
  v_forecast_tomorrow_status text;
  v_actual_status text;
  v_actual_source text;
  v_radar_status text;
  v_forecast_product_status text;
  v_nowcast_status text;
  v_overall_status text;
  v_reasons jsonb := '[]'::jsonb;
begin
  if coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    auth.jwt()->>'role',
    case when session_user in ('service_role','postgres') then session_user end
  ) not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;

  select (extract(epoch from (
    ((((v_today + 1)::date)::timestamp at time zone 'Europe/Bucharest') -
     ((v_today::date)::timestamp at time zone 'Europe/Bucharest'))
  ))/900)::integer into v_today_slots;
  select (extract(epoch from (
    ((((v_tomorrow + 1)::date)::timestamp at time zone 'Europe/Bucharest') -
     ((v_tomorrow::date)::timestamp at time zone 'Europe/Bucharest'))
  ))/900)::integer into v_tomorrow_slots;

  select x.source_key,x.slots
    into v_today_market_source,v_today_market
  from (
    select m.source_key,count(distinct m.delivery_start)::integer as slots
    from public.hydro_dispatch_market_observations m
    where m.market_zone='RO'
      and m.source_key in ('ENTSOE_DA_RO','OPCOM_PZU')
      and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_today
    group by m.source_key
  ) x
  order by (x.slots=v_today_slots) desc,x.slots desc,
           case x.source_key when 'ENTSOE_DA_RO' then 0 else 1 end
  limit 1;
  v_today_market := coalesce(v_today_market,0);

  select x.source_key,x.slots
    into v_tomorrow_market_source,v_tomorrow_market
  from (
    select m.source_key,count(distinct m.delivery_start)::integer as slots
    from public.hydro_dispatch_market_observations m
    where m.market_zone='RO'
      and m.source_key in ('ENTSOE_DA_RO','OPCOM_PZU')
      and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_tomorrow
    group by m.source_key
  ) x
  order by (x.slots=v_tomorrow_slots) desc,x.slots desc,
           case x.source_key when 'ENTSOE_DA_RO' then 0 else 1 end
  limit 1;
  v_tomorrow_market := coalesce(v_tomorrow_market,0);

  select r.id into v_today_run
  from public.water_forecast_runs r
  where r.country_code='RO'
    and r.model_key='hydro_dispatch_olt_market_v1'
    and r.quality_status in ('validated','corrected')
    and exists (
      select 1 from public.water_forecast_values v
      where v.forecast_run_id=r.id
        and v.metric_code='hydro_dispatch_probability'
        and (v.valid_at at time zone 'Europe/Bucharest')::date=v_today
    )
  order by r.run_at desc,r.created_at desc
  limit 1;
  if v_today_run is not null then
    select count(distinct (v.external_entity_key,v.valid_at))::integer into v_today_forecast
    from public.water_forecast_values v
    where v.forecast_run_id=v_today_run
      and v.metric_code='hydro_dispatch_probability'
      and (v.valid_at at time zone 'Europe/Bucharest')::date=v_today;
  end if;

  select r.id into v_tomorrow_run
  from public.water_forecast_runs r
  where r.country_code='RO'
    and r.model_key='hydro_dispatch_olt_market_v1'
    and r.quality_status in ('validated','corrected')
    and exists (
      select 1 from public.water_forecast_values v
      where v.forecast_run_id=r.id
        and v.metric_code='hydro_dispatch_probability'
        and (v.valid_at at time zone 'Europe/Bucharest')::date=v_tomorrow
    )
  order by r.run_at desc,r.created_at desc
  limit 1;
  if v_tomorrow_run is not null then
    select count(distinct (v.external_entity_key,v.valid_at))::integer into v_tomorrow_forecast
    from public.water_forecast_values v
    where v.forecast_run_id=v_tomorrow_run
      and v.metric_code='hydro_dispatch_probability'
      and (v.valid_at at time zone 'Europe/Bucharest')::date=v_tomorrow;
  end if;

  select max(o.observed_at) into v_entsoe_actual_at
  from public.hydro_dispatch_system_observations o
  where o.source_key='ENTSOE_ACTUAL_GEN_RO'
    and o.metric_code='hydro_generation_mw';
  select max(o.observed_at) into v_tran_actual_at
  from public.hydro_dispatch_system_observations o
  where o.source_key='TRANSELECTRICA_SEN'
    and o.metric_code='hydro_generation_mw';
  select max(o.observed_at) into v_radar_at
  from public.hydro_dispatch_local_signal_observations o
  where o.source_key='ro-anm-radar-composite'
    and o.metric_code='radar_rain_proxy_score';

  v_market_today_status := case
    when v_today_market=v_today_slots then 'ready'
    when v_today_market>0 then 'partial'
    else 'missing'
  end;
  v_market_tomorrow_status := case
    when v_tomorrow_market=v_tomorrow_slots then 'ready'
    when v_tomorrow_market>0 then 'partial'
    when v_hour<16 then 'pending_publication'
    else 'missing_after_cutoff'
  end;
  v_forecast_today_status := case
    when v_today_forecast=v_today_slots*15 then 'ready'
    when v_today_forecast>0 then 'partial'
    else 'missing'
  end;
  v_forecast_tomorrow_status := case
    when v_tomorrow_forecast=v_tomorrow_slots*15 then 'ready'
    when v_tomorrow_forecast>0 then 'partial'
    when v_hour<16 then 'pending_publication'
    else 'missing_after_cutoff'
  end;

  if v_entsoe_actual_at is not null and v_entsoe_actual_at>=v_now-interval '3 hours' then
    v_actual_status := 'fresh'; v_actual_source := 'ENTSOE_ACTUAL_GEN_RO';
  elsif v_entsoe_actual_at is not null and v_entsoe_actual_at>=v_now-interval '6 hours' then
    v_actual_status := 'recent'; v_actual_source := 'ENTSOE_ACTUAL_GEN_RO';
  elsif v_tran_actual_at is not null and v_tran_actual_at>=v_now-interval '90 minutes' then
    v_actual_status := 'fallback_fresh'; v_actual_source := 'TRANSELECTRICA_SEN';
  elsif v_entsoe_actual_at is not null or v_tran_actual_at is not null then
    v_actual_status := 'stale'; v_actual_source := null;
  else
    v_actual_status := 'unavailable'; v_actual_source := null;
  end if;

  v_radar_status := case
    when v_radar_at is null then 'unavailable'
    when v_radar_at>=v_now-interval '45 minutes' then 'fresh'
    when v_radar_at>=v_now-interval '120 minutes' then 'recent'
    else 'stale'
  end;

  v_forecast_product_status := case
    when v_forecast_today_status<>'ready' then 'unavailable'
    when v_forecast_tomorrow_status='ready' then 'ready'
    else 'degraded'
  end;
  v_nowcast_status := case
    when v_forecast_today_status<>'ready' then 'unavailable'
    when v_actual_status in ('fresh','recent','fallback_fresh')
      and v_radar_status in ('fresh','recent') then 'ready'
    else 'degraded'
  end;

  if v_forecast_today_status<>'ready' then
    v_reasons := v_reasons || jsonb_build_array('forecast_today_not_ready');
  end if;
  if v_market_today_status<>'ready' then
    v_reasons := v_reasons || jsonb_build_array('market_today_not_ready');
  end if;
  if v_forecast_tomorrow_status='missing_after_cutoff' then
    v_reasons := v_reasons || jsonb_build_array('forecast_tomorrow_missing_after_cutoff');
  elsif v_forecast_tomorrow_status='partial' then
    v_reasons := v_reasons || jsonb_build_array('forecast_tomorrow_partial');
  end if;
  if v_actual_status in ('stale','unavailable') then
    v_reasons := v_reasons || jsonb_build_array('actual_hydro_not_fresh');
  end if;
  if v_radar_status in ('stale','unavailable') then
    v_reasons := v_reasons || jsonb_build_array('radar_not_fresh');
  end if;

  v_overall_status := case
    when v_forecast_product_status='unavailable' then 'unavailable'
    when v_forecast_product_status='degraded' or v_nowcast_status='degraded' then 'degraded'
    else 'healthy'
  end;

  return jsonb_build_object(
    'schema_version','2.0.0',
    'checked_at',v_now,
    'romania_date',v_today,
    'status',v_overall_status,
    'reasons',v_reasons,
    'product',jsonb_build_object(
      'forecast',v_forecast_product_status,
      'nowcast',v_nowcast_status,
      'today_exact_forecast_serving',v_forecast_today_status='ready',
      'tomorrow_exact_forecast_serving',v_forecast_tomorrow_status='ready',
      'truth_rule','Realtime source degradation changes confidence/nowcast, not an existing exact-day forecast.'
    ),
    'market',jsonb_build_object(
      'today',jsonb_build_object(
        'date',v_today,
        'status',v_market_today_status,
        'source',v_today_market_source,
        'slots',v_today_market,
        'expected_slots',v_today_slots
      ),
      'tomorrow',jsonb_build_object(
        'date',v_tomorrow,
        'status',v_market_tomorrow_status,
        'source',v_tomorrow_market_source,
        'slots',v_tomorrow_market,
        'expected_slots',v_tomorrow_slots,
        'hard_cutoff_hour_ro',16
      )
    ),
    'forecast',jsonb_build_object(
      'today',jsonb_build_object(
        'status',v_forecast_today_status,
        'forecast_run_id',v_today_run,
        'values',v_today_forecast,
        'expected_values',v_today_slots*15
      ),
      'tomorrow',jsonb_build_object(
        'status',v_forecast_tomorrow_status,
        'forecast_run_id',v_tomorrow_run,
        'values',v_tomorrow_forecast,
        'expected_values',v_tomorrow_slots*15
      )
    ),
    'sources',jsonb_build_object(
      'actual_hydro',jsonb_build_object(
        'status',v_actual_status,
        'selected_source',v_actual_source,
        'entsoe_latest_at',v_entsoe_actual_at,
        'transelectrica_latest_at',v_tran_actual_at
      ),
      'radar',jsonb_build_object(
        'status',v_radar_status,
        'latest_at',v_radar_at,
        'source','ro-anm-radar-composite'
      )
    )
  );
end;
$function$;

revoke all on function public.refresh_hydro_dispatch_olt_pilot_v3(date) from public;
revoke all on function public.refresh_hydro_dispatch_national_shadow_v2(date) from public;
revoke all on function public.ingest_hydro_dispatch_market_v2(jsonb) from public;
revoke all on function public.get_hydro_dispatch_runtime_health_v2() from public;

grant execute on function public.refresh_hydro_dispatch_olt_pilot_v3(date) to service_role;
grant execute on function public.refresh_hydro_dispatch_national_shadow_v2(date) to service_role;
grant execute on function public.ingest_hydro_dispatch_market_v2(jsonb) to service_role;
grant execute on function public.get_hydro_dispatch_runtime_health_v2() to service_role;
