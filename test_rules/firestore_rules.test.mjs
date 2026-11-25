// Firestore security-rule tests for the Sprint 4 collections (run on the
// emulator). Verifies: alertDispatchLog is service-only (no client access);
// userAlerts is owner-read + owner-mark-read only, never cross-user, never
// client-created/edited/deleted. The dispatch engine writes via the Admin SDK,
// which bypasses rules (simulated here with withSecurityRulesDisabled).
//
// Run from the project root:
//   firebase emulators:exec --only firestore --project demo-foreseeme \
//     "node test_rules/firestore_rules.test.mjs"

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  query,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  where,
} from 'firebase/firestore';

const rules = readFileSync(
  fileURLToPath(new URL('../firestore.rules', import.meta.url)),
  'utf8',
);

const testEnv = await initializeTestEnvironment({
  projectId: 'demo-foreseeme',
  firestore: { rules },
});

let failures = 0;
let passed = 0;
async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log('  PASS  ' + name);
  } catch (err) {
    failures++;
    console.error('  FAIL  ' + name + '  -  ' + err.message);
  }
}

const alice = testEnv.authenticatedContext('alice', { email: 'alice@example.com', email_verified: true }).firestore();
const bob = testEnv.authenticatedContext('bob', { email_verified: true }).firestore();
const admin = testEnv.authenticatedContext('op', { admin: true, firebase: { sign_in_second_factor: 'totp' } }).firestore();
const passwordAdmin = testEnv.authenticatedContext('password-admin', { admin: true }).firestore();
const anon = testEnv.unauthenticatedContext().firestore();

// Seed as the engine/back-end would (Admin SDK bypasses rules).
await testEnv.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  await setDoc(doc(db, 'userAlerts/alice/items/a1'), {
    title: 'Air quality rising',
    pushId: 'fixture-reference',
    read: false,
  });
  await setDoc(doc(db, 'userAlerts/alice/items/legacy'), {
    title: 'Legacy alert',
    read: false,
  });
  await setDoc(doc(db, 'alertDispatchLog/log1'), { uid: 'alice' });
  // Back-end service-account writes (never client-writable).
  await setDoc(doc(db, 'riskEstimates/Lahore_2026-07-08'), {
    city: 'Lahore',
    riskLevel: 'High',
  });
  await setDoc(doc(db, 'jobHeartbeats/compute_risk'), { ok: true });
  await setDoc(doc(db, 'adminActivityLog/log1'), { action: 'override_set' });
  await setDoc(doc(db, 'overrides/Lahore'), { active: true });
  await setDoc(doc(db, 'articles/lungs-smog'), { title: 'Lungs' });
  await setDoc(doc(db, 'operationalMetrics/accounts'), { totalUsers: 5 });
  await setDoc(doc(db, 'userDirectory/disabled'), { status: 'active', authDisabled: true });
  await setDoc(doc(db, 'adminAccountOperations/deleted'), { deleted: true });
  // A pre-existing user document + owned subtree item.
  await setDoc(doc(db, 'users/alice'), { fcmToken: 'seed' });
  await setDoc(doc(db, 'notificationRegistrations/seed'), { uid: 'alice' });
  await setDoc(doc(db, 'users/alice/medications/m1'), { name: 'Inhaler' });
  await setDoc(doc(db, 'users/alice/adherenceLogs/event'), { taken: true });
  // A document under a collection with NO explicit rule — must be default-denied.
  await setDoc(doc(db, 'unmatchedCollection/x1'), { any: 'thing' });
});

await check('notification registry: owner cannot read', () =>
  assertFails(getDoc(doc(alice, 'notificationRegistrations/seed'))),
);
await check('notification registry: owner cannot create', () =>
  assertFails(setDoc(doc(alice, 'notificationRegistrations/other'), { uid: 'alice' })),
);
await check('notification registry: owner cannot update', () =>
  assertFails(updateDoc(doc(alice, 'notificationRegistrations/seed'), { uid: 'bob' })),
);
await check('notification registry: owner cannot delete', () =>
  assertFails(deleteDoc(doc(alice, 'notificationRegistrations/seed'))),
);
await check('notification registry: MFA administrator cannot read', () =>
  assertFails(getDoc(doc(admin, 'notificationRegistrations/seed'))),
);

// alertDispatchLog — service-only, no client access.
await check('alertDispatchLog: client read denied', () =>
  assertFails(getDoc(doc(alice, 'alertDispatchLog/log1'))),
);
await check('alertDispatchLog: client write denied', () =>
  assertFails(setDoc(doc(alice, 'alertDispatchLog/x'), { uid: 'alice' })),
);
// M8.1: the System Monitoring Dashboard (SDS FR8.1, "alerts count") needs an
// admin-only read path onto the dispatch ledger — a deliberate, narrow widening
// of the admin claim's scope (see firestore.rules). Write stays sealed to the
// service account even for admins.
await check('alertDispatchLog: MFA admin cannot access per-user dispatch records', () =>
  assertFails(getDoc(doc(admin, 'alertDispatchLog/log1'))),
);
await check('alertDispatchLog: admin claim does not grant write', () =>
  assertFails(setDoc(doc(admin, 'alertDispatchLog/x'), { uid: 'alice' })),
);

// userAlerts — owner read, scoped mark-read; nothing else.
await check('userAlerts: owner reads own alert', () =>
  assertSucceeds(getDoc(doc(alice, 'userAlerts/alice/items/a1'))),
);
await check('userAlerts: cross-user read denied', () =>
  assertFails(getDoc(doc(bob, 'userAlerts/alice/items/a1'))),
);
const inboxPush = (db) => query(
  collection(db, 'userAlerts/alice/items'),
  where('pushId', '==', 'fixture-reference'),
  limit(1),
);
await check('userAlerts: owner can query inbox by push reference', () =>
  assertSucceeds(getDocs(inboxPush(alice))).then((snapshot) => {
    if (snapshot.size !== 1 || snapshot.docs[0].id !== 'a1') {
      throw new Error('The query did not resolve the expected inbox item');
    }
  }),
);
await check('userAlerts: other user cannot query owner inbox', () =>
  assertFails(getDocs(inboxPush(bob))),
);
await check('userAlerts: owner cannot create', () =>
  assertFails(setDoc(doc(alice, 'userAlerts/alice/items/a2'), { title: 't' })),
);
await check('userAlerts: owner may mark read (read/readAt only)', () =>
  assertSucceeds(
    updateDoc(doc(alice, 'userAlerts/alice/items/a1'), {
      read: true,
      readAt: serverTimestamp(),
    }),
  ),
);
await check('userAlerts: owner may mark a legacy alert read', () =>
  assertSucceeds(updateDoc(doc(alice, 'userAlerts/alice/items/legacy'), {
    read: true, readAt: serverTimestamp(),
  })),
);
await check('userAlerts: owner cannot replace the server push reference', () =>
  assertFails(updateDoc(doc(alice, 'userAlerts/alice/items/a1'), {
    pushId: 'forged-reference',
  })),
);
await check('userAlerts: owner cannot add a push reference to a legacy alert', () =>
  assertFails(updateDoc(doc(alice, 'userAlerts/alice/items/legacy'), {
    pushId: 'forged-reference',
  })),
);
await check('userAlerts: owner cannot edit content', () =>
  assertFails(
    updateDoc(doc(alice, 'userAlerts/alice/items/a1'), { title: 'hacked' }),
  ),
);
await check('userAlerts: owner cannot delete', () =>
  assertFails(deleteDoc(doc(alice, 'userAlerts/alice/items/a1'))),
);
// M7.0 gap: only cross-user READ was previously tested; a non-owner write
// path (update/delete) was unverified.
await check('userAlerts: cross-user update (mark-read) denied', () =>
  assertFails(
    updateDoc(doc(bob, 'userAlerts/alice/items/a1'), {
      read: true,
      readAt: serverTimestamp(),
    }),
  ),
);
await check('userAlerts: cross-user delete denied', () =>
  assertFails(deleteDoc(doc(bob, 'userAlerts/alice/items/a1'))),
);
// M7.0 gap (still true post-M8.1): the admin custom-claim must not be a
// backdoor into another user's inbox. Admin's extra rights are narrow and
// explicit — write on `overrides`, read on `jobHeartbeats`/`alertDispatchLog`
// (M8.1) — and `userAlerts` grants it nothing at all.
await check('userAlerts: admin claim does not grant cross-user read', () =>
  assertFails(getDoc(doc(admin, 'userAlerts/alice/items/a1'))),
);
await check('userAlerts: admin claim does not grant cross-user mark-read', () =>
  assertFails(
    updateDoc(doc(admin, 'userAlerts/alice/items/a1'), {
      read: true,
      readAt: serverTimestamp(),
    }),
  ),
);

// overrides/{city} (Sprint 5 P13) — admin-role write, authenticated read.
const overrideDoc = {
  city: 'Lahore',
  riskLevel: 'High',
  disease: 'Smog',
  reason: 'Pipeline delayed; AQI spiked per advisory.',
  authorUid: 'op',
  authorEmail: 'op@example.com',
  createdAt: '2026-07-02T00:00:00.000Z',
  active: true,
};
await check('overrides: client admin cannot bypass audited API', () =>
  assertFails(setDoc(doc(admin, 'overrides/Lahore'), overrideDoc)),
);
await check('overrides: authenticated user may read', () =>
  assertSucceeds(getDoc(doc(alice, 'overrides/Lahore'))),
);
await check('overrides: non-admin write denied', () =>
  assertFails(setDoc(doc(alice, 'overrides/Karachi'), overrideDoc)),
);
await check('overrides: non-admin cannot clear (update) an override', () =>
  assertFails(updateDoc(doc(bob, 'overrides/Lahore'), { active: false })),
);
await check('overrides: unauthenticated read denied', () =>
  assertFails(getDoc(doc(anon, 'overrides/Lahore'))),
);

// articles/{articleId} (Sprint M8.3) — the Resource Center CMS (SDS FR8.3):
// authed read, admin-only write.
const articleDoc = {
  title: 'Protecting your lungs on smog days',
  summary: 'Cut your exposure to fine particles when air quality is poor.',
  topic: 'lungs',
  sourceName: 'World Health Organization (WHO)',
  sourceUrl: 'https://www.who.int/health-topics/air-pollution',
  content: [{ kind: 'paragraph', text: 'Check your local AQI.' }],
  verified: true,
};
await check('articles: client admin cannot create directly', () =>
  assertFails(setDoc(doc(admin, 'articles/lungs-smog'), articleDoc)),
);
await check('articles: authenticated user may read', () =>
  assertSucceeds(getDoc(doc(alice, 'articles/lungs-smog'))),
);
await check('articles: client admin cannot update directly', () =>
  assertFails(
    updateDoc(doc(admin, 'articles/lungs-smog'), { summary: 'Updated.' }),
  ),
);
await check('articles: non-admin write denied', () =>
  assertFails(setDoc(doc(alice, 'articles/other'), articleDoc)),
);
await check('articles: unauthenticated read denied', () =>
  assertFails(getDoc(doc(anon, 'articles/lungs-smog'))),
);

// userDirectory/{uid} (Sprint M8.4) — the admin user directory (SDS FR8.5):
// owner-only write, admin-only read.
const directoryEntry = {
  email: 'alice@example.com',
  createdAt: '2026-07-27T00:00:00.000Z',
  status: 'pending',
};
await check('userDirectory: owner may write their own entry', () =>
  assertSucceeds(setDoc(doc(alice, 'userDirectory/alice'), directoryEntry)),
);
await check('userDirectory: admin (claim) may read', () =>
  assertSucceeds(getDoc(doc(admin, 'userDirectory/alice'))),
);
await check('userDirectory: non-owner write denied', () =>
  assertFails(setDoc(doc(bob, 'userDirectory/alice'), directoryEntry)),
);
await check('userDirectory: non-admin read denied', () =>
  assertFails(getDoc(doc(bob, 'userDirectory/alice'))),
);
await check('userDirectory: unauthenticated read denied', () =>
  assertFails(getDoc(doc(anon, 'userDirectory/alice'))),
);
await check('userDirectory: unauthenticated write denied', () =>
  assertFails(setDoc(doc(anon, 'userDirectory/eve'), directoryEntry)),
);

// adminActivityLog/{entryId} (Sprint M8.2) — admin-only, append-only audit
// trail (SDS FR8.4). Create + read gated to the admin claim; immutable
// afterwards, even for an admin.
const logEntry = {
  action: 'override_set',
  target: 'Lahore',
  summary: 'Set Lahore risk to High (Smog)',
  authorUid: 'op',
  authorEmail: 'op@example.com',
  createdAt: '2026-07-27T00:00:00.000Z',
};
await check('adminActivityLog: MFA admin cannot forge a privileged event', () =>
  assertFails(setDoc(doc(admin, 'adminActivityLog/log1'), logEntry)),
);
await check('adminActivityLog: admin (claim) may read', () =>
  assertSucceeds(getDoc(doc(admin, 'adminActivityLog/log1'))),
);
await check('adminActivityLog: non-admin create denied', () =>
  assertFails(setDoc(doc(alice, 'adminActivityLog/log2'), logEntry)),
);
await check('adminActivityLog: non-admin read denied', () =>
  assertFails(getDoc(doc(alice, 'adminActivityLog/log1'))),
);
await check('adminActivityLog: unauthenticated read denied', () =>
  assertFails(getDoc(doc(anon, 'adminActivityLog/log1'))),
);
await check('adminActivityLog: admin cannot update an existing entry (immutable)', () =>
  assertFails(updateDoc(doc(admin, 'adminActivityLog/log1'), { summary: 'edited' })),
);
await check('adminActivityLog: admin cannot delete an existing entry (immutable)', () =>
  assertFails(deleteDoc(doc(admin, 'adminActivityLog/log1'))),
);

// riskEstimates (ADR-001) — authenticated read; clients never write.
await check('riskEstimates: authenticated user may read', () =>
  assertSucceeds(getDoc(doc(alice, 'riskEstimates/Lahore_2026-07-08'))),
);
await check('riskEstimates: unauthenticated read denied', () =>
  assertFails(getDoc(doc(anon, 'riskEstimates/Lahore_2026-07-08'))),
);
await check('riskEstimates: client write denied', () =>
  assertFails(setDoc(doc(alice, 'riskEstimates/x'), { riskLevel: 'Low' })),
);

// jobHeartbeats (Sprint 5 P12) — service-account only; no client access.
await check('jobHeartbeats: client read denied', () =>
  assertFails(getDoc(doc(alice, 'jobHeartbeats/compute_risk'))),
);
await check('jobHeartbeats: client write denied', () =>
  assertFails(setDoc(doc(alice, 'jobHeartbeats/y'), { ok: false })),
);
// M8.1: the System Monitoring Dashboard (SDS FR8.1, "last run time" / job
// health) needs an admin-only read path onto the heartbeats — see
// firestore.rules and the matching alertDispatchLog grant above. Write stays
// sealed to the service account even for admins.
await check('jobHeartbeats: admin (claim) may read', () =>
  assertSucceeds(getDoc(doc(admin, 'jobHeartbeats/compute_risk'))),
);
await check('operationalMetrics: MFA admin can read aggregate accounts', () =>
  assertSucceeds(getDoc(doc(admin, 'operationalMetrics/accounts'))),
);
await check('operationalMetrics: role without MFA is denied', () =>
  assertFails(getDoc(doc(passwordAdmin, 'operationalMetrics/accounts'))),
);
await check('operationalMetrics: ordinary user is denied', () =>
  assertFails(getDoc(doc(alice, 'operationalMetrics/accounts'))),
);
await check('userDirectory: owner cannot forge disabled status', () =>
  assertFails(updateDoc(doc(alice, 'userDirectory/alice'), { authDisabled: true })),
);
await check('userDirectory: disabled owner cannot change their entry', () =>
  assertFails(updateDoc(doc(testEnv.authenticatedContext('disabled').firestore(),
    'userDirectory/disabled'), { status: 'pending' })),
);
await check('userDirectory: deleted owner cannot recreate entry', () =>
  assertFails(setDoc(doc(testEnv.authenticatedContext('deleted').firestore(),
    'userDirectory/deleted'), { status: 'pending' })),
);
await check('adminActivityLog: role without MFA cannot read', () =>
  assertFails(getDoc(doc(passwordAdmin, 'adminActivityLog/log1'))),
);
await check('jobHeartbeats: admin claim does not grant write', () =>
  assertFails(setDoc(doc(admin, 'jobHeartbeats/y'), { ok: false })),
);

// Settings and known health subcollections remain owner-only.
await check('users: owner reads own document', () =>
  assertSucceeds(getDoc(doc(alice, 'users/alice'))),
);
await check('users: owner cannot write the legacy FCM token', () =>
  assertFails(updateDoc(doc(alice, 'users/alice'), { fcmToken: 'refreshed' })),
);
await check('users: owner can update preferences alongside existing legacy fields', () =>
  assertSucceeds(updateDoc(doc(alice, 'users/alice'), {
    notificationPreferences: { highRiskAlerts: false },
  })),
);
await check('users: cross-user read denied', () =>
  assertFails(getDoc(doc(bob, 'users/alice'))),
);
await check('users: owner reads own medications subtree', () =>
  assertSucceeds(getDoc(doc(alice, 'users/alice/medications/m1'))),
);
await check('users: cross-user medications read denied', () =>
  assertFails(getDoc(doc(bob, 'users/alice/medications/m1'))),
);
await check('users: cross-user write denied', () =>
  assertFails(updateDoc(doc(bob, 'users/alice'), {
    notificationPreferences: { highRiskAlerts: true },
  })),
);
await check('users: arbitrary privileged fields denied', () =>
  assertFails(updateDoc(doc(alice, 'users/alice'), { admin: true })),
);
await check('users: owner can update medication', () =>
  assertSucceeds(updateDoc(doc(alice, 'users/alice/medications/m1'), { isActive: false })),
);
await check('users: cross-user medication writes denied', () =>
  assertFails(updateDoc(doc(bob, 'users/alice/medications/m1'), { isActive: false })),
);
await check('users: owner can write adherence', () =>
  assertSucceeds(setDoc(doc(alice, 'users/alice/adherence_logs/event'), { taken: true })),
);
await check('users: owner can read adherence', () =>
  assertSucceeds(getDoc(doc(alice, 'users/alice/adherence_logs/event'))),
);
await check('users: cross-user adherence reads denied', () =>
  assertFails(getDoc(doc(bob, 'users/alice/adherence_logs/event'))),
);
await check('users: cross-user adherence writes denied', () =>
  assertFails(updateDoc(doc(bob, 'users/alice/adherence_logs/event'), { taken: false })),
);
await check('users: additional clinical fields in medications denied', () =>
  assertFails(updateDoc(doc(alice, 'users/alice/medications/m1'), { diagnosis: 'test' })),
);
await check('users: additional clinical fields in adherence denied', () =>
  assertFails(updateDoc(doc(alice, 'users/alice/adherence_logs/event'), { labResult: 'test' })),
);

const profile = doc(alice, 'users/alice/profile/alice');
const profileData = {
  uid: 'alice', city: 'Lahore', chronicConditions: ['Asthma'], lastUpdated: serverTimestamp(),
};
await check('profile: owner can save allowed fields', () => assertSucceeds(setDoc(profile, profileData)));
await check('profile: owner can read the legacy schema', () => assertSucceeds(getDoc(profile)));
await check('profile: owner can change city and save custom conditions', () =>
  assertSucceeds(updateDoc(profile, {
    city: 'Karachi', chronicConditions: [], customConditions: ['Custom label', 'Another label'],
    lastUpdated: serverTimestamp(),
  })),
);
await check('profile: owner can remove custom conditions', () =>
  assertSucceeds(updateDoc(profile, { customConditions: [], lastUpdated: serverTimestamp() })),
);
for (const customConditions of [
  [''], [' padded'], ['two  spaces'], ['bad\tspace'], ['a'.repeat(65)],
  ['a', 'b', 'c', 'd', 'e', 'f'], ['same', 'same'], [42], { arbitrary: 'field' },
]) {
  await check(`profile: denies malformed custom conditions ${JSON.stringify(customConditions)}`, () =>
    assertFails(updateDoc(profile, { customConditions, lastUpdated: serverTimestamp() })),
  );
}
await check('profile: another verified user cannot read or edit the profile', async () => {
  const foreign = doc(bob, profile.path);
  await assertFails(getDoc(foreign));
  await assertFails(updateDoc(foreign, { city: 'Islamabad', lastUpdated: serverTimestamp() }));
});
await check('profile: unverified owner cannot access active-user data', async () => {
  const pending = testEnv.authenticatedContext('alice', { email_verified: false }).firestore();
  await assertFails(getDoc(doc(pending, profile.path)));
  await assertFails(setDoc(doc(pending, profile.path), profileData));
  await assertFails(getDoc(doc(pending, 'riskEstimates/Lahore_2026-07-08')));
  await assertFails(getDoc(doc(pending, 'userAlerts/alice/items/a1')));
});
await check('profile: wrong city, mismatched UID and protected fields denied', async () => {
  await assertFails(setDoc(profile, { ...profileData, city: 'Unsupported' }));
  await assertFails(setDoc(profile, { ...profileData, uid: 'bob' }));
  await assertFails(updateDoc(profile, { customConditions: [], emailVerified: true, lastUpdated: serverTimestamp() }));
});
await check('profile: clinical results denied', () =>
  assertFails(setDoc(profile, { ...profileData, labResult: 'test data' })),
);
await check('profile: unrecognized condition values denied', () =>
  assertFails(setDoc(profile, { ...profileData, chronicConditions: ['Detailed clinical data'] })),
);
await check('users: unrecognized health subcollections denied', () =>
  assertFails(setDoc(doc(alice, 'users/alice/testResults/result'), { value: 1 })),
);

const record = (db, uid = 'alice', version = 'v1') =>
  doc(db, `medicalDisclaimerAcceptances/${uid}/versions/${version}`);
const accepted = { version: 'v1', acceptedAt: serverTimestamp() };
await check('disclaimer: anonymous read denied', () => assertFails(getDoc(record(anon))));
await check('disclaimer: cross-user write denied', () => assertFails(setDoc(record(bob), accepted)));
await check('disclaimer: extra fields denied', () =>
  assertFails(setDoc(record(alice), { ...accepted, admin: true })),
);
await check('disclaimer: client timestamp denied', () =>
  assertFails(setDoc(record(alice), { ...accepted, acceptedAt: new Date(0) })),
);
await check('disclaimer: unknown version denied', () =>
  assertFails(setDoc(record(alice, 'alice', 'v2'), { ...accepted, version: 'v2' })),
);
await check('disclaimer: owner can create', () => assertSucceeds(setDoc(record(alice), accepted)));
await check('disclaimer: owner can read', () => assertSucceeds(getDoc(record(alice))));
await check('disclaimer: cross-user read denied', () => assertFails(getDoc(record(bob))));
await check('disclaimer: owner cannot rewrite', () => assertFails(setDoc(record(alice), accepted)));
await check('disclaimer: owner cannot delete', () => assertFails(deleteDoc(record(alice))));

await testEnv.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  await setDoc(doc(db, 'sessionRevocations/alice'), { throughAuthTime: 100 });
  await setDoc(doc(db, 'sessionRevocations/alice/logoutIntents/100'), {
    throughAuthTime: 100,
  });
  await setDoc(doc(db, 'sessionRevocations/op'), { throughAuthTime: 100 });
});
const oldAlice = testEnv.authenticatedContext('alice', { auth_time: 100, email_verified: true }).firestore();
const newAlice = testEnv.authenticatedContext('alice', { auth_time: 101, email_verified: true }).firestore();
await check('session: revoked owner cannot read risk data', () =>
  assertFails(getDoc(doc(oldAlice, 'riskEstimates/Lahore_2026-07-08'))),
);
await check('session: revoked owner cannot read private profile data', () =>
  assertFails(getDoc(doc(oldAlice, 'users/alice/profile/alice'))),
);
await check('session: revoked owner cannot write', () =>
  assertFails(updateDoc(doc(oldAlice, 'users/alice'), { notificationPreferences: { highRiskAlerts: false } })),
);
await check('session: revoked MFA administrator cannot read admin data', () =>
  assertFails(getDoc(doc(admin, 'adminActivityLog/log1'))),
);
await check('session: new sign-in can read own profile', () =>
  assertSucceeds(getDoc(doc(newAlice, 'users/alice/profile/alice'))),
);
await check('session: cutoff cannot be read or changed by its owner', async () => {
  const cutoff = doc(newAlice, 'sessionRevocations/alice');
  await assertFails(getDoc(cutoff));
  await assertFails(setDoc(cutoff, { throughAuthTime: 0 }));
});
await check('session: logout receipts are inaccessible to owners and admins', async () => {
  const path = 'sessionRevocations/alice/logoutIntents/100';
  await assertFails(getDoc(doc(newAlice, path)));
  await assertFails(getDoc(doc(admin, path)));
  await assertFails(setDoc(doc(newAlice, path), { throughAuthTime: 0 }));
});

// PRODUCTION DEFAULT-DENY — a collection with no explicit rule is fully denied.
await check('users: MFA administrator cannot read another user medication', () =>
  assertFails(getDoc(doc(admin, 'users/alice/medications/m1'))),
);
await check('users: MFA administrator cannot read another user adherence log', () =>
  assertFails(getDoc(doc(admin, 'users/alice/adherenceLogs/event'))),
);
await check('default-deny: authed read of unmatched collection denied', () =>
  assertFails(getDoc(doc(alice, 'unmatchedCollection/x1'))),
);
await check('default-deny: authed write of unmatched collection denied', () =>
  assertFails(setDoc(doc(alice, 'unmatchedCollection/x2'), { any: 'thing' })),
);
await check('default-deny: unauthenticated access denied', () =>
  assertFails(getDoc(doc(anon, 'unmatchedCollection/x1'))),
);

await testEnv.cleanup();

if (failures > 0) {
  console.error('\n' + failures + ' rule test(s) FAILED');
  process.exit(1);
}
console.log(`\n${passed} rule checks passed, ${failures} failed`);
