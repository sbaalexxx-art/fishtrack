# Hydro Dispatch P1.1 — Olt Full-Chain Shadow v1 — PASS

## Objective
Extend the Olt topology from the existing 15-node Râmnicu Vâlcea → Izbiceni production pilot to the complete 25 canonical Olt hydro complexes in a separate shadow cascade, without changing the current mobile/production contract.

## Product identity
- UI identity remains one **BARAJ**.
- CHE, reservoir and water-body identifiers remain backend links only.
- `engine_configured` and `dispatch_supported` are separate states so shadow-only assets cannot be presented as production-ready.

## Topology evidence
The complete order was verified against official Hidroelectrica Olt documentation and canonical ANAR Olt segment sequence numbers.

Full shadow order:
`Voila → Vistea → Arpasu → Scoreiu → Avrig → Cornetu → Gura Lotrului → Turnu → Calimanesti → Daesti → Ramnicu Valcea → Raureni → Govora → Babeni → Ionesti → Zavideni → Dragasani → Strejesti → Arcesti → Slatina → Ipotesti → Draganesti → Frunzaru → Rusanesti → Izbiceni`.

Canonical ANAR sequence range: 101 → 238.

## Production isolation
- Existing cascade `ro:olt:ramnicu-valcea-izbiceni` remains active and unchanged at 15 nodes.
- New cascade `ro:olt:full-chain-shadow-v1` is `model_scope=shadow`, 25 nodes.
- Existing `get_hydro_dispatch_olt_today_tomorrow_v3()` remains exactly 30 rows: 15 Today + 15 Tomorrow.
- No new shadow-only BARAJ is marked `dispatch_supported`.

## Live validation
- BARAJ registry total: 25
- `engine_configured`: 25
- `dispatch_supported`: 15
- unconfigured: 0
- dynamic active assets: 25 unique plants
- preferred active cascade in national shadow: 1 full-chain shadow cascade
- validation delivery date: 2026-08-30
- ENTSO-E market coverage: 96/96 PT15M slots
- national shadow coverage: 2400/2400 values (25 × 96)
- second refresh: `already_current`
- foundation health: `coverage_complete=true`

## Defect caught during gate
Legacy production scope is named `hydro_dispatch_pilot`, not `pilot`. The first registry version therefore reported `dispatch_supported=0` while leaving the old production RPC untouched. The registry was repaired without renaming or mutating the legacy pilot. Final result is 15 supported + 10 shadow-only.

## PASS
P1.1 is closed only for topology/configuration and shadow coverage. It does **not** promote the extra 10 BARAJE to product probabilities. Promotion requires source/model quality, multi-window extraction and calibration gates.
