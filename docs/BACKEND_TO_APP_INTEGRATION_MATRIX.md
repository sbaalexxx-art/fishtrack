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

Any row marked `BACKEND ONLY`, `MOBILE CONTRACT`, `UI OPEN`, or `QA OPEN` keeps the product checkpoint OPEN.

## Hydro Dispatch Olt P3/P4

| Backend capability | Canonical backend contract | Flutter integration | Current status |
|---|---|---|---|
| Today + tomorrow dispatch probability | `get_hydro_dispatch_olt_today_tomorrow_v3` | `HydroDispatchService.getTodayTomorrow` → `HydroDispatchMobileController` → `HydroDispatchFunctionalDock` | CONNECTED / QA OPEN |
| Sanitized AI explanation context | `get_hydro_dispatch_olt_ai_context_v1` | `HydroDispatchService.getAiContext` → controller → `HydroDispatchPresentation.aiExplanation` | CONNECTED / QA OPEN |
| Community observed state | `get_hydro_dispatch_olt_observed_state_v1` | consumed through sanitized AI/product context and shown separately from ESTIMATED evidence | CONNECTED / QA OPEN |
| Explicit observed-event feedback | `submit_hydro_dispatch_observation_v1` | canonical Community report → mounted `HydroDispatchRouteBridge` → optional event selection → `HydroDispatchService.submitObservedEvent` | CONNECTED / QA OPEN |
| Start field validation | `start_hydro_dispatch_field_validation_v1` | real `LocationService` GPS → controller → functional dock | CONNECTED / QA OPEN |
| Active field validation | `get_my_active_hydro_dispatch_field_validation_v1` | controller restores active session and prediction snapshot | CONNECTED / QA OPEN |
| Finish field validation | `finish_hydro_dispatch_field_validation_v1` | functional dock supports explicit negative/unknown; positive OBSERVED report can close active session | CONNECTED / QA OPEN |
| Hydro alert create/update | `upsert_hydro_dispatch_alert_rule_v1` | controller + functional dock toggle; Premium gated | CONNECTED / QA OPEN |
| Hydro alert delete | `delete_hydro_dispatch_alert_rule_v1` | controller + functional dock toggle | CONNECTED / QA OPEN |
| Hydro alert evaluator | `evaluate_hydro_dispatch_alerts_v1` cron 5 min | server-side; mobile consumes resulting notifications | BACKEND ACTIVE |
| Push dispatcher | Supabase Edge Function `push-dispatcher` + cron 1 min | existing `FirebasePushService` | BACKEND PASS / DEVICE QA OPEN |
| FCM device registration | `register_notification_device_v1` | existing `FirebasePushService._registerCurrentToken` | CONNECTED / DEVICE QA OPEN |
| Push deep-link to CHE | notification `entity_type=hydropower_plant`, `entity_id=plant_id` | `MainNavigation._routePushOpened` → real CHE state → `SelectedContext` → hydropower route | CONNECTED / DEVICE QA OPEN |
| Canonical CHE saved item | `saved_items.item_type='hydropower_plant'` | `SavedItemsService.canonicalItemType` compatibility bridge | CONNECTED |
| Hydro entry with no CHE selected | selected-context / map runtime | functional bridge offers Hydro România map selection instead of a dead empty utility | CONNECTED / QA OPEN |
| Free/Premium split | app entitlement contract | Free: Today + field/report contribution; Premium: Tomorrow + Hydro alerts + advanced Hydro explanation | CONNECTED / QA OPEN |
| Romania dispatch timezone | P3/P4 UTC timestamps | `HydroDispatchPresentation` renders forecast windows in `Europe/Bucharest`, independent of device timezone | CONNECTED / QA OPEN |
| ML calibration dataset | `get_hydro_dispatch_olt_calibration_dataset_v1` | intentionally server-only training contract | SERVER ONLY BY DESIGN |
| ML calibration summary | `get_hydro_dispatch_olt_calibration_summary_v1` | backend-ready; mobile exposure only when product presentation needs calibrated status | BACKEND PASS / PRODUCT DISPLAY OPEN |

## Existing app infrastructure reused

- Firebase Core / Messaging / Crashlytics / Analytics / Performance from recovery baseline.
- `SelectedContext` is the canonical entity/context bridge.
- `AppNavigator` remains the canonical navigation path.
- Existing Mapbox runtime and Hydro Intelligence UI remain the presentation base.
- Existing notification inbox/preferences remain the user notification control center.
- Existing `SavedItemsService` remains the saved/favorites storage bridge.
- Existing Community report publisher remains canonical; Hydro Dispatch only adds an optional post-publish OBSERVED association when the current route is a real CHE.
- Hydro Dispatch presentation is isolated from the approved page layout so tomorrow's UI/UX pass can polish presentation without rewriting utility logic.

## P4D implementation status

The utility wiring is now implemented. P4D remains OPEN only because compile/build/device/product gates still require evidence.

- [x] Correct recovery implementation base selected.
- [x] Firebase Messaging client present and initialized.
- [x] P3/P4 typed Flutter service added.
- [x] Riverpod P4 state/controller added.
- [x] Hydropower saved-item type canonicalized.
- [x] Hydropower push deep-link resolves a real CHE with safe inbox fallback.
- [x] Existing hydropower route bound to P4 state without redesign.
- [x] Today/Tomorrow product data connected to the CHE functional flow.
- [x] Hydro Alert action connected to the real P4 create/delete rule.
- [x] Report flow connected to explicit Hydro OBSERVED events.
- [x] Field validation connected to real GPS and start/active/finish RPCs.
- [x] Positive field observation can close an active validation through the OBSERVED report path.
- [x] AI/Fluvi Hydro explanation consumes only the sanitized P4 AI context.
- [x] Last-known-good/degraded refresh behavior prevents one auxiliary failure from hiding usable forecast/AI data.
- [x] User-facing P4 dock states have RO/EN variants.
- [x] Free/Premium P4 utility split implemented.
- [x] Hydro România selection fallback implemented when no CHE is selected.
- [x] Dedicated P4D Flutter gate workflow saved in GitHub.
- [ ] Flutter format/analyze/tests PASS evidence.
- [ ] Android build/install PASS.
- [ ] Samsung SM-S928B: FCM token registration PASS.
- [ ] Samsung SM-S928B: real push received PASS.
- [ ] Samsung SM-S928B: tapping Hydro push opens correct CHE PASS.
- [ ] Samsung SM-S928B: Hydro Today/Tomorrow/Alert/field validation functional PASS.
- [ ] Product/Visual polish review PASS.

## UI governance for next pass

- Current approved design remains the implementation base.
- No screen is rebuilt from scratch.
- Utility/backend wiring is not redesigned during visual polish.
- Tomorrow's controlled UI/UX work is presentation-only unless QA exposes a functional defect.
- The functional dock/presentation layer may be visually refined, resized or integrated more elegantly, but its production contracts and truth rules remain intact.

## Non-negotiable data-truth rules

- National hydro/market signals never become claims that a specific CHE is currently generating.
- `ESTIMATED`, `DERIVED`, `MEASURED`, and `OBSERVED` remain distinct in mobile presentation.
- Community observations are field evidence, not official measurements.
- Missing community reports never become negative ML labels.
- Raw market prices, raw MW values, credentials and private payloads never enter mobile RPC/UI contracts.
- A `NOT_YET_PUBLISHED` tomorrow forecast must display as unavailable/not yet published, never as `0%`.
- Romania Hydro Dispatch forecast windows are rendered in Romania local time, not blindly in the device timezone.
