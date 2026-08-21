-- Canonicalize ABA basin presentation without modifying raw ANAR source values.

create or replace function public.water_basin_canonical_key_v1(p_name text)
returns text
language sql immutable
set search_path = public,pg_temp
as $$
select case
  when public.water_search_normalize_v1(p_name) like '%arges%vedea%' then 'arges-vedea'
  when public.water_search_normalize_v1(p_name) like '%buzau%ialomita%' then 'buzau-ialomita'
  when public.water_search_normalize_v1(p_name) like '%somes%tisa%' then 'somes-tisa'
  when public.water_search_normalize_v1(p_name) like '%prut%barlad%' then 'prut-barlad'
  when public.water_search_normalize_v1(p_name) like '%dobrogea%litoral%' then 'dobrogea-litoral'
  when public.water_search_normalize_v1(p_name) like '%crisuri%' then 'crisuri'
  when public.water_search_normalize_v1(p_name) like '%mures%' then 'mures'
  when public.water_search_normalize_v1(p_name) like '%siret%' then 'siret'
  when public.water_search_normalize_v1(p_name) like '%banat%' then 'banat'
  when public.water_search_normalize_v1(p_name) like '%jiu%' then 'jiu'
  when public.water_search_normalize_v1(p_name) like '%olt%' then 'olt'
  else regexp_replace(public.water_search_normalize_v1(p_name),'[^a-z0-9]+','-','g')
end;
$$;

create or replace function public.water_basin_display_name_v1(p_name text)
returns text
language sql immutable
set search_path = public,pg_temp
as $$
select case public.water_basin_canonical_key_v1(p_name)
  when 'arges-vedea' then 'A.B.A. Argeș-Vedea'
  when 'buzau-ialomita' then 'A.B.A. Buzău-Ialomița'
  when 'somes-tisa' then 'A.B.A. Someș-Tisa'
  when 'prut-barlad' then 'A.B.A. Prut-Bârlad'
  when 'dobrogea-litoral' then 'A.B.A. Dobrogea-Litoral'
  when 'crisuri' then 'A.B.A. Crișuri'
  when 'mures' then 'A.B.A. Mureș'
  when 'siret' then 'A.B.A. Siret'
  when 'banat' then 'A.B.A. Banat'
  when 'jiu' then 'A.B.A. Jiu'
  when 'olt' then 'A.B.A. Olt'
  else public.water_display_text_v1(p_name)
end;
$$;

revoke all on function public.water_basin_canonical_key_v1(text) from public,anon;
revoke all on function public.water_basin_display_name_v1(text) from public,anon;
grant execute on function public.water_basin_canonical_key_v1(text) to authenticated,service_role;
grant execute on function public.water_basin_display_name_v1(text) to authenticated,service_role;

drop function if exists public.get_hydro_map_basins_v1(text);
create function public.get_hydro_map_basins_v1(p_country_code text default 'RO')
returns table(
  basin_key text,basin_name text,reservoir_count integer,anchored_site_count integer,
  geometry_only_count integer,hydropower_verified_count integer,dispatch_available_count integer
)
language sql stable security definer
set search_path = public,pg_temp
as $$
with s as (
  select *,public.water_basin_canonical_key_v1(basin_name) canonical_basin_key
  from public.get_hydro_map_sites_v1(p_country_code,true,1000)
)
select s.canonical_basin_key,
  public.water_basin_display_name_v1(min(s.basin_name)) basin_name,
  count(*)::integer,
  count(*) filter(where s.pin_eligible)::integer,
  count(*) filter(where not s.pin_eligible)::integer,
  count(*) filter(where s.hydropower_verified)::integer,
  count(*) filter(where s.dispatch_available)::integer
from s
group by s.canonical_basin_key
order by count(*) desc,basin_name;
$$;

revoke all on function public.get_hydro_map_basins_v1(text) from public,anon;
grant execute on function public.get_hydro_map_basins_v1(text) to authenticated,service_role;
