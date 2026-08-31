# Hydro Dispatch P3 — Multi-window BARAJ Shadow — Infrastructure PASS

## Scope
Private/shadow multi-window extraction over the national PT15M market-prior forecast. No mobile production promotion.

## Verified behavior
- One UI/product identity: BARAJ.
- 96 PT15M slots per normal Romanian delivery day.
- Strong start threshold + lower continue threshold (hysteresis).
- One controlled 15-minute gap bridge.
- Minimum episode duration.
- No top-1/top-3 truncation.
- Consecutive delivery days are processed as one timeline.
- Cross-midnight episodes remain continuous.

## Live validation
Dates: 2026-08-29 and 2026-08-30.
- 2/2 days complete at 96/96 slots.
- 25 configured Olt BARAJE.
- 25/25 produced qualifying episodes.
- 100 total episodes, maximum 4 per BARAJ.
- 25 episodes crossed local midnight.

Concrete example (Frunzaru; market-prior shadow only):
- 2026-08-29 00:00–02:45
- 2026-08-29 07:00–08:30
- 2026-08-29 17:30–2026-08-30 08:15 (cross-midnight)
- 2026-08-30 18:15–2026-08-31 00:00

## Accuracy limitation intentionally preserved
At this stage the national shadow is market-prior driven, so Olt BARAJE receive the same base probability curve and therefore identical candidate windows. This checkpoint validates extraction/temporal semantics only. It does NOT claim plant-specific accuracy or calibrated probabilities.

Plant/BARAJ-specific differentiation requires hydrology, plant/cascade constraints, meteorology, propagation and calibration gates before production promotion.

## PASS
P3 is closed for multi-window infrastructure only. The current mobile contract remains unchanged.
