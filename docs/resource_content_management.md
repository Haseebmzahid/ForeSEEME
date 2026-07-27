# Health Resource Content Management (Sprint M8.3)

*Implements SDS FR8.3 — migrates the Resource Center from static, ship-with-the-app
content to an admin-editable Firestore-backed CMS.*

## The scope decision

The audit (`docs/MODULE_8_AUDIT.md` §15, Sprint 8.3) originally scoped this as
"maybe write-only for now" versus a full migration, because FR8.3's business rule
— *"Published content must be immediately visible in resource center"* — only
holds if the **live, user-facing** Resource Center actually reads from the same
place the admin writes to. The team chose the **full migration**: the Resource
Center now reads Firestore, not the old static Dart list.

## What changed for end users

Nothing observable — the same 8 curated articles render exactly as before,
identity-for-identity (same ids, same content), because:

1. `ResourceRepository.articles()` (interface) went from a synchronous
   `List<ResourceArticle>` to `Future<List<ResourceArticle>>` — the only
   contract change.
2. **Only one provider crossed the async boundary**:
   `resourceArticlesAsyncProvider` (new, `FutureProvider`). Every other
   article-derived provider (`orderedResourceArticlesProvider`,
   `featuredResourceArticleProvider`, `articleByIdProvider`,
   `isTopicContextuallyRelevantProvider`) stayed a plain, synchronous
   `Provider`, reading the async source via `.asData?.value ?? const []` — the
   same idiom already used for `currentCityRiskProvider` elsewhere in this
   file. **`ResourceCenterScreen` and `ArticleScreen` needed zero changes.**
3. The accepted trade-off: a brief empty-list flash on first paint before the
   initial Firestore read resolves (no loading spinner was added for it —
   consistent with how these screens never showed one for the old static data
   either).

## Data model

`ResourceArticle`/`ArticleBlock`/`ResourceTopic` gained `fromJson`/`toJson` —
additive; `readingMinutes` and every other existing member is untouched. The
document id (Firestore `articles/{id}`) is a title-derived slug
(`slugifyArticleTitle`), assigned once at creation and **never changed by a
later title edit** — it's what bookmarks and `/resources/article/:id` deep
links point at.

## Graceful degradation, not silent seeding

`FirestoreResourceRepository.articles()`: if the `articles` collection has zero
documents (a fresh/unseeded Firestore project), it returns
`StaticResourceRepository`'s curated content instead of an empty list — mirrors
the backend's own established precedent (`app/predict.py` falling back to
`StubRiskModel` when no artifact exists). This is a **fallback for the empty
case only**, not a substitute for seeding: `backend/scripts/seed_resource_articles.py`
writes the same 8 articles into Firestore (idempotent, upsert by slug) and
should be run as a deployment step so the CMS's own admin list isn't
mysteriously empty on a fresh project. A genuine read error (offline, no cache)
is **not** masked this way — it surfaces as a normal `AsyncError`.

## The admin CMS

**Profile → Admin Panel → Content** (`/admin/content`, admins only), a fourth
branch of `AdminShell` (no shell changes needed — proves out the M8.1/M8.2
"plug in a branch" promise a second time):

- **List** (`AdminContentScreen`) — every published article (this IS what end
  users see; there is no draft state), with an "Add article" entry point.
- **Form** (`AdminArticleFormScreen`, pushed, not a branch — mirrors the
  medication feature's `AddMedicationScreen(medication: ...)` add/edit
  convention): title, category, summary, source name + URL (**source is
  required and must be `https://`** — not explicitly listed in the SDS's
  mockup-derived field list, but kept as a hard requirement anyway: every
  other article in this app is genuinely sourced, and the CMS must not become
  a way to sneak in unsourced content), and a **structured block editor**
  (heading/paragraph/tip/warning + text, add/remove rows) — not a single
  free-text body, because `ResourceArticle.content` is genuinely typed and
  this is the only way an admin can reproduce a "warning" callout rather than
  flattening every article to one paragraph.
- **No delete** — the SDS's FR8.3 mockup rows only ask for create/update/publish;
  an operator can still remove a document via the Firebase Console (already
  permitted by the admin-write rule) if truly needed.
- **No draft/review workflow** — SDS: *"if workflow enabled"* is conditional;
  a save is immediately live, matching "Published content must be immediately
  visible."
- Every create/update logs to the shared `adminActivityLog`
  (`article_create` / `article_update`, target = the article's id) —
  `docs/admin_activity_log.md`.

## Firestore rules

```
match /articles/{articleId} {
  allow read: if request.auth != null;
  allow write: if isAdmin();
}
```
Same openness as `riskEstimates` for reads (every user reads the same
published library); admin-only write, using the shared `isAdmin()` helper.
Verified: admin create/update succeed, non-admin write denied, authed read
succeeds, unauthenticated read denied (`test_rules/firestore_rules.test.mjs`).

## Two bugs found and fixed while building this

Neither is specific to M8.3's own new code — both were latent defects the new
tests happened to expose:

1. **A spurious auto-pop/toast on screen open.** `ref.listen(controller, ...)`
   gating a "just saved" side effect on `previous is AsyncLoading` alone is
   wrong: `AsyncNotifier.build()` itself transitions `AsyncLoading` →
   `AsyncData` the instant the controller is first created, identical in
   shape to a real save completing. `AdminArticleFormScreen` copied this
   pattern from `AdminOverrideScreen` (Sprint 5) and turned the latent bug
   into a broken navigation flow (auto-popping before the admin did anything);
   `AdminOverrideScreen`'s own version was harmless only because it just shows
   a toast. Both are now fixed with an explicit `_submitted` flag, set only
   when the admin actually taps submit.
2. **Eager Firestore initialisation breaking a synchronous provider.**
   `FirestoreResourceRepository`'s constructor touched `FirebaseFirestore.instance`
   immediately, even though `emergencyContact()` never needs it. Since
   `emergencyContactProvider` is a plain `Provider` (not a `FutureProvider`
   that catches errors into `AsyncError`), any screen reading it without
   overriding `resourceRepositoryProvider` in tests crashed outright. Fixed by
   resolving `_firestore` lazily (only inside `articles()`), and surfaced 12
   failing tests across unrelated features (`health_intelligence_screen_test.dart`,
   `risk_details_screen_test.dart`, an integration test) that all shared this
   one root cause.

## Tests

- `test/features/resources/resource_article_model_test.dart` — JSON round-trips,
  defensive defaults for missing/unrecognised fields.
- `test/features/resources/article_slug_test.dart` — slug derivation.
- `test/features/resources/firestore_resource_repository_test.dart` — read,
  the empty-collection fallback, and the write-then-read round trip via
  `FirestoreResourceContentRepository`.
- `test/features/resources/resource_center_test.dart` — updated to explicitly
  pin `resourceRepositoryProvider` to `StaticResourceRepository()` (the
  default now performs a real read) and to `await` the now-`Future`
  `articles()` call in its content-integrity test; all existing assertions
  unchanged.
- `test/features/admin/admin_content_screen_test.dart`,
  `admin_article_form_screen_test.dart` — the admin gate, empty state, list
  rendering, add/edit navigation, every validation rule, the block editor,
  and (via fakes) that a save reaches the repository and the activity log
  with the correct id/action.
- `test_rules/firestore_rules.test.mjs` — the `articles` rule surface.

## What this sprint deliberately does not do

- No delete UI (see above).
- No draft/review/publish-workflow state.
- No content versioning/history beyond the shared admin activity log's
  create/update entries (SDS FR8.3's table doesn't ask for full version
  history — FR8.4's log entries are the audit trail here).
