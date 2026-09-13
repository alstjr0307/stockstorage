const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, deleteDoc, getDoc, getDocs, collection, query, where, writeBatch, runTransaction } = require('firebase/firestore');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-journal', firestore: {
    host: '127.0.0.1', port: 8787,
    rules: readFileSync(resolve(__dirname, '../../firestore.rules'), 'utf8'),
  }});
});
after(async () => env?.cleanup());
const trade = (uid, quantity = 10) => ({uid, price: 100, quantity, action: '매수', isPublic: false, likes: 0});
test('legacy CRUD works without revision; owner data stays protected', async () => {
  const db = env.authenticatedContext('owner').firestore();
  const ref = doc(db, 'trading_journal/first');
  await assertSucceeds(setDoc(ref, trade('owner')));
  const batch = writeBatch(db);
  batch.set(ref, trade('owner'));
  batch.set(doc(db, 'journal_revisions/owner'), {revision: 1, journalId: 'first'});
  await assertSucceeds(batch.commit());
  await assertSucceeds(updateDoc(ref, {quantity: 11}));
  await assertSucceeds(deleteDoc(ref));
  await assertSucceeds(setDoc(ref, trade('owner')));
  await assertSucceeds(updateDoc(ref, {note: 'keep finance unchanged'}));
  await assertSucceeds(updateDoc(ref, {isPublic: true}));
  const other = env.authenticatedContext('other').firestore();
  await assertSucceeds(updateDoc(doc(other, ref.path), {likes: 1}));
  await assertFails(updateDoc(doc(other, ref.path), {quantity: 1}));
  await assertFails(getDoc(doc(other, 'journal_revisions/owner')));
  const deletion = writeBatch(db);
  deletion.delete(ref);
  deletion.set(doc(db, 'journal_revisions/owner'), {revision: 2, journalId: 'first'});
  await assertSucceeds(deletion.commit());
});
test('optional revisions reject stale writes while legacy inserts remain allowed', async () => {
  const db = env.authenticatedContext('stale').firestore();
  const write = (id, revision) => {
    const batch = writeBatch(db);
    batch.set(doc(db, `trading_journal/${id}`), trade('stale'));
    batch.set(doc(db, 'journal_revisions/stale'), {revision, journalId: id});
    return batch;
  };
  await assertSucceeds(write('one', 1).commit());
  await assertFails(write('two', 1).commit());
  const multi = write('three', 2);
  multi.set(doc(db, 'trading_journal/four'), trade('stale'));
  await assertSucceeds(multi.commit());
  await assertSucceeds(write('two', 3).commit());
  await assertSucceeds(setDoc(doc(db, 'trading_journal/legacy-extra'), trade('stale')));
});
test('two transaction callbacks with the same snapshot cannot both commit', async () => {
  const uid = 'race';
  const db1 = env.authenticatedContext(uid).firestore();
  const db2 = env.authenticatedContext(uid).firestore();
  const attempt = (db, id) => runTransaction(db, async tx => {
    const gate = doc(db, `journal_revisions/${uid}`);
    const snap = await tx.get(gate);
    if ((snap.data()?.revision ?? 0) !== 0) return false; // app must re-read and validate
    tx.set(doc(db, `trading_journal/${id}`), trade(uid));
    tx.set(gate, {revision: 1, journalId: id});
    return true;
  });
  const outcomes = await Promise.allSettled([attempt(db1, 'race-a'), attempt(db2, 'race-b')]);
  assert.equal(outcomes.filter(o => o.status === 'fulfilled' && o.value === true).length, 1);
  for (const result of outcomes.filter(o => o.status === 'rejected')) assert.equal(result.reason.code, 'permission-denied');
});

test('concurrent full sales revalidate after revision contention: only one sale remains', async () => {
  const uid = 'sell-race';
  await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), 'trading_journal/buy-race'), trade(uid)));
  let ready;
  const barrier = new Promise(resolve => { ready = resolve; });
  let arrivals = 0;
  async function sell(db, id) {
    const gate = doc(db, `journal_revisions/${uid}`);
    for (let attempt = 0; attempt < 4; attempt++) {
      const revision = (await getDoc(gate)).data()?.revision ?? 0;
      const rows = await getDocs(query(collection(db, 'trading_journal'), where('uid', '==', uid)));
      const remaining = rows.docs.reduce((qty, d) => qty + (d.data().action === '매수' ? 1 : -1) * d.data().quantity, 0);
      if (remaining < 10) return 'insufficient';
      if (attempt === 0) { if (++arrivals === 2) ready(); await barrier; }
      try {
        const committed = await runTransaction(db, async tx => {
          const current = (await tx.get(gate)).data()?.revision ?? 0;
          if (current !== revision) return false;
          tx.set(doc(db, `trading_journal/${id}`), {...trade(uid), action: '매도'});
          tx.set(gate, {revision: revision + 1, journalId: id});
          return true;
        });
        if (committed) return 'saved';
      } catch (error) {
        if (!['permission-denied', 'aborted'].includes(error.code) || ((await getDoc(gate)).data()?.revision ?? 0) === revision) throw error;
      }
    }
    throw Error('retry exhausted');
  }
  const results = await Promise.all([sell(env.authenticatedContext(uid).firestore(), 'sell-a'), sell(env.authenticatedContext(uid).firestore(), 'sell-b')]);
  assert.deepEqual(results.sort(), ['insufficient', 'saved']);
  const rows = await getDocs(query(collection(env.authenticatedContext(uid).firestore(), 'trading_journal'), where('uid', '==', uid)));
  assert.equal(rows.size, 2);
});
