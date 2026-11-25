# Module 4 implementation and verification

## Baseline and scope

The implementation started from a clean `main` at
`60975aea13ddb62bb8bbb5bdccaedc641c88fdd7`
(`feat(auth): finalize registration and health profile`). The acceptance
review found the 23 tracked edits and six new files recorded in the original
Module 4 report. Local HEAD and the fetched `origin/main` matched that base.
This review uses
the SRS Module 4 extract supplied in the task and the issued SDS text mirrored
in the repository. A separate original SRS file was unavailable in this
workspace. The SRS and SDS were left unchanged.

The Resource Center retains its existing Flutter and Riverpod screens,
Firestore article repository, bundled verified catalogue, context weighting,
and Module 8 publishing authority. Its hospital directory retains the Google
Places repository, GPS service, profile-city fallback, Google Maps, and shared
launcher. The catalogue content was left unchanged.

## Bookmark data and account boundaries

`FirestoreArticleBookmarks` stores one document per article at
`users/{uid}/profile/{uid}/bookmarks/{articleId}`. The only fields are
`articleId` and `savedAt`. A repeated save writes the same document and
updates its server timestamp. Repeated removal succeeds with no record left.
There is no copied article content. A UID-keyed Firestore stream drives the
article action and Saved Articles. Selecting a different account stops using
the previous stream and switches immediately to the new UID's state. An
in-flight write remains addressed to the UID captured when it started.

Firestore rules reuse the existing verified-session ownership and revocation
checks. The rules require both profile UID segments to agree, the article ID
to match the document ID, and `savedAt` to equal the server request time.
Firestore metadata distinguishes cached results and pending writes. The
article action displays a sync indicator while its write is outstanding and
shows a message if the write fails. The Saved Articles screen displays cached
or pending state, an empty state, and an unavailable count when an ID is
absent from the catalogue. The rules enforce revocation on server access.
Previously cached data for the same account can be visible while disconnected,
subject to the existing Firebase cache policy. [Firestore listener metadata](https://firebase.google.com/docs/firestore/query-data/listen) · [Firestore offline persistence](https://firebase.google.com/docs/firestore/manage-data/enable-offline)

The legacy SharedPreferences key `resources_bookmarked_article_ids` has no
account ownership information. Its existing values remain on the device and
are excluded from account-specific bookmark state. There is no automatic
import or deletion. The bundled catalogue remains available through the existing fallback if
Firestore is empty or unavailable.

### Article source provenance

The detail screen displays publisher citation and a supplied publication date
separately from verification date. In Firestore, the CMS writes its own
creation time to the legacy `publishedAt` field. The reader suppresses that
ambiguous field for entries without verified trusted-source provenance and a
valid verification date. Verified seeded catalogue dates remain visible.
Individual bylines and source dates for new CMS content require a publisher
metadata contract. The CMS, catalogue content and publishing permissions are
unchanged.

## Public emergency access and facility data

Login and verification-pending screens keep the one-tap dial action and link
to `/emergency`. The public page displays the bundled Punjab Rescue 1122
contact, a dial action, a service disclaimer, and the public nearby directory.
`/emergency/nearby` and its map use device GPS with a provider that does not
read the profile or risk feed. The normal full Resource Center and the normal
hospital route retain their authentication, profile and disclaimer gates.
The issued app has one bundled emergency number. Additional contacts require
verification of operator and service coverage. [Punjab Emergency Service](https://www.rescue.gov.pk/ambulanceservice.aspx)

The same Nearby Search request includes the documented `hospital`,
`general_hospital` and `medical_clinic` types. The response's type metadata
drives category labels. Results are deduplicated by Place ID. Search, the
five-kilometre filter, highest-rated sort and Open Now filter work locally.
The default is nearest first. The rating control appears only when ratings
exist. Filters persist for the open directory screen. The map reapplies the
directory's filters to each updated result. Manual refresh can still resolve
a new origin. In-map search controls are outside the current design. [Places types](https://developers.google.com/maps/documentation/places/web-service/place-types) · [Nearby Search](https://developers.google.com/maps/documentation/places/web-service/nearby-search)

The existing 15-minute coordinate cache and 50-attempt in-memory budget remain
in place. Simultaneous same-origin searches share one request, unsuccessful
requests also count against the budget, and HTTP 429 surfaces the quota state.
GPS position acquisition has a 15-second limit. A missing fix can offer the
private profile-city fallback or a GPS retry on the public route. Places
transport requests have a 12-second limit.

### Foreground location and map tracking

After an initial GPS fix, the visible directory or its map subscribes to
Geolocator. Route changes and any departure from the resumed app state cancel
the subscription. Device fixes are filtered at 50 metres and remeasure each
facility's straight-line distance. An origin change of at least one kilometre
can refresh the facility set, at most once per minute, through the existing
cache and quota controls. Failed refreshes retain the previous set and report
that it could not be refreshed. Cache hits and shared in-flight responses
use distances for the requesting origin. The map shows the latest device
position and moves the camera without animation after at least 250 metres and
eight seconds. Facility selection takes precedence over automatic camera
movement. The map's recenter button uses the tracked fix.

The GPS service checks permission and service status on subscription and
periodically while active. Loss of access stops tracking. The public route
offers GPS retry. The private route can offer the existing explicit profile
city fallback. City-only results do not start GPS tracking.

The directory includes the age of its results. `currentOpeningHours.openNow`
describes provider-reported opening hours at lookup. Missing hours remain
unknown. Places metadata does not establish emergency capability, ED status,
capacity or 24/7 service. No integrated, verified per-facility emergency
capability or availability feed was found. Highlighting confirmed emergency
departments and showing live clinical availability require a vetted source
and an approved linkage to facility IDs. [Places response fields](https://developers.google.com/maps/documentation/places/web-service/reference/rest/v1/places)

## Requirement closure matrix

The implementation file names below identify the relevant Module 4 code.
The evidence column distinguishes automated checks from physical-device
and external requirements.

| Requirement | Implementation and files | Evidence | Status and remaining limitation |
| --- | --- | --- | --- |
| FE-1 verified precaution and self-care library | Existing `static_resource_repository.dart` and `firestore_resource_repository.dart` catalogue | Repository, catalogue integrity, and article tests | Implemented and tested locally. Editorial updates remain with the CMS. |
| FE-2 one-tap emergency actions and hospital directory links | `emergency_help_button.dart`, `emergency_resources_screen.dart`, `hospital_actions.dart`, `app_router.dart` | Public route and fake dialer tests | Implemented and tested locally. Requires device dialer verification. Additional contacts require verified data. |
| FE-3 nearby hospitals and clinics during high-risk alerts | `google_places_repository.dart`, `nearby_hospitals_providers.dart`, existing risk-context entry | Mocked Places, GPS, and risk-slice tests | Implemented and tested locally. Requires staging Places coverage and device validation. |
| Table 2.14 keyword search (FR4.1) | Existing search sheet in `resource_center_sheets.dart` | Live-input, publisher and no-result widget tests | Implemented and tested locally. |
| Table 2.14 category filters (FR4.1) | Existing `resource_center_screen.dart` real catalogue filters | Category and article count checks | Implemented and tested locally. |
| Table 2.14 nearby hospitals based on location (FR4.3) | `nearby_hospitals_providers.dart`, `nearby_hospitals_screen.dart` | Mock GPS, profile-city fallback, denial, and public isolation | Implemented and tested locally. Requires device GPS verification. |
| Table 2.14 hospital navigation (FR4.3) | `hospital_actions.dart` Google Maps URL | Fake launcher direction assertions | Implemented and tested locally. Requires device handoff verification. |
| Table 2.14 public contacts (FR4.2) | `emergency_resources_screen.dart`, `app_router.dart` | Signed-out and unverified GoRouter tests | Implemented and tested locally. One verified bundled contact. |
| Table 2.14 high-risk relevance (FR3.3) | Existing `resource_field_state.dart` and context-aware ordering | Resource Center and risk-slice integration | Implemented and tested locally using the existing risk signal. |
| Table 2.14 titles, previews and full reading (FR4.1) | `resource_center_screen.dart`, `article_screen.dart` | Catalogue and route tests | Implemented and tested locally. CMS remains the publishing authority. |
| Table 2.14 location personalization (FR4.3) | Existing current-city risk and nearby-care providers | Risk-slice, location and profile fallback tests | Implemented and tested locally. Public emergency routes omit personalization. |
| Table 2.15 title and category (FR4.1) | `article_screen.dart` and `resource_article.dart` | Article route, category and model tests | Implemented and tested locally. |
| Table 2.15 author and publication date (FR4.1) | `source_citation_card.dart` and `firestore_resource_repository.dart` display sourced metadata and omit ambiguous CMS creation timestamps | Seeded versus CMS date regression in `firestore_resource_repository_test.dart`, metadata and article tests | Partially implemented. Individual bylines and missing source dates require publisher metadata. |
| Table 2.15 readable sections and highlighted advice (FR4.1) | Existing `article_content_blocks.dart` | Content model and article widget coverage | Implemented and tested locally, with the existing source and disclaimer. |
| Table 2.15 bookmarking and profile storage (FR4.1) | `firestore_article_bookmarks.dart`, `article_bookmark_provider.dart`, `saved_articles_screen.dart`, `firestore.rules` | Widget tests, account-switch tests, and two same-UID demo clients | Implemented and tested locally and on the emulator. Native reinstall and offline recovery require device verification. |
| Table 2.15 external sharing and navigation controls (FR4.1) | `article_screen.dart` existing share and routed reading controls | Fake share sheet, source link and navigation tests | Implemented and tested locally. Requires system share-sheet check. |
| Table 2.15 contextual risk (FR3.3) and user-derived health metrics (FR3.4) | `article_screen.dart` uses the existing city risk signal for article relevance and context | Resource risk-slice and article rendering tests | Partially implemented. Separate article-specific personal health metrics are absent and require supervisor approval of the data and design. |
| Table 2.16 interactive map and markers (FR4.3) | `hospitals_map_screen.dart` and `nearby_care_tracking.dart` update the current-position and filtered facility markers | Marker coordinates and selection tests, camera threshold tests, fake position stream | Implemented and tested locally. Requires device map rendering, camera and gesture verification. |
| Table 2.16 name, rating and distance (FR4.3) | `google_places_repository.dart`, `hospital_list.dart`, `hospital_detail_sheet.dart` | Places and list/detail tests | Implemented and tested locally. Ratings are optional and distances are straight-line. |
| Table 2.16 emergency-capable highlight (FR4.2) | No verified capability field available from the integrated source | Source and model audit | Not implemented. Requires verified facility data and supervisor approval of the source. |
| Table 2.16 navigation and dialing (FR4.3 and FR4.2) | `hospital_actions.dart` shared launcher | Fake call and directions tests and missing-phone state | Implemented and tested locally. Requires device handoff verification. |
| Table 2.16 search and session filters (FR4.3) | `nearby_hospitals_screen.dart` name/address search, distance, rating, Open Now and reset | Directory widget tests, no new lookup while filtering | Implemented and tested locally for the fetched result set, with filters reapplied to live map results. |
| Table 2.16 location tracking (FR3.2) | `nearby_hospitals_providers.dart` with `geolocator_location_service.dart` and `nearby_care_tracking.dart` use foreground GPS or an explicitly chosen private profile city | Fake fixes, distance update, camera limits, covered route, background cancellation, permission loss, stream error and disposal | Implemented and tested locally. Requires physical-device verification of native permission changes and movement. |
| Table 2.16 real-time availability (FR4.3) | `hospital_detail_sheet.dart` and directory display provider-reported opening status and freshness | Known and unknown opening-hours fixtures and cache tests | Partially implemented. Live ED availability, capacity or verified 24/7 coverage require external verified data. |

## Production boundaries

Validate location prompts and revocation, disabled services, foreground and
background transitions, map movement, dialer/directions/share handoff and
offline bookmark queue recovery on physical devices. On staging, check Places
key restrictions, quota and local facility coverage, and bookmark syncing
across devices and account switches. The
results below use fixtures or the demo emulator. No live emergency calls,
Places searches, FCM notifications, or production Firestore writes were made.

The shared router and auth emergency button are the only production Dart
changes outside the resource feature. Module 2 scheduling and dose handling,
Module 3 risk logic, Modules 5 and 6, Module 7 dispatch, Module 8 CMS
authorization, and Module 9 session, registry and logout architecture were
left unchanged. The bookmark rules extend the existing ownership checks at
the profile path.

## Test commands and results

The acceptance test run used Flutter fixtures and a Firestore demo project.
On Windows the Flutter CLI commands ran through the installed
`dart.exe flutter_tools.snapshot --no-version-check` entry point.

| Command | Result |
| --- | --- |
| `dart analyze lib test` | No issues found |
| `flutter test --no-pub --reporter expanded --plain-name 'foreground fixes' test/features/resources/nearby_hospitals_test.dart` | 2 passed |
| `flutter test --no-pub --reporter expanded test/features/resources test/integration/risk_view_slice_test.dart test/features/auth/auth_notifier_test.dart test/features/health_profile/disclaimer_acceptance_test.dart test/features/alerts/alerts_test.dart` | 127 passed, 1 opt-in suite skipped |
| `flutter test --no-pub --reporter expanded` | 986 passed, 4 opt-in suites skipped |
| `firebase emulators:exec --config .module4-final-emulators.json --only firestore --project demo-foreseeme "node test_rules/firestore_rules.test.mjs"` | 122 passed, 0 failed |
| `flutter test --no-pub --run-skipped --tags golden --reporter expanded test/features/resources/resource_center_golden_test.dart` | Isolated working snapshot 1 passed, 32 failed. Isolated clean baseline 3 passed, 30 failed. |

The Firebase CLI used a temporary configuration with loopback host and port
18488. The default Flutter command excludes the four opt-in golden suites for\nAdd Medication, Medication Hub, Profile Hub, and Resource Center. No\nproduction configuration or reference screenshots were changed.
An initial focused run (123 passed, 3 failed, 1 opt-in skip) exposed a test
assumption about cached list identity and fake subscription scheduling.
The tests now assert facility IDs and use a controllable fake cancellation
future. The first parallel baseline golden attempt stopped when the Flutter
compiler temporary directory disappeared. The isolated rerun completed.

### Golden case diagnostics

The goldens disable runtime Google Fonts fetching. The repository's assets
have no tracked TTF/OTF for Space Grotesk, Manrope or IBM Plex Mono, and its
pubspec has no corresponding font declarations or test-font loader. The clean
baseline reproduces missing-font errors and fallback-glyph screenshots. The
working snapshot preserves all 30 baseline failures. The table accounts for
all 32 working-snapshot failures. Font failures and pixel comparisons can
occur in the same test. Pixel differences with fallback glyphs cannot certify
production typography.

| Failed cases | Count | Observed signatures and comparison |
| --- | ---: | --- |
| Dark and light Resource Center at 360×800, 390×844 and 430×932 | 6 | Missing fonts on both snapshots. The working snapshot also reports pixel deltas of 0.98–1.36%. |
| Dark and light at 390×844 scrolled 320, 900 and 1500 | 6 | Missing fonts and pixel deltas on both. Scroll 900 and 1500 deltas match the baseline exactly. Scroll 320 differs at the updated search row. |
| Dark and light full page | 2 | Both snapshots report missing fonts and pixels. The changed search row is included in the full-page images. |
| Dark resource field with no signal, low, medium or high risk | 4 | Missing fonts on both. Working images also report 1.23% pixel differences. |
| Dark and light article at 1× and 2× | 4 | Missing fonts on both. No pixel comparison error was reported for these tests. |
| Dark and light emergency and search overlays | 4 | Missing fonts and pixel differences on both. Search-overlay differences match exactly, while emergency overlays include the changed background row. |
| Dark care, light care and dark facility sheet | 3 | Both snapshots stopped before comparison when the care call-to-action finder did not resolve. Default widget tests exercise the care lookup and facility sheet successfully. |
| Dark 390×844 at 1.5× scrolled 0 and at 2× scrolled 900 | 2 | Baseline passes. Working image diffs of 1.14% and 1.68% are localized to the Saved Articles icon and adjacent search control. |
| Dark 390×844 at 1.5× scrolled 900 | 1 | Same pixel difference on baseline and working snapshot, 0.45% and 1,476 pixels. |

Visual acceptance remains open for the standard fonts and native map. The
two Saved Articles screenshot deltas reflect the required entry point and its
layout change. The approved visual environment is needed to review these
against correctly rendered text and update the affected references.

## Changed files

- `docs/MODULE_4_IMPLEMENTATION_AND_VERIFICATION.md`
- `firestore.rules`
- `lib/core/routes/app_router.dart`
- `lib/features/auth/presentation/widgets/emergency_help_button.dart`
- `lib/features/resources/data/repositories/firestore_article_bookmarks.dart`
- `lib/features/resources/data/repositories/firestore_resource_repository.dart`
- `lib/features/resources/data/repositories/google_places_repository.dart`
- `lib/features/resources/data/services/geolocator_location_service.dart`
- `lib/features/resources/domain/exceptions/places_exception.dart`
- `lib/features/resources/domain/models/hospital.dart`
- `lib/features/resources/domain/models/location_result.dart`
- `lib/features/resources/domain/models/nearby_hospitals_result.dart`
- `lib/features/resources/domain/services/location_service.dart`
- `lib/features/resources/presentation/article_bookmark_provider.dart`
- `lib/features/resources/presentation/article_screen.dart`
- `lib/features/resources/presentation/emergency_resources_screen.dart`
- `lib/features/resources/presentation/nearby_care_tracking.dart`
- `lib/features/resources/presentation/nearby_hospitals_providers.dart`
- `lib/features/resources/presentation/nearby_hospitals_screen.dart`
- `lib/features/resources/presentation/resource_center_screen.dart`
- `lib/features/resources/presentation/saved_articles_screen.dart`
- `lib/features/resources/presentation/services/hospital_actions.dart`
- `lib/features/resources/presentation/widgets/emergency_card.dart`
- `lib/features/resources/presentation/widgets/hospital_detail_sheet.dart`
- `lib/features/resources/presentation/widgets/hospital_list.dart`
- `lib/features/resources/presentation/widgets/hospitals_map_screen.dart`
- `test/features/resources/article_bookmarks_test.dart`
- `test/features/resources/emergency_resources_test.dart`
- `test/features/resources/firestore_resource_repository_test.dart`
- `test/features/resources/nearby_hospitals_test.dart`
- `test/features/resources/resource_center_golden_test.dart`
- `test/features/resources/resource_center_test.dart`
- `test/integration/risk_view_slice_test.dart`
- `test_rules/firestore_rules.test.mjs`
