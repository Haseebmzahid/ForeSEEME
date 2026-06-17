# API Contracts & Data Formats: ForeSeeMe

**Last Updated**: May 6, 2026  
**Specification Version**: 1.0  
**Status**: 🟡 Firestore Complete | ⏳ Backend API Planning

## Overview

This document defines all data contracts, API endpoints, request/response formats, error codes, and authentication schemes used throughout ForeSeeMe.

---

## Firestore Collections & Schemas

### Collection: `users/{uid}`

**Purpose**: User account and profile data  
**Access**: User's own data (role-based)  
**Timestamp**: Server timestamp

#### Document Structure

```json
{
  "uid": "firebase-uid-string",
  "email": "user@example.com",
  "displayName": "John Doe",
  "photoUrl": "https://example.com/photo.jpg",
  "createdAt": "2026-05-01T10:30:00Z",
  "lastUpdated": "2026-05-06T15:45:00Z"
}
```

#### Fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| uid | string | Yes | Firebase Auth UID |
| email | string | Yes | User email address |
| displayName | string | No | User display name |
| photoUrl | string | No | Profile picture URL |
| createdAt | ISO 8601 | Yes | Account creation time |
| lastUpdated | ISO 8601 | Yes | Last profile update |

#### Subcollection: `users/{uid}/profile/data`

**Purpose**: Extended health profile  
**Document ID**: `data` (singleton)

```json
{
  "city": "New York",
  "chronicConditions": [
    "Type 2 Diabetes",
    "Hypertension"
  ],
  "lastUpdated": "2026-05-06T15:45:00Z"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| city | string | No | User's city/location |
| chronicConditions | string[] | No | List of chronic conditions |
| lastUpdated | ISO 8601 | Yes | When profile was last updated |

#### Subcollection: `users/{uid}/medications/{medId}`

**Purpose**: Medication records  
**Document ID**: Auto-generated UUID

```json
{
  "id": "med-uuid-v4",
  "uid": "firebase-uid",
  "name": "Metformin",
  "dosage": "500mg",
  "type": "pill",
  "frequency": "twiceDaily",
  "reminderTimes": [
    "08:00",
    "20:00"
  ],
  "isActive": true,
  "createdAt": "2026-05-01T10:30:00Z",
  "deactivatedAt": null
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | UUID | Yes | Unique medication ID |
| uid | string | Yes | User's Firebase UID |
| name | string | Yes | Medication name |
| dosage | string | Yes | Dosage (e.g., "500mg") |
| type | enum | Yes | pill \| syrup |
| frequency | enum | Yes | onceDaily \| twiceDaily \| thriceDaily |
| reminderTimes | string[] | Yes | Times in HH:mm format (24h) |
| isActive | boolean | Yes | Soft delete flag |
| createdAt | ISO 8601 | Yes | When added |
| deactivatedAt | ISO 8601 | No | When deactivated (if soft deleted) |

#### Subcollection: `users/{uid}/adherence_logs/{logId}`

**Purpose**: Daily adherence tracking  
**Document ID**: `{medId}_{YYYY-MM-DD}_{HHmm}`

```json
{
  "id": "med-uuid_2026-05-06_0800",
  "medicationId": "med-uuid",
  "uid": "firebase-uid",
  "date": "2026-05-06",
  "time": "08:00",
  "status": "taken",
  "confirmedAt": "2026-05-06T08:05:00Z",
  "createdAt": "2026-05-06T08:05:00Z"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| id | string | Yes | Composite ID `{medId}_{date}_{time}` |
| medicationId | string | Yes | Reference to medication |
| uid | string | Yes | User's Firebase UID |
| date | string | Yes | Date in YYYY-MM-DD format |
| time | string | Yes | Time in HH:mm format |
| status | enum | Yes | taken \| skipped \| pending |
| confirmedAt | ISO 8601 | No | When user confirmed status |
| createdAt | ISO 8601 | Yes | When record created |

---

## Authentication

### Firebase Authentication

**Method**: Firebase Auth REST API (official)  
**Protocols**: HTTPS only  
**Base URL**: `https://identitytoolkit.googleapis.com/v1`

#### Sign Up (Email/Password)

**Endpoint**: `POST /accounts:signUp`

**Request**:
```json
{
  "email": "user@example.com",
  "password": "SecurePassword123!",
  "returnSecureToken": true
}
```

**Response** (Success):
```json
{
  "kind": "identitytoolkit#SignupNewUserResponse",
  "idToken": "jwt-token-here",
  "email": "user@example.com",
  "refreshToken": "refresh-token-here",
  "expiresIn": "3600",
  "localId": "firebase-uid"
}
```

**Response** (Error):
```json
{
  "error": {
    "code": 400,
    "message": "EMAIL_EXISTS",
    "errors": [{
      "message": "EMAIL_EXISTS",
      "domain": "global",
      "reason": "invalid"
    }]
  }
}
```

#### Sign In (Email/Password)

**Endpoint**: `POST /accounts:signInWithPassword`

**Request**:
```json
{
  "email": "user@example.com",
  "password": "SecurePassword123!",
  "returnSecureToken": true
}
```

**Response** (Success):
```json
{
  "kind": "identitytoolkit#VerifyPasswordResponse",
  "localId": "firebase-uid",
  "email": "user@example.com",
  "displayName": "John Doe",
  "idToken": "jwt-token",
  "registered": true,
  "refreshToken": "refresh-token",
  "expiresIn": "3600"
}
```

#### Sign In with Google

**Method**: Firebase Google OAuth  
**Flow**: OAuth 2.0 Authorization Code

**Token Exchange**:
```json
{
  "idToken": "google-id-token",
  "displayName": "John Doe",
  "photoUrl": "https://lh3.googleusercontent.com/...",
  "email": "user@gmail.com"
}
```

#### Password Reset

**Endpoint**: `POST /accounts:sendOobCode`

**Request**:
```json
{
  "requestType": "PASSWORD_RESET",
  "email": "user@example.com"
}
```

**Response**:
```json
{
  "kind": "identitytoolkit#GetOobConfirmationCodeResponse",
  "email": "user@example.com",
  "oobCode": "reset-code-string",
  "oobExpireIn": 3600
}
```

#### Refresh Token

**Endpoint**: `https://securetoken.googleapis.com/v1/token`

**Request**:
```json
{
  "grant_type": "refresh_token",
  "refresh_token": "refresh-token-string"
}
```

**Response**:
```json
{
  "access_token": "new-jwt-token",
  "expires_in": "3600",
  "token_type": "Bearer",
  "id_token": "new-id-token"
}
```

---

## Error Codes & Responses

### Firebase Auth Error Codes

| Code | Message | HTTP | Meaning |
|------|---------|------|---------|
| 400 | INVALID_EMAIL | 400 | Email format invalid |
| 400 | EMAIL_EXISTS | 400 | Email already registered |
| 400 | OPERATION_NOT_ALLOWED | 400 | Auth method disabled |
| 400 | TOO_MANY_ATTEMPTS_TRY_LATER | 429 | Too many failed attempts |
| 400 | USER_DISABLED | 400 | User account disabled |
| 400 | INVALID_PASSWORD | 400 | Password incorrect |
| 401 | INVALID_ID_TOKEN | 401 | ID token invalid/expired |

### Firestore Error Codes

| Code | HTTP | Meaning |
|------|------|---------|
| PERMISSION_DENIED | 403 | Insufficient permissions |
| INVALID_ARGUMENT | 400 | Invalid query parameter |
| NOT_FOUND | 404 | Document not found |
| ALREADY_EXISTS | 409 | Document already exists |
| RESOURCE_EXHAUSTED | 429 | Quota exceeded |
| INTERNAL | 500 | Server error |

---

## Enums & Constants

### Medication Type

```dart
enum MedicationType {
  pill,      // Tablet/capsule
  syrup,     // Liquid medication
  // Future: injection, cream, etc.
}

// String values for Firestore
pill → "pill"
syrup → "syrup"
```

### Medication Frequency

```dart
enum MedicationFrequency {
  onceDaily,    // 1x per day
  twiceDaily,   // 2x per day
  thriceDaily,  // 3x per day
  // Future: asNeeded, weekly, etc.
}

// String values for Firestore
onceDaily → "onceDaily"
twiceDaily → "twiceDaily"
thriceDaily → "thriceDaily"
```

### Adherence Status

```dart
enum AdherenceStatus {
  pending,   // Medication not yet marked
  taken,     // User confirmed taken
  skipped,   // User marked as skipped
}

// String values for Firestore
pending → "pending"
taken → "taken"
skipped → "skipped"
```

### Chronic Conditions

Common conditions (user can add custom):

```
Type 1 Diabetes
Type 2 Diabetes
Hypertension (High Blood Pressure)
Asthma
COPD
Arthritis
Depression
Anxiety
Thyroid Disorder
Heart Disease
Kidney Disease
Liver Disease
Asthma
Epilepsy
Migraine
```

### Reminder Time Format

```
HH:mm (24-hour format)
Examples:
08:00  → 8:00 AM
14:30  → 2:30 PM
23:59  → 11:59 PM
00:00  → Midnight
```

### Date Format

```
ISO 8601: YYYY-MM-DD
Examples:
2026-05-06  → May 6, 2026
2026-12-31  → December 31, 2026
```

---

## Rate Limiting

### Current (MVP)

No rate limiting enforced (Firebase default quotas apply)

### Planned (Multi-Provider Phase)

| Endpoint | Limit | Window |
|----------|-------|--------|
| Sign in | 5 attempts | 1 minute |
| Password reset | 3 requests | 1 hour |
| API calls | 100 req/s | Per user |

---

## Security Headers & CORS

### Required Headers

All HTTPS requests include:

```
Content-Type: application/json
Authorization: Bearer {idToken}
User-Agent: ForeSeeMe/{version}
```

### CORS Policy

Firestore Rules enforce:
- Only authenticated users
- Users only access own data
- No cross-user data access

---

## Data Validation Rules

### Email

```
Pattern: ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$
Max Length: 254 characters
```

### Password

```
Min Length: 8 characters
Complexity: At least 1 uppercase, 1 lowercase, 1 number
Examples:
✓ SecurePass123
✓ MyPassword2026
✗ password (too simple)
✗ Pass1 (too short)
```

### Medication Name

```
Max Length: 100 characters
Allowed: Alphanumeric, spaces, hyphens, parentheses
Examples:
✓ Metformin 500mg
✓ Aspirin (Daily)
✗ !@#$% (special chars)
```

### City Name

```
Max Length: 50 characters
Allowed: Letters, spaces, hyphens
Examples:
✓ New York
✓ Los Angeles
✓ San Francisco
```

### Dosage

```
Max Length: 50 characters
Pattern: Number + Unit
Examples:
✓ 500mg
✓ 10ml
✓ 1 tablet
✗ 500 (missing unit)
```

---

## Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // User data - only user can access own
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
      
      // Profile subcollection
      match /profile/{document=**} {
        allow read, write: if request.auth.uid == uid;
      }
      
      // Medications subcollection
      match /medications/{document=**} {
        allow read, write: if request.auth.uid == uid;
        allow create: if validateMedication(request.resource.data);
        allow update: if validateMedication(resource.data);
      }
      
      // Adherence logs subcollection
      match /adherence_logs/{document=**} {
        allow read, write: if request.auth.uid == uid;
        allow create: if validateAdherence(request.resource.data);
      }
    }
  }
  
  // Validation functions
  function validateMedication(med) {
    return med.keys().hasAll(['uid', 'name', 'dosage', 'type', 'frequency'])
      && med.uid == request.auth.uid
      && med.name is string && med.name.size() > 0
      && med.dosage is string && med.dosage.size() > 0
      && med.type in ['pill', 'syrup']
      && med.frequency in ['onceDaily', 'twiceDaily', 'thriceDaily']
      && med.reminderTimes is list;
  }
  
  function validateAdherence(log) {
    return log.keys().hasAll(['uid', 'medicationId', 'date', 'status'])
      && log.uid == request.auth.uid
      && log.status in ['taken', 'skipped', 'pending'];
  }
}
```

---

## Pagination Specification (Future)

When implemented for large datasets:

**Query Parameters**:
```
GET /medications?limit=20&page=1&orderBy=createdAt&direction=desc
```

**Response Format**:
```json
{
  "data": [...],
  "pagination": {
    "total": 150,
    "page": 1,
    "limit": 20,
    "hasMore": true,
    "nextPage": 2
  }
}
```

---

## Webhook Specifications (Future)

When healthcare provider integration added:

**Event Types**:
- `medication.created`
- `medication.updated`
- `medication.deactivated`
- `adherence.logged`
- `user.profile.updated`

**Webhook Payload**:
```json
{
  "id": "event-uuid",
  "type": "adherence.logged",
  "timestamp": "2026-05-06T10:30:00Z",
  "data": {
    "medicationId": "med-uuid",
    "userId": "firebase-uid",
    "status": "taken",
    "date": "2026-05-06"
  }
}
```

---

## Versioning Strategy

**Current API Version**: 1.0  
**Compatibility**: No breaking changes in v1.x  
**Deprecation**: 6-month notice before removing endpoints

---

## Testing Data

### Test User Accounts

```
Email: test@example.com
Password: TestPassword123

Email: demo@example.com
Password: DemoPassword456
```

### Test Medications

```
Metformin 500mg (pill, twice daily)
Aspirin 100mg (pill, once daily)
Cough Syrup 10ml (syrup, thrice daily)
```

### Test Conditions

```
Type 2 Diabetes
Hypertension
Asthma
```

---

## API Endpoint Roadmap (Q3 2026+)

### Planned REST API

```
GET    /api/v1/medications          - List medications
POST   /api/v1/medications          - Create medication
PUT    /api/v1/medications/{id}     - Update medication
DELETE /api/v1/medications/{id}     - Delete medication

GET    /api/v1/adherence/date/:date - Get adherence for date
POST   /api/v1/adherence            - Log adherence
GET    /api/v1/adherence/summary    - Adherence statistics

GET    /api/v1/profile              - Get health profile
PUT    /api/v1/profile              - Update profile
```

### Planned GraphQL Schema

```graphql
type Query {
  medications: [Medication!]!
  adherenceForDate(date: String!): [AdherenceLog!]!
  profile: HealthProfile!
}

type Mutation {
  addMedication(input: MedicationInput!): Medication!
  logAdherence(input: AdherenceInput!): AdherenceLog!
  updateProfile(input: ProfileInput!): HealthProfile!
}

type Subscription {
  medicationChanged: Medication!
  adherenceLogged: AdherenceLog!
}
```

---

## References

- [Firebase Documentation](https://firebase.google.com/docs)
- [Firestore Data Model](https://cloud.google.com/firestore/docs/data-model)
- [REST API Reference](https://firebase.google.com/docs/reference/rest/auth)
- [Security Rules Guide](https://firebase.google.com/docs/firestore/security)
