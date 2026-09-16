'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const axios = require('axios');
const { newsWindow, selectNews, fetchBriefNews, fetchMorningContext } = require('./ai_brief_morning');
const { buildAiBriefPrompt, runAiBriefGeneration, getAiBriefSlotMeta, fetchUsMarketData, generateBriefWithOpenAi } = require('./ai_brief');
const now = new Date('2026-09-15T23:00:00Z');
const quote = { price: 3000, change: 10, changeRate: 0.33, isUp: true, tradedDate: '2026-09-15', marketStatus: 'CLOSE' };
const sections = { summary: '밤사이 주요 변수를 점검합니다.', news: [], index: '미국 시장을 확인했습니다.', sector: '개장 후 흐름을 확인합니다.', flow: '환율을 점검합니다.', checkpoint: '주요 일정을 확인합니다.' };

test('morning window includes the prior close and Monday weekend, excludes future', () => {
  assert.equal(newsWindow('08', now).start.toISOString(), '2026-09-15T06:30:00.000Z');
  assert.equal(newsWindow('08', new Date('2026-09-13T23:00:00Z')).start.toISOString(), '2026-09-11T06:30:00.000Z');
  const items = [
    { title: 'old', pubDate: '2026-09-15T06:29:59Z' },
    { title: 'valid', pubDate: '2026-09-15T12:00:00Z' },
    { title: 'future', pubDate: '2026-09-16T00:00:00Z' },
    { title: 'unknown' },
  ];
  assert.deepEqual(selectNews([items], newsWindow('08', now)).map(n => n.title), ['valid']);
});

test('selection preserves every query category and removes duplicate headlines', () => {
  const row = title => ({ title, pubDate: '2026-09-15T12:00:00Z' });
  const result = selectNews([Array.from({ length: 20 }, (_, i) => row(`US${i}`)), [row('macro')], [row('US0'), row('KR')]], newsWindow('08', now));
  assert.equal(result.length, 12);
  assert.ok(result.some(n => n.title === 'macro'));
  assert.ok(result.some(n => n.title === 'KR'));
  assert.equal(result.filter(n => n.title === 'US0').length, 1);
});

test('RSS failures are isolated and source/time/link survive parsing', async () => {
  let calls = 0;
  const news = await fetchBriefNews('08', now, async () => {
    if (++calls === 1) throw new Error('timeout');
    return { data: '<rss><channel><item><title>주요 뉴스</title><pubDate>Tue, 15 Sep 2026 12:00:00 GMT</pubDate><source>신문</source><link>https://example.com/story</link></item></channel></rss>' };
  });
  assert.equal(news.length, 1);
  assert.equal(news[0].source, '신문');
  assert.equal(news[0].url, 'https://example.com/story');
});

test('morning prompt accepts missing domestic data without invented current flows', () => {
  const prompt = buildAiBriefPrompt(null, null, null, null, [], null, null, '08', {}, now);
  assert.match(prompt, /오전 8시/);
  assert.match(prompt, /한국 정규장은 개장 전/);
  assert.match(prompt, /이전 거래일 값만으로 국내 휴장을 판정하지/);
  assert.match(prompt, /한국시간 오늘 몇 시라고 변환·추정하지/);
  assert.equal(getAiBriefSlotMeta('09').timeLabel, '08:00');
});

test('midday and closing keep their domestic focus and morning comparison', () => {
  for (const slot of ['12', '15']) {
    const prompt = buildAiBriefPrompt({ kospi: quote, kosdaq: quote }, null, null, null, [], null, null, slot, { morningSummary: '아침 이슈' }, now);
    assert.match(prompt, slot === '12' ? /오전장을 지나며/ : /최종 지수 흐름/);
    assert.match(prompt, /아침 이슈/);
  }
});

function fakeDb() {
  const writes = [];
  let commits = 0;
  return {
    writes, get commits() { return commits; },
    collection: name => ({
      doc: id => ({ name, id, get: async () => ({ data: () => ({}) }) }),
      where: () => ({ get: async () => ({ docs: [] }) }),
    }),
    batch: () => ({ set: (ref, payload) => writes.push({ ref, payload }), commit: async () => { commits++; } }),
  };
}

function mockSources(t, { domesticFailure = false, allFailure = false, badOutput = false } = {}) {
  const calls = [];
  t.mock.method(axios, 'get', async url => {
    calls.push(url);
    if (allFailure) throw new Error('source down');
    if (url.includes('/basic')) {
      if (domesticFailure) throw new Error('domestic down');
      return { data: { closePrice: '3000', compareToPreviousClosePrice: '10', fluctuationsRatio: '0.33', marketStatus: 'CLOSE', localTradedAt: '2026-09-15T15:30:00' } };
    }
    if (url.includes('news.google.com')) return { data: '<rss><channel/></rss>' };
    if (url.includes('finance/chart')) return { data: { chart: { result: [{
      meta: { regularMarketPrice: 100, regularMarketTime: +new Date('2026-09-15T20:00:00Z') / 1000 },
      timestamp: [1789416000, 1789502400], indicators: { quote: [{ close: [99, 100] }] },
    }] } } };
    throw new Error(`Unexpected source ${url}`);
  });
  t.mock.method(global, 'fetch', async () => ({ ok: true, json: async () => ({ output_text: badOutput ? '{broken' : JSON.stringify(sections) }) }));
  return calls;
}

test('08:00 with previous-day domestic quotes generates, saves 08 and legacy fields', async t => {
  const calls = mockSources(t);
  const db = fakeDb();
  await runAiBriefGeneration('test-key', '08', { db, now });
  assert.equal(db.commits, 1);
  assert.equal(db.writes.length, 2);
  const value = db.writes[0].payload;
  assert.equal(value.slot, '08');
  assert.equal(value.slotLabel, '08:00');
  assert.equal(value.isMarketClosed, undefined);
  assert.ok(value.brief && value.sections.index);
  assert.ok(db.writes[1].payload['08']);
  assert.equal(calls.some(url => url.includes('marketValue') || url.includes('sise_group')), false);
});

test('morning survives domestic outage; preview makes no writes', async t => {
  mockSources(t, { domesticFailure: true });
  const db = fakeDb();
  const value = await runAiBriefGeneration('test-key', '08', { db, now, dryRun: true });
  assert.equal(value.kospi, null);
  assert.equal(value.briefingType, 'morning');
  assert.equal(db.commits, 0);
  assert.equal(db.writes.length, 0);
});

test('all source failure preserves last briefing', async t => {
  mockSources(t, { allFailure: true });
  const db = fakeDb();
  await assert.rejects(runAiBriefGeneration('test-key', '08', { db, now }), /모두 수집 실패/);
  assert.equal(db.writes.length, 0);
});

test('invalid AI JSON never overwrites last briefing', async t => {
  mockSources(t, { badOutput: true });
  const db = fakeDb();
  await assert.rejects(runAiBriefGeneration('test-key', '08', { db, now }), /JSON 파싱 실패/);
  assert.equal(db.writes.length, 0);
});

test('stale macro quotes are dropped and calendar outage stays distinguishable', async () => {
  const context = await fetchMorningContext({ collection: () => ({ where: () => ({ get: async () => { throw new Error('offline'); } }) }) }, now,
    async () => ({ data: { chart: { result: [{ meta: { regularMarketPrice: 5, regularMarketTime: 1 } }] } } }));
  assert.deepEqual(context.macro, []);
  assert.equal(context.calendarAvailable, false);
});

test('US daily chart ignores an unfinished session but includes it after close', async t => {
  t.mock.method(axios, 'get', async () => ({ data: { chart: { result: [{
    timestamp: ['2026-09-11T13:30:00Z', '2026-09-14T13:30:00Z', '2026-09-15T13:30:00Z'].map(s => +new Date(s) / 1000),
    indicators: { quote: [{ close: [100, 101, 99] }] },
  }] } } }));
  const during = await fetchUsMarketData(new Date('2026-09-15T17:00:00Z'));
  assert.equal(during.latestDate, '2026-09-14');
  assert.equal(during.indices[0].close, 101);
  const after = await fetchUsMarketData(now);
  assert.equal(after.latestDate, '2026-09-15');
  assert.equal(after.indices[0].close, 99);
});

test('morning news headlines and sources come from collected articles, not AI inventions', async t => {
  t.mock.method(global, 'fetch', async () => ({ ok: true, json: async () => ({ output_text: JSON.stringify({
    ...sections, news: [{ sourceIndex: 1, headline: 'invented price', detail: '설명입니다.' }, { sourceIndex: 99, headline: 'fake', detail: 'fake' }],
  }) }) }));
  const source = { title: '실제 기사 제목', source: '신문', url: 'https://example.com/news', pubDate: now.toISOString() };
  const result = await generateBriefWithOpenAi('test-key', null, null, null, null, [source], null, null, '08', {}, now);
  assert.equal(result.sections.news.length, 1);
  assert.equal(result.sections.news[0].headline, source.title);
  assert.equal(result.sections.news[0].url, source.url);
});
