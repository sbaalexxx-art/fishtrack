begin;

-- W4E-1A: enforce least-privilege access after Supabase default grants.
-- Operational observations remain append-only for service_role collectors.

revoke all privileges
  on table public.water_data_sources
  from service_role;

grant select, insert, update, delete
  on table public.water_data_sources
  to service_role;


revoke all privileges
  on table public.water_operational_observations
  from service_role;

grant select, insert
  on table public.water_operational_observations
  to service_role;


revoke all privileges
  on table public.water_community_observations
  from service_role;

grant select, insert, update, delete
  on table public.water_community_observations
  to service_role;


-- Reassert that raw source and operational tables remain inaccessible
-- to public mobile roles.
revoke all privileges
  on table public.water_data_sources
  from public, anon, authenticated;

revoke all privileges
  on table public.water_operational_observations
  from public, anon, authenticated;


-- Preserve the authenticated Community Pulse contract.
revoke all privileges
  on table public.water_community_observations
  from public, anon, authenticated;

grant select
  on table public.water_community_observations
  to authenticated;

grant insert (
  report_id,
  station_id,
  water_body_id,
  dam_id,
  reservoir_id,
  observed_at,
  observed_at_precision,
  flow_state,
  level_trend,
  operation_signal,
  water_clarity,
  fish_activity,
  species_name,
  bait_or_lure,
  fishing_method,
  catch_count
)
on table public.water_community_observations
to authenticated;

commit;
