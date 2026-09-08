# PR18 Weather Shadow v1

Status: development only  
Branch: feature/pr18-weather-shadow-v1  
Production impact: NONE

## Verified production baseline

PR18 production currently serves Weather through Supabase Edge Function weather-canonical.

Observed contract:

- canonical version: weather-canonical-v1
- selected source: met_norway_locationforecast_v2
- cache TTL: 30 minutes
- stale/LKG window: 12 hours
- JWT verification: enabled
- current output shape: current + hourly + daily + hazards + source_ids + resolution + cache
- no production multi-model fusion is active

Weather alert evaluation is a separate path and runs every 15 minutes. It is not modified by this branch.

## Safety rule

The existing weather-canonical function remains the production authority until a shadow candidate demonstrates a statistically significant improvement.

This branch MUST NOT:

- modify production weather-canonical
- deploy weather-canonical-shadow
- change Flutter contracts
- change cache semantics
- modify Hydro/Water/R2
- replace Weather alerts
- write shadow output into production canonical tables

## Shadow architecture

Provider adapters
-> normalized forecast candidates
-> correlation-family control
-> freshness + availability + skill weighting
-> robust outlier suppression
-> fused scalar forecast
-> uncertainty/confidence
-> verification against real observations
-> provider score by variable / region / season / horizon

Observation, radar and lightning channels are evidence sources. They are not counted as independent NWP model votes.

## Independence rule

Multiple products from the same forecasting center or a derived product can be strongly correlated.

For confidence, PR18 uses correlation families. Examples:

- MET Norway global guidance + ECMWF IFS/AIFS: capped as ECMWF-center family until empirical error correlation proves otherwise
- GFS + GEFS: NOAA-center family
- ICON-EU: DWD-center family

This prevents false confidence from counting correlated forecasts as independent confirmations.

## Initial metrics

Continuous variables:
- MAE
- RMSE
- bias
- availability
- freshness

Precipitation probability:
- Brier score
- reliability/calibration
- POD
- FAR
- CSI

Probabilistic/ensemble:
- CRPS when available
- spread-skill relationship

Timing:
- precipitation onset error
- precipitation end error

## Dynamic scoring dimensions

Provider skill is measured separately by:

- variable
- forecast horizon bucket
- geographic region
- season
- provider/model version

Initial horizon buckets:

- 0-6h
- 6-12h
- 12-24h
- 24-48h
- 48-72h
- 3-5d
- 5-7d
- 7d+

## Promotion gate

A new fused forecast can replace production only after:

1. schema/contract compatibility
2. provider legal/commercial validation
3. source health + retry + circuit-breaker design
4. sufficient verified samples
5. no regression in safety-critical variables
6. statistically better or non-inferior primary metrics
7. stable latency and backend cost
8. LKG/fallback test
9. shadow run with zero production writes
10. explicit production promotion

Until then MET Norway production remains unchanged.
