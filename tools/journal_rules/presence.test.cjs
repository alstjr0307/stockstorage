const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test, before, after } = require('node:test');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, deleteDoc, getDocs, collection, serverTimestamp, Timestamp, writeBatch, query, where, orderBy } = require('firebase/firestore');
const assert = require('node:assert/strict');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-presence', firestore: {
    host: '127.0.0.1', port: 8790,
    rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
});
after(async () => env?.cleanup());
test('daily visitors deduplicate devices and remain after live sessions close', async () => {
  const uid = 'daily-visitor';
  const owner = env.authenticatedContext(uid).firestore();
  const admin = env.authenticatedContext('1KzEXKZMoFaYOymYyoI283AR3Y32').firestore();
  await setDoc(doc(owner, 'users', uid), {nickname: 'daily-test'});
  for (const id of ['phone', 'browser']) {
    const batch = writeBatch(owner);
    batch.set(doc(owner, 'presence_sessions', id), {uid, platform: 'web', lastSeen: serverTimestamp()});
    batch.set(doc(owner, 'users', uid), {lastActiveAt: serverTimestamp()}, {merge: true});
    await assertSucceeds(batch.commit());
  }
  const kst = new Date(Date.now() + 9 * 3600000);
  const start = Date.UTC(kst.getUTCFullYear(), kst.getUTCMonth(), kst.getUTCDate()) - 9 * 3600000;
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'users/yesterday'), {lastActiveAt: Timestamp.fromMillis(start - 1)});
    await setDoc(doc(ctx.firestore(), 'users/tomorrow'), {lastActiveAt: Timestamp.fromMillis(start + 86400000)});
  });
  const visitors = db => query(collection(db, 'users'),
    where('lastActiveAt', '>=', Timestamp.fromMillis(start)),
    where('lastActiveAt', '<', Timestamp.fromMillis(start + 86400000)),
    orderBy('lastActiveAt', 'desc'));
  const before = await assertSucceeds(getDocs(visitors(admin)));
  assert.deepEqual(before.docs.map(d => d.id), [uid]);
  assert.equal(before.docs[0].data().nickname, 'daily-test');
  await assertFails(getDocs(visitors(owner)));
  await assertFails(getDocs(visitors(env.unauthenticatedContext().firestore())));
  await deleteDoc(doc(owner, 'presence_sessions/phone'));
  await deleteDoc(doc(owner, 'presence_sessions/browser'));
  const after = await getDocs(visitors(admin));
  assert.deepEqual(after.docs.map(d => d.id), [uid]);
});
test('only admins can list sessions; only owners can write and remove them', async () => {
  const owner = env.authenticatedContext('owner').firestore();
  const other = env.authenticatedContext('other').firestore();
  const guest = env.unauthenticatedContext().firestore();
  const admin = env.authenticatedContext('1KzEXKZMoFaYOymYyoI283AR3Y32').firestore();
  const path = 'presence_sessions/device';
  const data = () => ({uid: 'owner', platform: 'android', lastSeen: serverTimestamp()});
  await assertSucceeds(setDoc(doc(owner, path), data()));
  await assertSucceeds(setDoc(doc(owner, path), data()));
  await assertSucceeds(getDocs(collection(admin, 'presence_sessions')));
  for (const db of [owner, other, guest]) {
    await assertFails(getDocs(collection(db, 'presence_sessions')));
  }
  await assertFails(setDoc(doc(other, path), {...data(), uid: 'other'}));
  await assertFails(setDoc(doc(other, 'presence_sessions/spoof'), data()));
  await assertFails(setDoc(doc(guest, 'presence_sessions/guest'), data()));
  await assertFails(deleteDoc(doc(other, path)));
  await assertFails(setDoc(doc(owner, path), {...data(), lastSeen: Timestamp.fromMillis(Date.now() + 600000)}));
  await assertFails(setDoc(doc(owner, path), {...data(), extra: true}));
  await assertSucceeds(deleteDoc(doc(owner, path)));
});
