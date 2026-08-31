-- Hydro Dispatch P3 — multi-window BARAJ shadow v1
--
-- Extract every relevant dispatch episode from the dynamic national PT15M shadow.
-- This is deliberately shadow/private. It does not replace the current mobile RPC.
--
-- Hysteresis semantics:
--   * a window may START only on a strong slot >= start threshold;
--   * after start, it CONTINUES while slots remain >= continue threshold;
--   * one contiguous 15-minute dip may be bridged only if it remains >= gap floor
--     and both neighbouring slots satisfy the continue threshold;
--   * short episodes are discarded;
--   * consecutive D0/D+1 slots are processed as one timeline, so an episode may cross
--     local midnight without being artificially split.
--
-- Identity semantics: probabilities are collapsed to one BARAJ timeline. If a future
-- BARAJ has multiple linked CHE records, the slot-level BARAJ probability is the max
-- of its linked plant probabilities ("any generation at this hydro complex").

create or replace function public.get_hydro_dispatch_baraj_windows_shadow_v1(
  p_start_date date,
  p_days integer default 2,
  p_start_threshold double precision default 0.55,
  p_continue_threshold double precision default 0.47,
  p_gap_floor double precision default 0.35,
  p_min_duration_minutes integer default 30
)
returns table(
  baraj_id uuid,
  baraj_name text,
  basin_name text,
  river_name text,
  window_rank integer,
  window_start timestamptz,
  window_end timestamptz,
  duration_minutes integer,
  mean_probability double precision,
  peak_probability double precision,
  crosses_midnight boolean,
  hydro_plant_count integer,
  confidence text,
  evidence_class text,
  model_version text
)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
begin
  if p_start_date is null then
    raise exception 'p_start_date is required';
  end if;
  if p_days<1 or p_days>3 then
    raise exception 'p_days must be between 1 and 3';
  end if;
  if p_start_threshold<=0 or p_start_threshold>1
     or p_continue_threshold<0 or p_continue_threshold>1
     or p_gap_floor<0 or p_gap_floor>1 then
    raise exception 'probability thresholds must be within 0..1';
  end if;
  if p_start_threshold<=p_continue_threshold then
    raise exception 'start threshold must be greater than continue threshold';
  end if;
  if p_continue_threshold<p_gap_floor then
    raise exception 'continue threshold must be >= gap floor';
  end if;
  if p_min_duration_minutes<15 or p_min_duration_minutes>360
     or mod(p_min_duration_minutes,15)<>0 then
    raise exception 'p_min_duration_minutes must be a 15-minute multiple between 15 and 360';
  end if;

  return query
  with requested_dates as (
    select (p_start_date+g)::date as delivery_date
    from generate_series(0,p_days-1) g
  ), ranked_runs as (
    select
      d.delivery_date,
      r.id as forecast_run_id,
      row_number() over(
        partition by d.delivery_date
        order by r.run_at desc,r.created_at desc,r.id desc
      ) as rn
    from requested_dates d
    join public.water_forecast_runs r
      on r.country_code='RO'
     and r.model_key='hydro_dispatch_ro_national_market_shadow_v1'
     and r.quality_status in ('validated','corrected')
    where exists (
      select 1
      from public.water_forecast_values v
      where v.forecast_run_id=r.id
        and v.metric_code='hydro_dispatch_probability'
        and (v.valid_at at time zone 'Europe/Bucharest')::date=d.delivery_date
    )
  ), selected_runs as (
    select delivery_date,forecast_run_id
    from ranked_runs
    where rn=1
  ), slot_probabilities as (
    select
      a.baraj_id,
      max(a.baraj_name) as baraj_name,
      max(a.basin_name) as basin_name,
      max(a.river_name) as river_name,
      v.valid_at,
      max(coalesce(v.period_end,v.valid_at+interval '15 minutes')) as period_end,
      max(v.value::double precision) as probability,
      count(distinct a.plant_id)::integer as hydro_plant_count
    from selected_runs rr
    join public.water_forecast_values v
      on v.forecast_run_id=rr.forecast_run_id
     and v.metric_code='hydro_dispatch_probability'
     and (v.valid_at at time zone 'Europe/Bucharest')::date=rr.delivery_date
    join public.get_hydro_dispatch_active_assets_v1() a
      on a.plant_key=v.external_entity_key
    where a.baraj_id is not null
      and v.value is not null
      and v.value>=0 and v.value<=1
    group by a.baraj_id,v.valid_at
  ), base_flags as (
    select
      s.*,
      (s.probability>=p_start_threshold) as strong_slot,
      (s.probability>=p_continue_threshold) as continue_slot
    from slot_probabilities s
  ), neighbour_flags as (
    select
      b.*,
      lag(b.continue_slot) over(partition by b.baraj_id order by b.valid_at) as previous_continue,
      lead(b.continue_slot) over(partition by b.baraj_id order by b.valid_at) as next_continue,
      lag(b.period_end) over(partition by b.baraj_id order by b.valid_at) as previous_end,
      lead(b.valid_at) over(partition by b.baraj_id order by b.valid_at) as next_start
    from base_flags b
  ), effective_flags as (
    select
      n.*,
      (
        n.continue_slot
        or (
          n.probability>=p_gap_floor
          and coalesce(n.previous_continue,false)
          and coalesce(n.next_continue,false)
          and n.previous_end=n.valid_at
          and n.next_start=n.period_end
        )
      ) as effective_continue
    from neighbour_flags n
  ), boundaries as (
    select
      e.*,
      case
        when e.effective_continue
         and (
           not coalesce(lag(e.effective_continue) over(partition by e.baraj_id order by e.valid_at),false)
           or lag(e.period_end) over(partition by e.baraj_id order by e.valid_at)<>e.valid_at
         )
        then 1 else 0
      end as starts_group
    from effective_flags e
  ), grouped as (
    select
      b.*,
      sum(b.starts_group) over(
        partition by b.baraj_id
        order by b.valid_at
        rows between unbounded preceding and current row
      )::integer as group_id
    from boundaries b
  ), anchors as (
    select
      g.baraj_id,
      g.group_id,
      min(g.valid_at) filter(where g.strong_slot and g.effective_continue) as first_strong_at
    from grouped g
    where g.effective_continue
    group by g.baraj_id,g.group_id
  ), active_episode_slots as (
    select g.*
    from grouped g
    join anchors a
      on a.baraj_id=g.baraj_id
     and a.group_id=g.group_id
    where g.effective_continue
      and a.first_strong_at is not null
      and g.valid_at>=a.first_strong_at
  ), episodes as (
    select
      e.baraj_id,
      max(e.baraj_name) as baraj_name,
      max(e.basin_name) as basin_name,
      max(e.river_name) as river_name,
      e.group_id,
      min(e.valid_at) as window_start,
      max(e.period_end) as window_end,
      round(avg(e.probability)::numeric,4)::double precision as mean_probability,
      round(max(e.probability)::numeric,4)::double precision as peak_probability,
      max(e.hydro_plant_count)::integer as hydro_plant_count
    from active_episode_slots e
    group by e.baraj_id,e.group_id
  ), qualified as (
    select
      ep.*,
      (extract(epoch from(ep.window_end-ep.window_start))/60.0)::integer as duration_minutes
    from episodes ep
    where extract(epoch from(ep.window_end-ep.window_start))/60.0>=p_min_duration_minutes
  ), ranked as (
    select
      q.*,
      row_number() over(partition by q.baraj_id order by q.window_start,q.window_end)::integer as window_rank
    from qualified q
  )
  select
    r.baraj_id,
    r.baraj_name,
    r.basin_name,
    r.river_name,
    r.window_rank,
    r.window_start,
    r.window_end,
    r.duration_minutes,
    r.mean_probability,
    r.peak_probability,
    ((r.window_start at time zone 'Europe/Bucharest')::date
      <> ((r.window_end-interval '1 microsecond') at time zone 'Europe/Bucharest')::date) as crosses_midnight,
    r.hydro_plant_count,
    'low'::text as confidence,
    'ESTIMATED'::text as evidence_class,
    '0.1.0-national-shadow-hysteresis'::text as model_version
  from ranked r
  order by r.baraj_name,r.window_start;
end;
$function$;

revoke all on function public.get_hydro_dispatch_baraj_windows_shadow_v1(date,integer,double precision,double precision,double precision,integer) from public;
grant execute on function public.get_hydro_dispatch_baraj_windows_shadow_v1(date,integer,double precision,double precision,double precision,integer) to service_role;

comment on function public.get_hydro_dispatch_baraj_windows_shadow_v1(date,integer,double precision,double precision,double precision,integer) is
'Private shadow multi-window extractor over exact PT15M national Hydro forecasts. One BARAJ identity; all qualifying chronological episodes are returned, including cross-midnight episodes when both delivery days exist.';


create or replace function public.get_hydro_dispatch_multiwindow_shadow_health_v1(
  p_start_date date,
  p_days integer default 2
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_role text;
  v_configured integer := 0;
  v_total_windows integer := 0;
  v_baraje_with_windows integer := 0;
  v_cross_midnight integer := 0;
  v_max_per_baraj integer := 0;
  v_dates_ready integer := 0;
  v_date_status jsonb := '[]'::jsonb;
begin
  v_role := coalesce(
    nullif(current_setting('request.jwt.claim.role',true),''),
    auth.jwt()->>'role',
    case when session_user in ('service_role','postgres') then session_user end
  );
  if v_role not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  if p_start_date is null then raise exception 'p_start_date is required'; end if;
  if p_days<1 or p_days>3 then raise exception 'p_days must be between 1 and 3'; end if;

  select count(*)::integer into v_configured
  from public.get_hydro_dispatch_baraj_registry_v1('RO')
  where engine_configured;

  with requested_dates as (
    select (p_start_date+g)::date as delivery_date
    from generate_series(0,p_days-1) g
  ), coverage as (
    select
      d.delivery_date,
      (
        extract(epoch from(
          (((d.delivery_date+1)::date)::timestamp at time zone 'Europe/Bucharest')
          - ((d.delivery_date::date)::timestamp at time zone 'Europe/Bucharest')
        ))/900
      )::integer as expected_slots,
      coalesce((
        select count(distinct v.valid_at)::integer
        from public.water_forecast_runs r
        join public.water_forecast_values v on v.forecast_run_id=r.id
        where r.country_code='RO'
          and r.model_key='hydro_dispatch_ro_national_market_shadow_v1'
          and r.quality_status in ('validated','corrected')
          and v.metric_code='hydro_dispatch_probability'
          and (v.valid_at at time zone 'Europe/Bucharest')::date=d.delivery_date
          and r.id=(
            select r2.id
            from public.water_forecast_runs r2
            where r2.country_code='RO'
              and r2.model_key='hydro_dispatch_ro_national_market_shadow_v1'
              and r2.quality_status in ('validated','corrected')
              and exists(
                select 1 from public.water_forecast_values v2
                where v2.forecast_run_id=r2.id
                  and v2.metric_code='hydro_dispatch_probability'
                  and (v2.valid_at at time zone 'Europe/Bucharest')::date=d.delivery_date
              )
            order by r2.run_at desc,r2.created_at desc,r2.id desc
            limit 1
          )
      ),0) as actual_slots
    from requested_dates d
  )
  select
    count(*) filter(where actual_slots=expected_slots)::integer,
    jsonb_agg(jsonb_build_object(
      'date',delivery_date,
      'expected_slots',expected_slots,
      'actual_slots',actual_slots,
      'ready',actual_slots=expected_slots
    ) order by delivery_date)
  into v_dates_ready,v_date_status
  from coverage;

  with w as (
    select *
    from public.get_hydro_dispatch_baraj_windows_shadow_v1(p_start_date,p_days)
  ), per_baraj as (
    select baraj_id,count(*)::integer as windows
    from w
    group by baraj_id
  )
  select
    (select count(*)::integer from w),
    (select count(*)::integer from per_baraj),
    (select count(*)::integer from w where crosses_midnight),
    coalesce((select max(windows)::integer from per_baraj),0)
  into v_total_windows,v_baraje_with_windows,v_cross_midnight,v_max_per_baraj;

  return jsonb_build_object(
    'schema_version','1.0.0',
    'checked_at',clock_timestamp(),
    'start_date',p_start_date,
    'days',p_days,
    'configured_baraje',v_configured,
    'delivery_dates_ready',v_dates_ready,
    'delivery_dates_requested',p_days,
    'date_coverage',coalesce(v_date_status,'[]'::jsonb),
    'total_windows',v_total_windows,
    'baraje_with_windows',v_baraje_with_windows,
    'cross_midnight_windows',v_cross_midnight,
    'max_windows_per_baraj',v_max_per_baraj,
    'window_limit_applied',false,
    'model_version','0.1.0-national-shadow-hysteresis'
  );
end;
$function$;

revoke all on function public.get_hydro_dispatch_multiwindow_shadow_health_v1(date,integer) from public;
grant execute on function public.get_hydro_dispatch_multiwindow_shadow_health_v1(date,integer) to service_role;

comment on function public.get_hydro_dispatch_multiwindow_shadow_health_v1(date,integer) is
'Private multi-window shadow coverage/episode health for one to three consecutive Romanian delivery days.';
