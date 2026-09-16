'use strict';
// Read-only live integration verification. Never writes to Firestore or sends push.
const assert = require('node:assert/strict');
const { fetchOfficialCalendars } = require('./market_calendar_official');
async function main() {
  if (process.argv.includes('--firestore')) {
    const admin = require('firebase-admin');
    admin.initializeApp({ credential: admin.credential.cert(require('./serviceAccountKey.json')) });
    const db = admin.firestore();
    // Exactly the legacy app query; verifies server compatibility without claiming device rendering.
    const snap = await db.collection('market_calendar').orderBy('timestamp').limit(200).get();
    const rows = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    for (const source of ['fed', 'ecb', 'boj', 'bok', 'nyse', 'ism', 'fred', 'finnhub']) {
      assert.ok(rows.some(e => e.source === source), `${source} absent from legacy app query`);
    }
    assert.ok(rows.some(e => e.id === 'economic_fed_rate_2026-09-16' && e.type === 'economic' && e.importance === 3));
    require('fs').mkdirSync('../output/calendar-audit', { recursive: true });
    require('fs').writeFileSync('../output/calendar-audit/after.json', JSON.stringify(rows, null, 2));
    console.log(JSON.stringify({ visibleCount: rows.length,
      bySource: rows.reduce((counts, row) => ({ ...counts, [row.source]: (counts[row.source] || 0) + 1 }), {}),
      fomc: rows.filter(e => e.source === 'fed').map(e => ({ date: e.date, title: e.title })),
      lastSync: (await db.collection('market_calendar_meta').doc('last_sync').get()).data(),
    }));
    return;
  }
  const results = await fetchOfficialCalendars('2026-09-13', '2026-12-12');
  for (const result of results) {
    console.log(JSON.stringify(result));
    assert.ok(!result.error, `${result.source}: ${result.error}`);
  }
  const events = results.flatMap(r => r.events);
  for (const [source, date] of [['fed', '2026-09-16'], ['bok', '2026-10-22'], ['boj', '2026-09-18'], ['ecb', '2026-10-29'], ['nyse', '2026-09-18'], ['ism', '2026-10-01']]) {
    assert.ok(events.some(e => e.source === source && e.date === date), `${source} ${date} missing`);
  }
  assert.equal(new Set(events.map(e => e.id)).size, events.length);
  console.log('Official calendar live verification passed');
}
main().catch(e => { console.error(e.message); process.exitCode = 1; });
