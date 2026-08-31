# Hydro Dispatch P4 — Arges Shadow Foundation — PASS

## Objective
Prove that the national Hydro foundation can accept a materially different Romanian basin without changing the current production/mobile contract or forcing the Olt 1:1 topology onto Arges.

## Product identity
Mobile identity remains **BARAJ** only. CHE, reservoir, diversion plants and secondary transfers are private technical entities.

## Arges BARAJ spine (shadow)
11 dam-linked forecast assets, ordered on the canonical ANAR Arges topology:

1. Vidraru — seq 6
2. Oiesti / CHE Oesti — seq 13
3. Cerbureni — seq 17
4. Curtea de Arges — seq 23
5. Zigoneni — seq 29
6. Valcele — seq 34
7. Budeasa — seq 39
8. Bascov — seq 43
9. Prundu / technical CHE Pitesti — seq 49
10. Golesti — seq 52
11. Mihailesti — seq 68

All 11 have high-confidence source-supplied dam/reservoir relations. Prundu/Pitesti is deliberately medium-confidence on technical alias semantics while the UI identity remains Baraj Prundu.

## Why Arges differs from Olt
Official Hidroelectrica documentation shows that Arges is not a simple one-dam/one-CHE chain:
- Vidraru is a large storage/peak plant (220 MW, 4 Francis units).
- Vidraru tailrace feeds the Oiesti reservoir and the cascade continues toward Mihailesti.
- Downstream plants include remote-dam, dam-type and diversion plants.
- Technical diversion nodes include Albesti, Valea Iasului, Noaptes, Baiculesti, Manicesti and Merisani.
- Doamnei–Valea cu Pesti and Topolog–Cumpana are important secondary headraces to the Vidraru scheme.

Therefore P4 adds a private hydraulic graph instead of flattening these relationships into UI objects.

## Private hydraulic graph
Graph key: `ro:arges:vidraru-mihailesti-hydraulic-shadow-v1`

- 19 nodes total
- 11 BARAJ asset nodes
- 6 hidden diversion-plant nodes
- 2 secondary-transfer nodes
- 18 hydraulic/routing edges
- same-graph edge endpoints enforced by PostgreSQL composite foreign keys
- routing lag values intentionally NULL/unparameterized
- no invented travel-time minutes

## Live DB validation
`get_hydro_dispatch_arges_shadow_health_v1()`:
- `baraj_forecast_assets = 11`
- `hydraulic_graph_nodes = 19`
- `hydraulic_graph_edges = 18`
- `hidden_diversion_nodes = 6`
- `secondary_transfer_nodes = 2`
- `parameterized_routing_edges = 0`
- `local_operational_observations = 0`
- `canonical_live_stations = 0`
- `dispatch_supported = false`
- `production_contract_changed = false`

National shadow after Arges:
- active cascades: 2
- active BARAJ forecast assets: 36
- 2026-08-30 ENTSO-E coverage: 96/96 PT15M
- forecast values: 3456/3456 (36 × 96)
- idempotent second run: `already_current`

P3 multi-window regression with 2026-08-29/30:
- configured BARAJE: 36
- baraje with windows: 36
- total windows: 144
- max windows per BARAJ: 4
- cross-midnight windows: 36
- no window-limit truncation

Legacy production regression:
- `get_hydro_dispatch_olt_today_tomorrow_v3()` remains exactly 30 rows
- 15 Today + 15 Tomorrow
- node order remains 1..15

## Accuracy finding
The current national shadow is still a common market-prior baseline. Therefore Vidraru, Oiesti, Prundu and Olt assets such as Frunzaru currently receive identical candidate windows for the same market day. This is expected and is now empirically demonstrated.

P4 proves cross-basin architecture and topology handling only. It does NOT claim Arges dispatch accuracy.

## Next model-quality gates
- Arges local level/flow source integration
- basin/catchment precipitation forecast and radar features
- Vidraru reservoir/availability state
- hydraulic travel-time estimation/calibration
- plant/BARAJ-specific probability model
- backtesting and calibration before `dispatch_supported=true`
