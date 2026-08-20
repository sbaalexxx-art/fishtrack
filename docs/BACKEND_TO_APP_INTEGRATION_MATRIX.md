# FluviAI Backend → App Integration Matrix

This file is a release gate, not a wishlist.

A backend capability is **not considered complete for product delivery** until it has a real mobile contract, a reachable app flow, loading/error/retry behavior where applicable, localization where user-facing, and physical-device QA.

## Global rule

For every production backend capability:

1. Source/collector or authoritative backend logic is saved in GitHub/Supabase.
2. Public/mobile-safe RPC or table contract exists; raw/private data stays server-side.
3. Flutter has a typed service/repository contract.
4. Riverpod/controller state owns loading/cache/error/retry and mutations.
5. The existing approved UI is connected without redesign unless explicitly approved.
6. Navigation/deep-link context resolves the real entity.
7. Free/Premium and country-pack eligibility are enforced where applicable.
8. RO/EN copy is localized for visible product states.
9. No fabricated values or hardcoded operational truth.
10. Android/iOS build gates pass and Samsung SM-S928B physical QA is recorded before CLOSED/PASS.

Any row marked `BACKEND ONLY`, `MOBILE CONTRACT`, or `UI OPEN` keeps the product checkpoint OPEN.

## Hydro Dispatch Olt P3/P4

| Backend capability | Canonical backend contract | Flutter integration | Current status |
|---|---|---|---|
| Today + tomorrow dispatch probability | `get_hydro_dispatch_olt_today_tomorrow_v3` | `HydroDispatchService.getTodayTomorrow` + `HydroDispatchMobileController` | MOBILE CONTRACT |
| Sanitized AI explanation context | `get_hydro_dispatch_olt_ai_context_v1` | `HydroDispatchService.getAiContext` + controller | MOBILE CONTRACT |
| Community observed state | `get_hydro_dispatch_olt_observed_state_v1` | included in AI/product context; detail UI connection pending | MOBILE CONTRACT |
| Explicit observed-event feedback | `submit_hydro_dispatch_observation_v1` | `HydroDispatchService.submitObservedEvent` | MOBILE CONTRACT / REPORT FLOW OPEN |
| Start field validation | `start_hydro_dispatch_field_validation_v1` | `HydroDispatchService.startFieldValidation` + controller | MOBILE CONTRACT / UI OPEN |
| Active field validation | `get_my_active_hydro_dispatch_field_validation_v1` | `HydroDispatchService.getActiveFieldValidation` + controller | MOBILE CONTRACT / UI OPEN |
| Finish field validation | `finish_hydro_dispatch_field_validation_v1` | `HydroDispatchService.finishFieldValidation` + controller | MOBILE CONTRACT / UI OPEN |
| Hydro alert create/update | `upsert_hydro_dispatch_alert_rule_v1` | `HydroDispatchService.upsertAlertRule` + controller | MOBILE CONTRACT / UI OPEN |
| Hydro alert delete | `delete_hydro_dispatch_alert_rule_v1` | `HydroDispatchService.deleteAlertRule` + controller | MOBILE CONTRACT / UI OPEN |
| Hydro alert evaluator | `evaluate_hydro_dispatch_alerts_v1` cron 5 min | server-side; mobile consumes resulting notifications | BACKEND ACTIVE |
| Push dispatcher | Supabase Edge Function `push-dispatcher` + cron 1 min | existing `FirebasePushService` | BACKEND PASS / DEVICE QA OPEN |
| FCM device registration | `register_notification_device_v1` | existing `FirebasePushService._registerCurrentToken` | CONNECTED / DEVICE QA OPEN |
| Push deep-link to CHE | notification `entity_type=hydropower_plant`, `entity_id=plant_id` | `MainNavigation._routePushOpened` → real CHE state → `SelectedContext` → hydropower route | CONNECTED / DEVICE QA OPEN |
| Canonical CHE saved item | `saved_items.item_type='hydropower_plant'` | `SavedItemsService.canonicalItemType` compatibility bridge | CONNECTED |
| ML calibration dataset | `get_hydro_dispatch_olt_calibration_dataset_v1` | intentionally server-only training contract | SERVER ONLY BY DESIGN |
| ML calibration summary | `get_hydro_dispatch_olt_calibration_summary_v1` | mobile exposure only when product UI needs calibrated status | BACKEND PASS / PRODUCT DISPLAY OPEN |

## Existing app infrastructure reused

- Firebase Core / Messaging / Crashlytics / Analytics / Performance from recovery baseline.
- `SelectedContext` is the canonical entity/context bridge.
- `AppNavigator` remains the canonical navigation path.
- Existing Mapbox runtime and Hydro Intelligence UI remain the presentation base.
- Existing notification inbox/preferences remain the user notification control center.
- Existing `SavedItemsService` remains the saved/favorites storage bridge.

## P4D release gate

P4D cannot be CLOSED/PASS until all of the following are true:

- [x] Correct recovery implementation base selected.
- [x] Firebase Messaging client present and initialized.
- [x] P3/P4 typed Flutter service added.
- [x] Riverpod P4 state/controller added.
- [x] Hydropower saved-item type canonicalized.
- [x] Hydropower push deep-link resolves a real CHE with safe inbox fallback.
- [x] Existing hydropower route bound to P4 state without redesign.
- [ ] Today/Tomorrow product data is visible in the existing CHE/Water flow.
- [ ] Hydro Alert action creates/disables the real P4 rule.
- [ ] Report flow can submit explicit turbining observed events.
- [ ] Field validation UI uses real current GPS and start/finish RPCs.
- [ ] AI/Fluvi explanation reads sanitized P4 AI context only.
- [ ] Loading/cache/error/retry behavior is visible and verified.
- [ ] RO/EN user-facing strings are complete.
- [ ] Free/Premium behavior is verified against product rules.
- [ ] Flutter format/analyze/tests pass.
- [ ] Android build/install pass.
- [ ] Samsung SM-S928B: FCM token registration PASS.
- [ ] Samsung SM-S928B: real push received PASS.
- [ ] Samsung SM-S928B: tapping Hydro push opens correct CHE PASS.
- [ ] Samsung SM-S928B: Hydro Today/Tomorrow/Alert/field validation functional PASS.
- [ ] Product/Visual review PASS.

## Non-negotiable data-truth rules

- National hydro/market signals never become claims that a specific CHE is currently generating.
- `ESTIMATED`, `DERIVED`, `MEASURED`, and `OBSERVED` remain distinct in mobile presentation.
- Community observations are field evidence, not official measurements.
- Missing community reports never become negative ML labels.
- Raw market prices, raw MW values, credentials and private payloads never enter mobile RPC/UI contracts.
- A `NOT_YET_PUBLISHED` tomorrow forecast must display as unavailable/not yet published, never as `0%`.
