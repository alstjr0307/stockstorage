const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createRevenueHandler, parseReport, period, APP_IDS, ACCOUNT} = require('./admob_revenue');
const admin = {uid: '1KzEXKZMoFaYOymYyoI283AR3Y32'};
const token = 'test-access-token-never-log';
const now = new Date('2026-10-15T15:01:00Z');
const account = {name: ACCOUNT, currencyCode: 'USD', reportingTimeZone: 'Asia/Seoul'};
function row(date, app, earnings, impressions = 1000) {
  return {row: {dimensionValues: {DATE: {value: date}, APP: {value: app}}, metricValues: {
    ESTIMATED_EARNINGS: {microsValue: String(earnings)}, IMPRESSIONS: {integerValue: String(impressions)},
    CLICKS: {integerValue: '5'}, AD_REQUESTS: {integerValue: '2000'},
  }}};
}
function report(rows = []) {
  return [{header: {localizationSettings: {currencyCode: 'USD'}}}, ...rows, {footer: {matchingRowCount: rows.length}}];
}
test('account timezone and new year include yesterday and seven days', () => {
  assert.equal(period(now, 'Asia/Seoul').today, '20261016');
  assert.equal(period(now, 'America/Los_Angeles').today, '20261015');
  const dates = period(new Date('2026-12-31T15:00:00Z'), 'Asia/Seoul');
  assert.equal(dates.today, '20270101');
  assert.equal(dates.start, '20261226');
  assert.equal(dates.yesterday, '20261231');
});
test('micros, both apps, zero fill and weighted eCPM', () => {
  const result = parseReport(report([
    row('20261016', APP_IDS[0], 1500000, 500), row('20261016', APP_IDS[1], 2500000, 1500),
    row('20261015', APP_IDS[0], 1000000), row('20261001', APP_IDS[0], 2000000),
  ]), account, period(now, account.reportingTimeZone), now);
  assert.equal(result.today.earnings, 4);
  assert.equal(result.today.ecpm, 2);
  assert.equal(result.yesterday.earnings, 1);
  assert.equal(result.month.earnings, 7);
  assert.equal(result.week.length, 7);
  assert.equal(result.week[2].earnings, 0);
});
test('valid empty report is zero; incomplete or unrelated data is rejected', () => {
  const parse = data => parseReport(data, account, period(now, account.reportingTimeZone), now);
  assert.equal(parse(report()).today.earnings, 0);
  assert.throws(() => parse([]));
  const truncated = report(); truncated.at(-1).footer.matchingRowCount = 1;
  assert.throws(() => parse(truncated));
  const warning = report(); warning.at(-1).footer.warnings = [{type: 'WARNING'}];
  assert.throws(() => parse(warning));
  assert.throws(() => parse(report([row('20261016', 'another-app', 1000)])));
});
test('auth before cache, fixed app filters, cache expiry and token confidentiality', async () => {
  let calls = 0;
  let current = now;
  const handler = createRevenueHandler({clock: () => current, http: {
    get: async (url, config) => { calls++; assert.equal(config.headers.Authorization, `Bearer ${token}`); return {data: account}; },
    post: async (url, body) => {
      assert.ok(url.endsWith('/networkReport:generate'));
      assert.deepEqual(body.reportSpec.dimensionFilters[0].matchesAny.values, APP_IDS);
      assert.equal(body.reportSpec.timeZone, undefined);
      return {data: report()};
    },
  }});
  await assert.rejects(handler({data: {accessToken: token}}), e => e.code === 'unauthenticated');
  await assert.rejects(handler({auth: {uid: 'ordinary'}, data: {accessToken: token}}), e => e.code === 'permission-denied');
  await assert.rejects(handler({auth: admin, data: {}}), e => e.details.reason === 'connect-required');
  const result = await handler({auth: admin, data: {accessToken: token}});
  assert.equal(JSON.stringify(result).includes(token), false);
  assert.equal((await handler({auth: admin, data: {}})).cached, true);
  await assert.rejects(handler({auth: {uid: 'ordinary'}, data: {}}), e => e.code === 'permission-denied');
  assert.equal(calls, 1);
  current = new Date(now.getTime() + 301000);
  await assert.rejects(handler({auth: admin, data: {}}), e => e.details.reason === 'connect-required');
});
test('cache cannot cross account midnight', async () => {
  let current = new Date('2026-10-15T14:59:59Z');
  const handler = createRevenueHandler({clock: () => current, http: {
    get: async () => ({data: account}), post: async () => ({data: report()}),
  }});
  await handler({auth: admin, data: {accessToken: token}});
  current = new Date('2026-10-15T15:00:00Z');
  await assert.rejects(handler({auth: admin, data: {}}), e => e.details.reason === 'connect-required');
});
test('upstream errors never expose OAuth credentials', async () => {
  for (const status of [401, 403, 429, 500]) {
    const handler = createRevenueHandler({http: {get: async () => {
      throw {message: token, config: {headers: {Authorization: token}}, response: {status}};
    }}});
    await assert.rejects(handler({auth: admin, data: {accessToken: token}}), e => {
      assert.equal(JSON.stringify(e).includes(token), false);
      return ['failed-precondition', 'resource-exhausted', 'unavailable'].includes(e.code);
    });
  }
});
