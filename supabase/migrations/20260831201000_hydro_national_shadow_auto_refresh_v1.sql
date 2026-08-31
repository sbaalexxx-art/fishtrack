-- Hydro Dispatch P2 — national shadow auto-refresh v1
--
-- Extend the existing private market ingest transaction without changing the legacy
-- Olt refresh contract. An exact ENTSO-E RO delivery day now refreshes both:
--   1) the existing Olt production/pilot forecast, and
--   2) the dynamic national shadow forecast for that exact delivery date.
--
-- Raw market evidence remains private. OPCOM legacy/dev input keeps the old behavior
-- and does not feed the ENTSO-E-only national shadow model.

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

  -- Preserve the existing production refresh and response key for backward compatibility.
  v_refresh := public.refresh_hydro_dispatch_olt_pilot_v2();

  if v_input_source='ENTSOE_DA_RO' then
    v_national_shadow := public.refresh_hydro_dispatch_national_shadow_v1(v_target_date);
    v_shadow_status := coalesce(v_national_shadow->>'status','');

    if v_shadow_status not in ('created','already_current') then
      raise exception 'National Hydro shadow refresh failed for %: %',
        v_target_date,coalesce(v_national_shadow::text,'null');
    end if;

    if coalesce((v_national_shadow->>'delivery_date')::date,date '1900-01-01')<>v_target_date then
      raise exception 'National Hydro shadow target mismatch: expected %, got %',
        v_target_date,v_national_shadow->>'delivery_date';
    end if;

    if coalesce((v_national_shadow->>'forecast_values')::integer,-1)
       <>coalesce((v_national_shadow->>'expected_forecast_values')::integer,-2) then
      raise exception 'National Hydro shadow coverage mismatch for %',v_target_date;
    end if;
  else
    v_national_shadow := jsonb_build_object(
      'status','not_applicable_legacy_source',
      'delivery_date',v_target_date,
      'market_source',v_input_source,
      'shadow',true
    );
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

comment on function public.ingest_hydro_dispatch_market_v2(jsonb) is
'Private Hydro market ingest v2. Preserves the legacy Olt refresh and atomically refreshes the exact-date national shadow for ENTSO-E RO input. One source and one Romanian delivery date per call.';
