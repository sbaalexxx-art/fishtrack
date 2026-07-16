-- A station identity and its coordinates may be known before a live Water
-- observation exists. Current readings remain in daily_water_snapshots and
-- are overlaid by providers at runtime.

alter table public.stations
  alter column level drop not null,
  alter column trend drop not null,
  alter column last_update drop not null;

insert into public.stations (id, name, river, latitude, longitude)
values
  ('afdj-drencova', 'Drencova', 'Dunărea', 44.6377707, 21.9723364),
  ('afdj-gruia', 'Gruia', 'Dunărea', 44.2665732, 22.7046852),
  ('afdj-cetate', 'Cetate', 'Dunărea', 44.1114259, 23.0475514),
  ('afdj-rast', 'Rast', 'Dunărea', 43.8851672, 23.2813472)
on conflict (id) do nothing;
