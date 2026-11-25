import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { deleteApp, initializeApp } from 'firebase/app';
import {
  applyActionCode, confirmPasswordReset, connectAuthEmulator, GoogleAuthProvider,
  createUserWithEmailAndPassword, getAuth, reload, sendEmailVerification,
  sendPasswordResetEmail, signInWithCredential, signInWithEmailAndPassword,
  signOut, updateProfile,
} from 'firebase/auth';
import {
  connectFirestoreEmulator, doc, getDocFromServer, initializeFirestore,
  serverTimestamp, setDoc, terminate, writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-foreseeme';

function requireLoopbackPort(envKey) {
  const match = /^(?:127\.0\.0\.1|localhost):(\d+)$/.exec(process.env[envKey] ?? '');
  if (!match) throw new Error(`${envKey} must identify a local emulator`);
  return Number(match[1]);
}

const authPort = requireLoopbackPort('FIREBASE_AUTH_EMULATOR_HOST');
const firestorePort = requireLoopbackPort('FIRESTORE_EMULATOR_HOST');
const origin = `http://127.0.0.1:${authPort}`;
const app = initializeApp({ projectId, apiKey: 'fake-demo-key' });
const auth = getAuth(app);
connectAuthEmulator(auth, origin, { disableWarnings: true });
const db = initializeFirestore(app, {});
connectFirestoreEmulator(db, '127.0.0.1', firestorePort);

const email = `module1-${randomUUID()}@example.test`;
const password = 'fixture-password-1';
const replacement = 'fixture-password-2';

async function codeFor(requestType) {
  const response = await fetch(`${origin}/emulator/v1/projects/${projectId}/oobCodes`);
  assert.equal(response.ok, true, 'Could not read emulator action codes');
  const { oobCodes } = await response.json();
  const code = oobCodes.findLast(entry =>
    entry.email === email && entry.requestType === requestType)?.oobCode;
  assert.ok(code, 'Expected an emulator action code');
  return code;
}

try {
  const { user } = await createUserWithEmailAndPassword(auth, email, password);
  await assert.rejects(createUserWithEmailAndPassword(auth, email, password), {
    code: 'auth/email-already-in-use',
  });
  await updateProfile(user, { displayName: 'Module One Fixture' });
  const userDoc = doc(db, 'users', user.uid);
  const profile = doc(userDoc, 'profile', user.uid);
  assert.equal(user.emailVerified, false);
  await sendEmailVerification(user);

  await signOut(auth);
  const pending = (await signInWithEmailAndPassword(auth, email, password)).user;
  assert.equal(pending.emailVerified, false);
  await assert.rejects(getDocFromServer(profile), { code: 'permission-denied' });
  await sendEmailVerification(pending);
  await applyActionCode(auth, await codeFor('VERIFY_EMAIL'));
  await reload(pending);
  assert.equal(pending.emailVerified, true);
  assert.equal((await pending.getIdTokenResult(true)).claims.email_verified, true);
  assert.equal(pending.displayName, 'Module One Fixture');
  console.log('PASS: registration, pending sign-in, resend, verification, and fresh token');

  const created = writeBatch(db);
  created.set(userDoc, {}, { merge: true });
  created.set(profile, {
    uid: pending.uid, city: 'Lahore', chronicConditions: [],
    customConditions: ['Custom label'], lastUpdated: serverTimestamp(),
  }, { merge: true });
  await created.commit();
  assert.equal((await getDocFromServer(userDoc)).exists(), true);
  await setDoc(userDoc, { notificationPreferences: { lowRiskUpdates: true } }, { merge: true });
  const edit = writeBatch(db);
  edit.set(userDoc, {}, { merge: true });
  edit.set(profile, { city: 'Karachi', lastUpdated: serverTimestamp() }, { merge: true });
  await edit.commit();
  await signOut(auth);
  await signInWithEmailAndPassword(auth, email, password);
  assert.equal((await getDocFromServer(userDoc)).data().notificationPreferences.lowRiskUpdates, true);
  const stored = (await getDocFromServer(profile)).data();
  assert.equal(stored.city, 'Karachi');
  assert.deepEqual(stored.chronicConditions, []);
  assert.deepEqual(stored.customConditions, ['Custom label']);
  console.log('PASS: owner profile creation, city edit, preference preservation and reload after sign-in');

  await signOut(auth);
  await sendPasswordResetEmail(auth, email);
  const resetCode = await codeFor('PASSWORD_RESET');
  await assert.rejects(confirmPasswordReset(auth, 'invalid-fixture-code', replacement), {
    code: 'auth/invalid-action-code',
  });
  await confirmPasswordReset(auth, resetCode, replacement);
  await assert.rejects(confirmPasswordReset(auth, resetCode, password), {
    code: 'auth/invalid-action-code',
  });
  await assert.rejects(signInWithEmailAndPassword(auth, email, password), (error) =>
    ['auth/wrong-password', 'auth/invalid-credential'].includes(error.code));
  assert.equal((await signInWithEmailAndPassword(auth, email, replacement)).user.emailVerified, true);
  console.log('PASS: password reset, invalid and reused action codes, and sign-in with the new password');

  await signOut(auth);
  // Auth Emulator's documented mock Google credential, guarded by loopback.
  const googleIdentity = GoogleAuthProvider.credential(JSON.stringify({
    sub: randomUUID(), email: `google-${randomUUID()}@example.test`, email_verified: true,
  }));
  const google = (await signInWithCredential(auth, googleIdentity)).user;
  assert.equal(google.emailVerified, true);
  assert.equal((await google.getIdTokenResult()).claims.email_verified, true);
  const googleProfile = doc(db, 'users', google.uid, 'profile', google.uid);
  assert.equal((await getDocFromServer(googleProfile)).exists(), false);
  await setDoc(googleProfile, {
    uid: google.uid, city: 'Islamabad', chronicConditions: ['Asthma'],
    lastUpdated: serverTimestamp(),
  });
  await signOut(auth);
  assert.equal((await signInWithCredential(auth, googleIdentity)).user.uid, google.uid);
  assert.equal((await getDocFromServer(googleProfile)).data().city, 'Islamabad');
  console.log('PASS: verified mock Google account, onboarding and profile restoration');
} finally {
  await terminate(db);
  await deleteApp(app);
}
