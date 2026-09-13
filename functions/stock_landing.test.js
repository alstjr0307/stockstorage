'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseStockPath, loadPublicSnapshot, renderStockLanding, createStockLandingHandler } = require('./stock_landing');
const stock = { market: 'KS', ticker: '005930' };

test('valid domestic and class-share URLs; reject malformed paths', () => {
  assert.deepEqual(parseStockPath('/stock/KS/005930'), stock);
  assert.equal(parseStockPath('/stock/US/BRK.B').ticker, 'BRK.B');
  for (const path of ['/stock/KS/5930', '/stock/XX/AAPL', '/users/private', '/stock/US/<script>', '/stock/US/AAPL/more']) assert.equal(parseStockPath(path), null);
});
test('HTML escapes public content and malicious display hints including script tags', () => {
  const html = renderStockLanding(stock, { name: '</title><script>alert(1)</script>', reason: '<img onerror="x">' });
  assert(!html.includes('<script>alert(1)</script>'));
  assert(!html.includes('<img onerror='));
  assert(html.includes('&lt;img'));
  const hintHtml = renderStockLanding(stock, null, '</script><script>alert(2)</script>');
  assert(!hintHtml.includes('<script>alert(2)</script>'));
});
test('server-rendered dated summary and web CTA preserve stock identity', () => {
  const html = renderStockLanding(stock, { name: '삼성전자', reason: '공개 요약', price: 123, sourceDate: { toMillis: () => Date.UTC(2026, 8, 10) } });
  assert(html.includes('공개 요약'));
  assert(html.includes('실시간 시세가 아닙니다'));
  assert(html.includes('market=KS&amp;ticker=005930'));
  assert(html.includes('<link rel="canonical" href="https://stockstorage-13828.web.app/stock/KS/005930">'));
});
test('missing public data gets a usable fallback, not invented price or analysis', () => {
  const html = renderStockLanding(stock, null, '삼성전자');
  assert(html.includes('공개 요약이 아직 없는 종목'));
  assert(html.includes('noindex,follow'));
  assert(!html.includes('class="price"'));
  assert(html.includes('이 종목 확인하고 저장하기'));
});
test('snapshot lookup only reads public collection and filters other markets', async () => {
  const query = { where() { return this; }, select() { return this; }, limit(n) { assert.equal(n, 20); return this; },
    async get() { return { docs: [{ data: () => ({ market: 'US', name: 'Wrong' }) }, { data: () => ({ market: 'KS', name: '삼성전자' }) }] }; } };
  const db = { collection(name) { assert.equal(name, 'market_feature_stocks'); return query; } };
  assert.equal((await loadPublicSnapshot(db, stock)).name, '삼성전자');
});
test('invalid requests never reach Firestore', async () => {
  const handler = createStockLandingHandler({ collection() { throw Error('unexpected read'); } });
  const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, set() { return this; }, send() { return this; } };
  await handler({ method: 'GET', path: '/stock/KS/nope' }, res);
  assert.equal(res.statusCode, 404);
  await handler({ method: 'POST', path: '/stock/KS/005930' }, res);
  assert.equal(res.statusCode, 405);
});
