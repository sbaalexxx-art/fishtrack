-- Hydro Dispatch hydraulic graph integrity v1
-- Enforce at database level that each edge and both endpoint nodes belong to the
-- same hydraulic graph. This prevents cross-basin/cross-graph corruption as the
-- national engine expands.

alter table public.hydro_dispatch_hydraulic_nodes
  add constraint hydro_dispatch_hydraulic_nodes_graph_id_id_key
  unique (graph_id,id);

alter table public.hydro_dispatch_hydraulic_edges
  drop constraint if exists hydro_dispatch_hydraulic_edges_upstream_node_id_fkey;

alter table public.hydro_dispatch_hydraulic_edges
  drop constraint if exists hydro_dispatch_hydraulic_edges_downstream_node_id_fkey;

alter table public.hydro_dispatch_hydraulic_edges
  add constraint hydro_dispatch_hydraulic_edges_upstream_same_graph_fkey
  foreign key (graph_id,upstream_node_id)
  references public.hydro_dispatch_hydraulic_nodes(graph_id,id)
  on delete cascade;

alter table public.hydro_dispatch_hydraulic_edges
  add constraint hydro_dispatch_hydraulic_edges_downstream_same_graph_fkey
  foreign key (graph_id,downstream_node_id)
  references public.hydro_dispatch_hydraulic_nodes(graph_id,id)
  on delete cascade;

alter table public.hydro_dispatch_hydraulic_edges
  add constraint hydro_dispatch_hydraulic_edges_nominal_lag_bounds_check
  check (
    nominal_lag_minutes is null
    or (
      (lag_min_minutes is null or nominal_lag_minutes>=lag_min_minutes)
      and (lag_max_minutes is null or nominal_lag_minutes<=lag_max_minutes)
    )
  );
