-- Automatically promote every successfully inserted AFDJ staging batch
-- into the canonical append-only operational Water store.

create or replace function public.trigger_promote_afdj_staging_batch()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public.promote_afdj_water_level_observations();
  return null;
end;
$$;

revoke all
  on function public.trigger_promote_afdj_staging_batch()
  from public, anon, authenticated, service_role;

drop trigger if exists promote_afdj_staging_batch
  on public.water_observations_staging;

create trigger promote_afdj_staging_batch
after insert on public.water_observations_staging
for each statement
execute function public.trigger_promote_afdj_staging_batch();

-- Promote the fresh batch already written by the current GitHub workflow.
select public.promote_afdj_water_level_observations();

do $$
declare
  latest_batch_at timestamptz;
  latest_batch_rows integer;
  promoted_matches integer;
begin
  select max(ingested_at)
  into latest_batch_at
  from public.water_observations_staging
  where source = 'AFDJ'
    and country_code = 'RO';

  if latest_batch_at is null then
    raise exception 'AFDJ auto-promotion failed: no staging batch exists.';
  end if;

  select count(*)
  into latest_batch_rows
  from public.water_observations_staging
  where source = 'AFDJ'
    and country_code = 'RO'
    and ingested_at = latest_batch_at;

  if latest_batch_rows <> 23 then
    raise exception
      'AFDJ auto-promotion failed: latest batch contains % rows, expected 23.',
      latest_batch_rows;
  end if;

  select count(*)
  into promoted_matches
  from public.water_observations_staging staging
  join public.water_station_source_mappings mapping
    on mapping.source = staging.source
   and mapping.country_code = staging.country_code
   and mapping.source_station_id = staging.station_key
  join public.water_data_sources source_registry
    on source_registry.source_key = staging.source
   and source_registry.country_code = staging.country_code
  join public.water_operational_observations observation
    on observation.source_id = source_registry.id
   and observation.source_entity_id = staging.station_key
   and observation.station_id = mapping.station_id
   and observation.metric_code = 'water_level_cm'
   and observation.observed_at = staging.observed_at
   and observation.value = staging.water_level_cm
  where staging.source = 'AFDJ'
    and staging.country_code = 'RO'
    and staging.ingested_at = latest_batch_at;

  if promoted_matches <> 23 then
    raise exception
      'AFDJ auto-promotion failed: promoted matches %, expected 23.',
      promoted_matches;
  end if;
end;
$$;