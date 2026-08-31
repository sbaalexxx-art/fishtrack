-- Hydro Dispatch runtime health v2
-- Separates exact-day forecast availability from optional/realtime source health.
-- A stale Actual Hydro or radar signal may degrade NOWCAST confidence, but must
-- not make an already-built exact-day market forecast disappear.

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

  select (
    extract(epoch from (
      (((v_today + 1)::date)::timestamp at time zone 'Europe/Bucharest')
      - ((v_today::date)::timestamp at time zone 'Europe/Bucharest')
    )) / 900
  )::integer into v_today_slots;

  select (
    extract(epoch from (
      (((v_tomorrow + 1)::date)::timestamp at time zone 'Europe/Bucharest')
      - ((v_tomorrow::date)::timestamp at time zone 'Europe/Bucharest')
    )) / 900
  )::integer into v_tomorrow_slots;

  select count(distinct m.delivery_start)::integer
    into v_today_market
  from public.hydro_dispatch_market_observations m
  where m.source_key='ENTSOE_DA_RO'
    and m.market_zone='RO'
    and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_today;

  select count(distinct m.delivery_start)::integer
    into v_tomorrow_market
  from public.hydro_dispatch_market_observations m
  where m.source_key='ENTSOE_DA_RO'
    and m.market_zone='RO'
    and (m.delivery_start at time zone 'Europe/Bucharest')::date=v_tomorrow;

  select r.id into v_today_run
  from public.water_forecast_runs r
  where r.country_code='RO'
    and r.model_key='hydro_dispatch_olt_market_v1'
    and r.quality_status in ('validated','corrected')
    and exists (
      select 1
      from public.water_forecast_values v
      where v.forecast_run_id=r.id
        and v.metric_code='hydro_dispatch_probability'
        and (v.valid_at at time zone 'Europe/Bucharest')::date=v_today
    )
  order by r.run_at desc,r.created_at desc
  limit 1;

  if v_today_run is not null then
    select count(distinct (v.external_entity_key,v.valid_at))::integer
      into v_today_forecast
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
      select 1
      from public.water_forecast_values v
      where v.forecast_run_id=r.id
        and v.metric_code='hydro_dispatch_probability'
        and (v.valid_at at time zone 'Europe/Bucharest')::date=v_tomorrow
    )
  order by r.run_at desc,r.created_at desc
  limit 1;

  if v_tomorrow_run is not null then
    select count(distinct (v.external_entity_key,v.valid_at))::integer
      into v_tomorrow_forecast
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
    v_actual_status := 'fresh';
    v_actual_source := 'ENTSOE_ACTUAL_GEN_RO';
  elsif v_entsoe_actual_at is not null and v_entsoe_actual_at>=v_now-interval '6 hours' then
    v_actual_status := 'recent';
    v_actual_source := 'ENTSOE_ACTUAL_GEN_RO';
  elsif v_tran_actual_at is not null and v_tran_actual_at>=v_now-interval '90 minutes' then
    v_actual_status := 'fallback_fresh';
    v_actual_source := 'TRANSELECTRICA_SEN';
  elsif v_entsoe_actual_at is not null or v_tran_actual_at is not null then
    v_actual_status := 'stale';
    v_actual_source := null;
  else
    v_actual_status := 'unavailable';
    v_actual_source := null;
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
    when v_actual_status in ('fresh','recent','fallback_fresh') and v_radar_status in ('fresh','recent') then 'ready'
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
        'slots',v_today_market,
        'expected_slots',v_today_slots
      ),
      'tomorrow',jsonb_build_object(
        'date',v_tomorrow,
        'status',v_market_tomorrow_status,
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

revoke all on function public.get_hydro_dispatch_runtime_health_v2() from public;
grant execute on function public.get_hydro_dispatch_runtime_health_v2() to service_role;
