# ForeSeeMe — Golden Rules (architectural invariants)

# Paste this file's contents into every AI-coding-assistant prompt.

## Layer boundaries (Feature-First Clean Architecture)

1. Presentation (Flutter widgets, screens, GoRouter) MUST NOT import firebase_*,

   http, or any external SDK. It only watches Riverpod providers.

2. Domain (Riverpod notifiers/providers/AsyncNotifiers, validators) MUST NOT

   import Flutter widget libraries (no `package:flutter/material.dart` etc.).

3. Data (abstract repositories, Firebase implementations, Dart models) holds ALL

   external I/O. Every external call sits behind an abstract repository interface.

## Risk data (ADR-001)

4. The app reads risk ONLY from Firestore `riskEstimates`. It MUST NEVER call the

   FastAPI `/predict` endpoint directly. `/predict` is internal to the backend.

## Models & quality

5. All Dart models are immutable (final fields, const constructor), null-safe,

   with explicit fromJson/toJson. No Flutter imports in models.

6. Every new repository method ships with a unit test.

7. No secrets in source. All keys/paths come from environment variables.

   Service-account JSON and .env are git-ignored.

## When in doubt

8. Mirror the structure, naming, and patterns already used by the existing

   `medication` and `auth` features. Do not invent a new folder convention.
