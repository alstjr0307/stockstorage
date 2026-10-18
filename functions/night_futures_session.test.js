const { test } = require('node:test');
const assert = require('node:assert/strict');
const { isNightFuturesSession } = require('./night_futures_session');

for (const [time, expected] of [
  ['2026-09-18T17:59:59+09:00', false],
  ['2026-09-18T18:00:00+09:00', true],
  ['2026-09-19T00:00:00+09:00', true],
  ['2026-09-19T04:59:59+09:00', true],
  ['2026-09-19T05:00:00+09:00', false],
  ['2026-09-19T18:00:00+09:00', false],
  ['2026-09-20T04:00:00+09:00', false],
  ['2026-09-20T18:00:00+09:00', false],
  ['2026-09-21T04:00:00+09:00', false],
  ['2026-09-21T18:00:00+09:00', true],
  ['2026-09-22T04:59:59+09:00', true],
  ['2026-09-22T05:00:00+09:00', false],
]) {
  test(`session gate at ${time}`, () => {
    assert.equal(isNightFuturesSession(new Date(time)), expected);
  });
}
