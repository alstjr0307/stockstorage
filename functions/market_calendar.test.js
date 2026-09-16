'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PARSERS, fetchOfficialCalendars, ismEvents } = require('./market_calendar_official');
const { runCalendarSync, fetchEconomic } = require('./market_calendar');
const axios = require('axios');

test('FOMC cross-month meeting uses final day and published minutes override 21-day rule', () => {
  const events = PARSERS.fed(`<div><div class="panel-heading">2026 FOMC Meetings</div>
    <div class="fomc-meeting"><div class="fomc-meeting__month">Jan/Feb</div>
    <div class="fomc-meeting__date">31-1*</div><div class="fomc-meeting__minutes">Released February 25, 2026</div></div></div>`);
  assert.equal(events.length, 4);
  assert.equal(events[0].date, '2026-02-01');
  assert.equal(events[3].date, '2026-02-25');
  assert.equal(events[3].extra.scheduledByRule, false);
});

test('ECB excludes non-policy and first-day meetings', () => {
  const events = PARSERS.ecb(`<dl><dt>28/10/2026</dt><dd>monetary policy meeting (Day 1)</dd>
    <dt>29/10/2026</dt><dd>monetary policy meeting (Day 2)</dd>
    <dt>30/10/2026</dt><dd>non-monetary policy meeting (Day 2)</dd></dl>`);
  assert.deepEqual(events.map(e => e.date), ['2026-10-29']);
});

test('BOJ minutes use explicit next-year date', () => {
  const events = PARSERS.boj(`<table><caption>Table : 2026</caption><thead><tr><th>Date of MPM</th></tr></thead>
    <tbody><tr><td>Dec. 17 (Thurs.), 18 (Fri.)</td><td>-</td><td>Dec. 28 (Mon.)</td><td>Jan. 27 (Wed.), 2027</td></tr></tbody></table>`);
  assert.equal(events.find(e => e.extra.category === 'minutes').date, '2027-01-27');
});

test('June options expiration moves back for Juneteenth', () => {
  const events = PARSERS.nyse(`<table><thead><tr><th>Holiday</th><th>2026</th></tr></thead>
    <tbody><tr><th>Juneteenth</th><td>Friday, June 19</td></tr></tbody></table>`);
  assert.ok(events.some(e => e.extra.category === 'options' && e.date === '2026-06-18'));
});

test('malformed official pages report failure instead of empty success', async () => {
  const results = await fetchOfficialCalendars('2026-09-13', '2026-12-12', async () => ({ data: '<html>maintenance</html>' }));
  assert.ok(results.filter(r => r.source !== 'ism').every(r => r.error));
  assert.throws(() => ismEvents('2027-01-01'), /refresh/);
});

test('FRED reads following pages without dropping later core releases', async () => {
  const oldGet = axios.get;
  const offsets = [];
  axios.get = async (_, { params }) => {
    offsets.push(params.offset);
    return { data: { count: 1001, release_dates: params.offset === 0
      ? Array.from({ length: 1000 }, () => ({ date: '2026-09-14', release_name: 'Ignored' }))
      : [{ date: '2026-09-16', release_name: 'Consumer Price Index', release_id: 10 }] } };
  };
  try {
    assert.equal((await fetchEconomic('test', '2026-09-13', '2026-10-04')).length, 1);
    assert.deepEqual(offsets, [0, 1000]);
  } finally { axios.get = oldGet; }
});

test('sync preserves failed and unconfigured feeds; removes expired and superseded successful feed events', async () => {
  const records = new Map([
    ['fed_old', { source: 'fed', type: 'economic', date: '2026-09-16' }],
    ['ecb_keep', { source: 'ecb', type: 'economic', date: '2026-10-29' }],
    ['earnings_keep', { source: 'finnhub', type: 'earnings', date: '2026-09-20' }],
    ['expired', { source: 'ecb', type: 'economic', date: '2026-09-01' }],
  ]);
  const db = {
    collection: name => ({ get: async () => ({ docs: [...records].map(([id, data]) => ({ id, ref: id, data: () => data })) }),
      doc: id => name === 'market_calendar_meta' ? { set: async () => {} } : id }),
    batch: () => ({ delete: id => records.delete(id), set: (id, data) => records.set(id, data), commit: async () => {} }),
  };
  await runCalendarSync(db, { now: new Date('2026-09-13T12:00:00Z'), officialFetcher: async () => [
    { source: 'fed', events: [{ id: 'fed_new', source: 'fed', type: 'economic', date: '2026-09-17' }] },
    { source: 'ecb', events: [], error: 'timeout' },
  ] });
  assert.deepEqual([...records.keys()].sort(), ['earnings_keep', 'ecb_keep', 'fed_new']);
});

test('FRED retries a transient gateway failure', async () => {
  const oldGet = axios.get;
  let calls = 0;
  axios.get = async () => {
    if (++calls === 1) throw Object.assign(new Error('gateway'), { response: { status: 502 } });
    return { data: { release_dates: [{ date: '2026-09-16', release_name: 'Consumer Price Index', release_id: 10 }] } };
  };
  try {
    assert.equal((await fetchEconomic('test', '2026-09-13', '2026-12-12')).length, 1);
    assert.equal(calls, 2);
  } finally { axios.get = oldGet; }
});
