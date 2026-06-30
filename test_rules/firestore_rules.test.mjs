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
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
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
async function check(name, fn) {
  try {
    await fn();
    console.log('  PASS  ' + name);
  } catch (err) {
    failures++;
    console.error('  FAIL  ' + name + '  -  ' + err.message);
  }
}

const alice = testEnv.authenticatedContext('alice').firestore();
const bob = testEnv.authenticatedContext('bob').firestore();

// Seed as the engine would (Admin SDK bypasses rules).
await testEnv.withSecurityRulesDisabled(async (context) => {
  const db = context.firestore();
  await setDoc(doc(db, 'userAlerts/alice/items/a1'), {
    title: 'Air quality rising',
    read: false,
  });
  await setDoc(doc(db, 'alertDispatchLog/log1'), { uid: 'alice' });
});

// alertDispatchLog — service-only, no client access.
await check('alertDispatchLog: client read denied', () =>
  assertFails(getDoc(doc(alice, 'alertDispatchLog/log1'))),
);
await check('alertDispatchLog: client write denied', () =>
  assertFails(setDoc(doc(alice, 'alertDispatchLog/x'), { uid: 'alice' })),
);

// userAlerts — owner read, scoped mark-read; nothing else.
await check('userAlerts: owner reads own alert', () =>
  assertSucceeds(getDoc(doc(alice, 'userAlerts/alice/items/a1'))),
);
await check('userAlerts: cross-user read denied', () =>
  assertFails(getDoc(doc(bob, 'userAlerts/alice/items/a1'))),
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
await check('userAlerts: owner cannot edit content', () =>
  assertFails(
    updateDoc(doc(alice, 'userAlerts/alice/items/a1'), { title: 'hacked' }),
  ),
);
await check('userAlerts: owner cannot delete', () =>
  assertFails(deleteDoc(doc(alice, 'userAlerts/alice/items/a1'))),
);

await testEnv.cleanup();

if (failures > 0) {
  console.error('\n' + failures + ' rule test(s) FAILED');
  process.exit(1);
}
console.log('\nAll rule tests passed');
