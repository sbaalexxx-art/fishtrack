# Hydro Dispatch P2 — National Shadow Auto-Refresh v1 — PASS

## Objective
Make the national shadow forecast part of the exact ENTSO-E market ingest transaction so a valid Day-Ahead delivery day updates both the existing Olt production pilot and the dynamic national shadow automatically.

## Invariants
- `ingest_hydro_dispatch_market_v2` remains backward-compatible: existing `refresh` key still contains the Olt pilot refresh.
- ENTSO-E input must contain exactly one source and one Romanian delivery date per call.
- National shadow is refreshed for that exact target date, never a neighbouring date.
- National shadow must return `created` or `already_current`.
- Shadow coverage must equal `expected_forecast_values` or the ingest transaction fails.
- OPCOM legacy/dev input does not feed the ENTSO-E-only national shadow model.
- Raw market price remains private.

## Live idempotent validation
Re-ingested the already stored exact ENTSO-E day 2026-08-30 through the production ingest function.

Result:
- affected market rows: 96
- input source: `ENTSOE_DA_RO`
- delivery date: `2026-08-30`
- legacy Olt refresh: `already_current`, 96 slots, 1440 values
- national shadow: `already_current`, 25 assets, 96 slots, 2400/2400 values
- no neighbouring-day fallback
- no duplicate shadow forecast run

## PASS
The database side of P2 is complete. The collector production guard is updated in the collector repository as a separate gate so D+1 PASS also verifies national shadow coverage.
