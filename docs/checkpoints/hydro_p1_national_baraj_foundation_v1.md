# Hydro Dispatch P1 — National BARAJ Foundation v1

## Objective
Remove the architectural dependency on a fixed 15-CHE Olt list and establish one canonical `BARAJ` product identity while preserving separate technical `plant_id`, `dam_id`, `reservoir_id`, and `water_body_id` links in the backend.

## Product invariant
- Mobile/UI identity: **BARAJ** only.
- No separate user-facing Hydro/Lake/Reservoir identities for the same hydro complex.
- Backend keeps CHE, dam, reservoir, river and topology identities separately for inference and evidence.

## Production safety
- Current Olt Today/Tomorrow v3 contract is not replaced by this vertical.
- New national engine is **shadow only**.
- Raw market price remains backend-only.
- Shadow probabilities remain explicitly `ESTIMATED`, `low`, `uncalibrated`, and `market_only=true`.
- Exact delivery day must be DST-complete (92/96/100 PT15M slots).
- Forecast coverage must equal `active_assets × expected_slots` or the transaction fails.
- `water_forecast_values_single_entity_check` is respected: probabilities are indexed only by `external_entity_key`; BARAJ/reservoir/water-body links are provenance metadata.
- Refresh is idempotent by market + configured-asset fingerprint.

## Verified live state at implementation
- Canonical Olt BARAJ registry: 25
- Engine-configured BARAJE: 15
- Unconfigured Olt BARAJE: 10
- Active configured cascades: 1
- Active configured assets: 15
- Shadow validation delivery day: 2026-08-30
- ENTSO-E slots: 96/96
- Shadow forecast values: 1440/1440
- Re-run result: `already_current` (idempotency PASS)
- Existing production Today/Tomorrow v3 still returns 30 rows (15 Today + 15 Tomorrow).

## New contracts
- `get_hydro_dispatch_active_assets_v1()` — private dynamic configured-asset registry.
- `get_hydro_dispatch_baraj_registry_v1(country)` — canonical app-facing one-row-per-BARAJ identity contract.
- `refresh_hydro_dispatch_national_shadow_v1(date)` — private dynamic national shadow market baseline.
- `get_hydro_dispatch_national_foundation_health_v1()` — private foundation/coverage health.

## Next gate
Before adding the 10 remaining Olt complexes to an active cascade, verify their upstream/downstream sequence from canonical topology/official evidence. Do not infer order from names or geography alone. After Olt full-chain parity, add Romanian basins as data/configuration and keep the engine code unchanged.
