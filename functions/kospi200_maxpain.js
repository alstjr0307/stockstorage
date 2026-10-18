'use strict';

// The display-board endpoint truncates each side at 100 rows. Never use it
// to compute market-wide max pain. Enumerate the official contract master.
const MASTER_URL = 'https://new.real.download.dws.co.kr/common/master/fo_idx_code_mts.mst.zip';
const QUOTE_URL = 'https://openapi.koreainvestment.com:9443/uapi/domestic-futureoption/v1/quotations/inquire-price';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

function parseMaster(text, now = new Date()) {
  const kst = new Date(now.getTime() + 9 * 3600000);
  const month = kst.toISOString().slice(0, 7).replace('-', '');
  const groups = new Map();
  for (const line of text.split(/\r?\n/)) {
    const f = line.split('|').map(s => s.trim());
    if (!['5', '6'].includes(f[0]) || f[7] !== '2001') continue;
    const match = /^[CP]\s+(\d{6})\s/.exec(f[3]);
    if (!match || match[1] < month) continue;
    const expiry = match[1], strike = Number(f[5]);
    if (!f[1] || !Number.isFinite(strike) || strike <= 0) throw Error('INVALID_MASTER');
    if (!groups.has(expiry)) groups.set(expiry, []);
    groups.get(expiry).push({ code: f[1], side: f[0] === '5' ? 'call' : 'put', strike });
  }
  if (!groups.size) throw Error('EMPTY_MASTER');
  for (const contracts of groups.values()) {
    const codes = new Set(), sides = new Set();
    for (const c of contracts) {
      if (codes.has(c.code) || sides.has(`${c.side}:${c.strike}`)) throw Error('DUPLICATE_MASTER');
      codes.add(c.code); sides.add(`${c.side}:${c.strike}`);
    }
    for (const c of contracts) {
      if (!sides.has(`${c.side === 'call' ? 'put' : 'call'}:${c.strike}`)) throw Error('UNPAIRED_MASTER');
    }
  }
  return [...groups].sort(([a], [b]) => a.localeCompare(b));
}

function validateQuote(contract, data, expiry) {
  const q = data?.output1;
  const oiRaw = q?.hts_otst_stpl_qty;
  const oi = Number(oiRaw), strike = Number(q?.acpr);
  const date = String(q?.futs_last_tr_date || '');
  const name = String(q?.hts_kor_isnm || '').trim();
  const side = contract.side === 'call' ? 'C' : 'P';
  if (data?.rt_cd !== '0' || !name.startsWith(`${side} ${expiry}`) ||
      !/^\d{8}$/.test(date) || !date.startsWith(expiry) ||
      strike !== contract.strike || oiRaw == null || String(oiRaw).trim() === '' ||
      !Number.isSafeInteger(oi) || oi < 0) throw Error('INVALID_CONTRACT_QUOTE');
  const spot = Number(data.output3?.bstp_nmix_prpr);
  if (String(data.output3?.bstp_cls_code) !== '2001' || !Number.isFinite(spot) || spot <= 0) {
    throw Error('INVALID_UNDERLYING');
  }
  return { ...contract, oi, expiryDate: date, spot };
}

function calculate(contracts, quotes, expiry) {
  if (!contracts.length || quotes.length !== contracts.length) throw Error('INCOMPLETE_CHAIN');
  const byCode = new Map(quotes.map(q => [q.code, q]));
  if (byCode.size !== contracts.length) throw Error('INCOMPLETE_CHAIN');
  const map = new Map();
  let expiryDate;
  for (const c of contracts) {
    const q = byCode.get(c.code);
    if (!q || q.strike !== c.strike || q.side !== c.side || !Number.isSafeInteger(q.oi) || q.oi < 0) throw Error('INCOMPLETE_CHAIN');
    if (expiryDate && expiryDate !== q.expiryDate) throw Error('MIXED_EXPIRY');
    expiryDate = q.expiryDate;
    if (!map.has(c.strike)) map.set(c.strike, { strike: c.strike, callOi: 0, putOi: 0 });
    map.get(c.strike)[c.side === 'call' ? 'callOi' : 'putOi'] = q.oi;
  }
  const strikes = [...map.values()].sort((a, b) => a.strike - b.strike);
  const totalCallOi = strikes.reduce((n, s) => n + s.callOi, 0);
  const totalPutOi = strikes.reduce((n, s) => n + s.putOi, 0);
  if (!totalCallOi || !totalPutOi) throw Error('EMPTY_OPEN_INTEREST');
  const currentLevel = quotes.at(-1).spot;
  if (!(strikes[0].strike < currentLevel && currentLevel < strikes.at(-1).strike)) throw Error('UNDERLYING_OUTSIDE_CHAIN');
  const pains = strikes.map(({ strike: s }) => strikes.reduce((n, k) =>
    n + k.callOi * Math.max(s - k.strike, 0) + k.putOi * Math.max(k.strike - s, 0), 0));
  const minimum = Math.min(...pains);
  const minima = strikes.filter((_, i) => Math.abs(pains[i] - minimum) < 1e-7).map(s => s.strike);
  // Preserve an actual listed strike as the displayed value; retain ties.
  const maxPain = minima.reduce((a, b) => Math.abs(b - currentLevel) < Math.abs(a - currentLevel) ? b : a);
  return { status: 'valid', source: 'KIS_MASTER_AND_CONTRACT_QUOTES', coverage: 'complete', expiry,
    expiryDate: `${expiryDate.slice(0, 4)}-${expiryDate.slice(4, 6)}-${expiryDate.slice(6, 8)}`,
    maxPain, maxPainRange: [minima[0], minima.at(-1)], atmStrike: null, currentLevel,
    totalCallOi, totalPutOi, putCallRatio: totalPutOi / totalCallOi, strikes,
    expectedContracts: contracts.length, fetchedContracts: quotes.length };
}

async function collect({ axios, AdmZip, appKey, appSecret, token, now = () => new Date(), sleep = pause }) {
  const startedAt = now();
  const response = await axios.get(MASTER_URL, { responseType: 'arraybuffer', timeout: 20000 });
  const zip = new AdmZip(Buffer.from(response.data));
  const entry = zip.getEntries().find(e => e.entryName === 'fo_idx_code_mts.mst');
  if (!entry) throw Error('MASTER_FILE_MISSING');
  const groups = parseMaster(new TextDecoder('euc-kr').decode(entry.getData()), startedAt);
  const headers = { authorization: `Bearer ${token}`, appkey: appKey, appsecret: appSecret,
    tr_id: 'FHMIF10000000', custtype: 'P' };
  const get = async (c, expiry) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const res = await axios.get(QUOTE_URL, { headers, timeout: 10000,
          params: { FID_COND_MRKT_DIV_CODE: 'O', FID_INPUT_ISCD: c.code } });
        return validateQuote(c, res.data, expiry);
      } catch (_) {
        if (attempt === 2) throw Error('CONTRACT_FETCH_FAILED');
        await sleep(1500 * (attempt + 1));
      }
    }
  };
  for (const [expiry, contracts] of groups) {
    const first = await get(contracts[0], expiry);
    // Actual exchange last-trade date handles holiday-shifted expirations.
    const kst = new Date(now().getTime() + 9 * 3600000);
    const today = kst.toISOString().slice(0, 10).replace(/-/g, '');
    const expired = first.expiryDate < today || (first.expiryDate === today &&
      kst.getUTCHours() * 60 + kst.getUTCMinutes() >= 15 * 60 + 20);
    if (expired) continue;
    const quotes = [first];
    // Five quotes per batch; reserve API capacity for other scheduled jobs.
    for (let i = 1; i < contracts.length; i += 5) {
      if (now().getTime() - startedAt.getTime() > 450000) throw Error('COLLECTION_DEADLINE');
      await sleep(1000);
      const batch = await Promise.allSettled(contracts.slice(i, i + 5).map(c => get(c, expiry)));
      if (batch.some(r => r.status === 'rejected')) throw Error('INCOMPLETE_CHAIN');
      quotes.push(...batch.map(r => r.value));
    }
    const finishedAt = now();
    const finishKst = new Date(finishedAt.getTime() + 9 * 3600000);
    if (first.expiryDate === finishKst.toISOString().slice(0, 10).replace(/-/g, '') &&
        finishKst.getUTCHours() * 60 + finishKst.getUTCMinutes() >= 920) throw Error('EXPIRED_DURING_COLLECTION');
    return { ...calculate(contracts, quotes, expiry), collectionStartedAt: startedAt, updatedAt: finishedAt };
  }
  throw Error('NO_ACTIVE_MONTH');
}

module.exports = { parseMaster, validateQuote, calculate, collect };
