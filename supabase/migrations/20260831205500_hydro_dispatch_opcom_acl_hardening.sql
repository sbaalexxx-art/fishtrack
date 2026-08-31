-- Keep Hydro Dispatch market evidence and refresh controls service-role only.
revoke all on function public.refresh_hydro_dispatch_olt_pilot_v3(date) from public, anon, authenticated;
revoke all on function public.refresh_hydro_dispatch_national_shadow_v2(date) from public, anon, authenticated;
revoke all on function public.ingest_hydro_dispatch_market_v2(jsonb) from public, anon, authenticated;
revoke all on function public.get_hydro_dispatch_runtime_health_v2() from public, anon, authenticated;

grant execute on function public.refresh_hydro_dispatch_olt_pilot_v3(date) to service_role;
grant execute on function public.refresh_hydro_dispatch_national_shadow_v2(date) to service_role;
grant execute on function public.ingest_hydro_dispatch_market_v2(jsonb) to service_role;
grant execute on function public.get_hydro_dispatch_runtime_health_v2() to service_role;
