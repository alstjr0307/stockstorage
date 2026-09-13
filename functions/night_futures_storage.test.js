const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(`${__dirname}/index.js`, 'utf8');
const start = source.indexOf('async function recordNightFuturesTo(');
const end = source.indexOf('// ── 야간선물 가격', start);
assert.ok(start >= 0 && end > start);
const context = vm.createContext({ Date, Math });
vm.runInContext(source.slice(start, end), context);

for (const count of [100, 2001, 2300]) {
  test(`one quote write, bounded cleanup with ${count} documents`, async () => {
    let writes = 0;
    let queried = 0;
    let deleted = 0;
    const quote = { price: 1400, change: -1, changeRate: -0.1, volume: 10,
      timestamp: new Date('2026-09-10T15:03:08Z') };
    const collection = {
      doc: key => ({ set: async data => {
        assert.equal(key, '2026-09-11_00:03');
        assert.equal(data.timestamp, quote.timestamp);
        writes++;
      } }),
      count: () => ({ get: async () => ({ data: () => ({ count }) }) }),
      orderBy: (field, direction) => {
        assert.equal(field, 'timestamp');
        assert.equal(direction, 'asc');
        return { limit: limit => ({ get: async () => {
          queried = limit;
          return { empty: false, docs: Array.from({length: limit}, () => ({ref: {}})) };
        } }) };
      },
    };
    const db = { collection: () => collection, batch: () => ({
      delete: () => deleted++, commit: async () => {},
    }) };
    await context.recordNightFuturesTo(db, 'prices', 'A06612', quote);
    assert.equal(writes, 1);
    assert.equal(queried, Math.min(Math.max(count - 2000, 0), 100));
    assert.equal(deleted, queried);
  });
}
