'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseMaster, validateQuote, calculate, collect } = require('./kospi200_maxpain');
const AdmZip = require('adm-zip');
const line = (kind, code, name, strike, underlying = '2001') =>
  [kind, code, 'standard', name, '1', strike, '', underlying, 'KOSPI200'].join('|');
const master = [line('5', 'C1', 'C 202611 100.0', 100), line('6', 'P1', 'P 202611 100.0', 100)].join('\n');
const payload = (side, strike, oi, date = '20261112') => ({ rt_cd: '0', output1: {
  hts_kor_isnm: `${side} ${date.slice(0, 6)} ${strike}`, acpr: String(strike),
  hts_otst_stpl_qty: oi, futs_last_tr_date: date },
  output3: { bstp_cls_code: '2001', bstp_nmix_prpr: '102' } });
const contracts = [90, 100, 110].flatMap(strike => ['call', 'put'].map(side => ({ code: side + strike, side, strike })));
const quotes = contracts.map(c => ({ ...c, oi: c.side === 'call' ? ({90: 10, 100: 20, 110: 30})[c.strike] : ({90: 30, 100: 20, 110: 10})[c.strike], expiryDate: '20261112', spot: 102 }));

test('master excludes mini/weekly and other underlyings; rejects partial pairs', () => {
  const text = master + '\n' + line('L', 'WEEKLY', 'C 202611 100', 100) + '\n' + line('5', 'OTHER', 'C 202611 100', 100, '2002');
  assert.equal(parseMaster(text, new Date('2026-10-16'))[0][1].length, 2);
  assert.throws(() => parseMaster(master.split('\n')[0], new Date('2026-10-16')), /UNPAIRED/);
  assert.throws(() => parseMaster(master + '\n' + master, new Date('2026-10-16')), /DUPLICATE/);
});
test('missing OI is not silently converted to zero; mismatched contract fails', () => {
  const c = contracts[0];
  assert.equal(validateQuote(c, payload('C', 90, '0'), '202611').oi, 0);
  for (const oi of [undefined, '', '-1', 'NaN', '2.5']) {
    assert.throws(() => validateQuote(c, payload('C', 90, oi), '202611'));
  }
  assert.throws(() => validateQuote(c, payload('P', 90, '10'), '202611'));
  assert.throws(() => validateQuote(c, payload('C', 100, '10'), '202611'));
  assert.throws(() => validateQuote(c, payload('C', 90, '10', '20261210'), '202611'));
});
test('full chain gives the independently known minimum payout at 100', () => {
  const d = calculate(contracts, quotes, '202611');
  // At 90/100/110, total intrinsic payouts are 400/200/400.
  assert.equal(d.maxPain, 100);
  assert.equal(d.totalCallOi, 60);
  assert.equal(d.totalPutOi, 60);
  assert.equal(d.fetchedContracts, 6);
  assert.equal(d.expiryDate, '2026-11-12');
});
test('incomplete/duplicate chain and missing spot coverage are rejected', () => {
  assert.throws(() => calculate(contracts, quotes.slice(1), '202611'), /INCOMPLETE/);
  assert.throws(() => calculate(contracts, [...quotes.slice(1), quotes[1]], '202611'), /INCOMPLETE/);
  assert.throws(() => calculate(contracts, quotes.map(q => ({ ...q, spot: 80 })), '202611'), /OUTSIDE/);
});
test('flat minimum retains the interval and selects nearest listed strike', () => {
  const qs = quotes.map(q => ({ ...q, oi: (q.strike === 90 && q.side === 'call') || (q.strike === 110 && q.side === 'put') ? 10 : 0 }));
  const d = calculate(contracts, qs, '202611');
  assert.deepEqual(d.maxPainRange, [90, 110]);
  assert.equal(d.maxPain, 100);
});
test('collector queries every master contract, including beyond the 100-row limit', async () => {
  const lines = [], expected = new Map();
  for (let i = 0; i < 105; i++) {
    for (const [kind, side] of [['5', 'C'], ['6', 'P']]) {
      const code = side + i, strike = 50 + i;
      lines.push(line(kind, code, `${side} 202611 ${strike}`, strike));
      expected.set(code, payload(side, strike, '10'));
    }
  }
  const zip = new AdmZip(); zip.addFile('fo_idx_code_mts.mst', Buffer.from(lines.join('\n')));
  const seen = [];
  const axios = { get: async (url, options) => {
    if (url.endsWith('.zip')) return { data: zip.toBuffer() };
    const code = options.params.FID_INPUT_ISCD; seen.push(code); return { data: expected.get(code) };
  } };
  const d = await collect({ axios, AdmZip, now: () => new Date('2026-10-16T01:00:00Z'), sleep: async () => {} });
  assert.equal(d.fetchedContracts, 210); assert.equal(new Set(seen).size, 210);
  assert.equal(d.strikes.length, 105);
});
