# Health resource content management

The existing ForeSeeMe Content screens publish structured articles to `articles/{id}` through the HTTPS admin service. The app still uses the same Firestore Resource Center and curated fallback. Article IDs and links remain stable during edits. Existing secondary categories and provenance are retained when applicable. A service-side check requires a nonempty title, category, summary, source name, HTTPS URL, and a nonempty paragraph, tip, or warning. Destination credentials in source URLs are rejected. A slug collision on creation returns a conflict and leaves the original article intact.

Each successful publication and its audit event commit together. An edit preserves original publication time. The service clears reviewed provenance when the source or reading content changes. Published changes are available on the next Resource Center read and invalidate the local reader after a successful admin save. Existing open sessions may need to refresh their content.

Every authenticated client can read the published collection. All client writes are denied. Use the existing `backend/scripts/seed_resource_articles.py` only for controlled initial seeding, after checking the existing catalog so seeded IDs do not overwrite later edits. See the [Module 8 engineering report](MODULE_8_FINALIZATION.md) for release order.
