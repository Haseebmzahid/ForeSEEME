# Claude Instructions

Before making ANY changes:

1. Read PROJECT_CONTEXT.md

2. Read GOLDEN_RULES.md

3. Read:

- docs/adr/ADR-001-risk-source-of-truth.md

- docs/adr/ADR-002-scheduled-compute.md

4. Inspect the existing:

- medication feature

- auth feature

5. Mirror their:

- folder structure

- repository pattern

- Riverpod providers

- naming conventions

- testing style

- dependency direction

Do NOT redesign the project.

Do NOT introduce new libraries.

Do NOT introduce new architectural patterns.

Every new feature must follow the existing Clean Architecture.

If a requested implementation violates these rules, explain why before making changes.

## Architecture Priority

When there is a conflict:

1. Existing project architecture
2. GOLDEN_RULES.md
3. ADR documents
4. Prompt instructions

Never violate a higher-priority rule to satisfy a lower-priority instruction.