const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// 실제 수집 코드의 순수 월물 선택 로직만 실행한다 (Firebase 초기화 없음).
const source = fs.readFileSync(`${__dirname}/index.js`, 'utf8');
const start = source.indexOf('function getSecondThursday(');
const end = source.indexOf('// KIS 실시간 WebSocket 승인키', start);
assert.ok(start >= 0 && end > start);
const context = vm.createContext({ Date });
vm.runInContext(source.slice(start, end), context);

for (const [time, suffix] of [
  ['2026-09-09T18:00:00+09:00', '609'],
  ['2026-09-10T04:59:00+09:00', '609'],
  ['2026-09-10T17:59:59+09:00', '609'],
  ['2026-09-10T18:00:00+09:00', '612'],
  ['2026-09-11T00:00:00+09:00', '612'],
  ['2026-12-10T04:00:00+09:00', '612'],
  ['2026-12-10T18:00:00+09:00', '703'],
]) {
  test(`night futures contract at ${time}`, () => {
    for (const prefix of ['A01', 'A06']) {
      assert.equal(context.getNightFuturesSymbol(prefix, new Date(time)), `${prefix}${suffix}`);
    }
  });
}
