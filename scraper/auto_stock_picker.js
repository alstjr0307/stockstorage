const fs = require('fs');
const path = require('path');
const https = require('https');
const iconv = require('iconv-lite');
const admin = require('firebase-admin');

const KRX_LIST_URL =
  'https://kind.krx.co.kr/corpgeneral/corpList.do?method=download&searchType=13';

function numberEnv(name, fallback) {
  const raw = process.env[name];
  if (raw == null || raw === '') return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

const LOOKBACK_DAYS = numberEnv('LOOKBACK_DAYS', 260);
const MIN_HISTORY_DAYS = numberEnv('MIN_HISTORY_DAYS', 120);
const MAX_STOCKS = numberEnv('MAX_STOCKS', 0);
const MAX_PICKS = numberEnv('MAX_PICKS', 8);
const CONCURRENCY = numberEnv('CONCURRENCY', 5);
const MIN_SCORE = numberEnv('MIN_SCORE', 65);
const MIN_AVG_TRADING_VALUE = numberEnv('MIN_AVG_TRADING_VALUE', 1000000000);
const MIN_PRICE = numberEnv('MIN_PRICE', 1000);
const TARGET_RETURN_RATE = numberEnv('TARGET_RETURN_RATE', 0.12);
const MAX_DISTANCE_FROM_MA20 = numberEnv('MAX_DISTANCE_FROM_MA20', 0.18);
const MAX_20D_RETURN = numberEnv('MAX_20D_RETURN', 0.35);
const MAX_5D_RETURN = numberEnv('MAX_5D_RETURN', 0.18);
const REQUIRE_PATTERN = String(process.env.REQUIRE_PATTERN || '').trim();
const CUP_MIN_DEPTH = numberEnv('CUP_MIN_DEPTH', 0.12);
const CUP_MAX_DEPTH = numberEnv('CUP_MAX_DEPTH', 0.35);
const HANDLE_MIN_DAYS = numberEnv('HANDLE_MIN_DAYS', 5);
const HANDLE_MAX_DAYS = numberEnv('HANDLE_MAX_DAYS', 25);
const CUP_MIN_DAYS = numberEnv('CUP_MIN_DAYS', 45);
const CUP_MAX_DAYS = numberEnv('CUP_MAX_DAYS', 180);
const SURGE_LOOKBACK_DAYS = numberEnv('SURGE_LOOKBACK_DAYS', 20);
const SURGE_MIN_GAIN = numberEnv('SURGE_MIN_GAIN', 0.04);
const SURGE_MIN_VOLUME_RATIO = numberEnv('SURGE_MIN_VOLUME_RATIO', 1.8);
const PULLBACK_MIN = numberEnv('PULLBACK_MIN', 0.1);
const PULLBACK_MAX = numberEnv('PULLBACK_MAX', 0.18);
const PULLBACK_TARGET = numberEnv('PULLBACK_TARGET', 0.12);
const PULLBACK_TOLERANCE = numberEnv('PULLBACK_TOLERANCE', 0.03);
const LOWER_TAIL_MIN_RATIO = numberEnv('LOWER_TAIL_MIN_RATIO', 0.35);
const LOWER_TAIL_MIN_CLOSE_POSITION = numberEnv('LOWER_TAIL_MIN_CLOSE_POSITION', 0.35);
const LOWER_TAIL_MAX_BODY_RATIO = numberEnv('LOWER_TAIL_MAX_BODY_RATIO', 0.8);
const LOWER_TAIL_MIN_COUNT = numberEnv('LOWER_TAIL_MIN_COUNT', 3);
const U_BASE_MIN_DAYS = numberEnv('U_BASE_MIN_DAYS', 5);
const U_BASE_ZONE_PCT = numberEnv('U_BASE_ZONE_PCT', 0.08);
const LOWER_TAIL_WINDOW_DAYS = numberEnv('LOWER_TAIL_WINDOW_DAYS', 14);
const MIN_DROP_DAYS_AFTER_SURGE = numberEnv('MIN_DROP_DAYS_AFTER_SURGE', 3);
const MIN_BOUNCE_FROM_PULLBACK_LOW = numberEnv('MIN_BOUNCE_FROM_PULLBACK_LOW', 0.015);
const MAX_BOUNCE_FROM_PULLBACK_LOW = numberEnv('MAX_BOUNCE_FROM_PULLBACK_LOW', 0.12);
const GOLDEN_MIN_VOLUME_RATIO = numberEnv('GOLDEN_MIN_VOLUME_RATIO', 1.5);
const GOLDEN_MAX_VOLUME_RATIO = numberEnv('GOLDEN_MAX_VOLUME_RATIO', 10);
const GOLDEN_MAX_DISTANCE_FROM_MA20 = numberEnv('GOLDEN_MAX_DISTANCE_FROM_MA20', 0.12);
const GOLDEN_MAX_5D_RETURN = numberEnv('GOLDEN_MAX_5D_RETURN', 0.12);
const GOLDEN_MAX_20D_RETURN = numberEnv('GOLDEN_MAX_20D_RETURN', 0.25);
const GOLDEN_BREAKOUT_BAND = numberEnv('GOLDEN_BREAKOUT_BAND', 0.06);
const MAX_CALENDAR_GAP_DAYS = numberEnv('MAX_CALENDAR_GAP_DAYS', 7);
const MAX_OPEN_GAP = numberEnv('MAX_OPEN_GAP', 0.12);
const MA_CLUSTER_MAX_SPREAD = numberEnv('MA_CLUSTER_MAX_SPREAD', 0.07);
const MA_TOUCH_LOOKBACK_DAYS = numberEnv('MA_TOUCH_LOOKBACK_DAYS', 7);
const MA_TOUCH_BAND = numberEnv('MA_TOUCH_BAND', 0.02);
const MA_CLUSTER_MAX_DISTANCE = numberEnv('MA_CLUSTER_MAX_DISTANCE', 0.06);
const MA_REQUIRE_120_TOUCH = String(process.env.MA_REQUIRE_120_TOUCH || '1') !== '0';
const MA_MIN_REBOUND_VOLUME_RATIO = numberEnv('MA_MIN_REBOUND_VOLUME_RATIO', 1.2);
const MA_NO_120_BREAK_LOOKBACK = numberEnv('MA_NO_120_BREAK_LOOKBACK', 60);
const MA120_MIN_SLOPE = numberEnv('MA120_MIN_SLOPE', 0.005);
const RECLAIM_LOOKBACK_DAYS = numberEnv('RECLAIM_LOOKBACK_DAYS', 45);
const RECLAIM_MIN_UNDERCUT = numberEnv('RECLAIM_MIN_UNDERCUT', 0.01);
const RECLAIM_MAX_UNDERCUT = numberEnv('RECLAIM_MAX_UNDERCUT', 0.08);
const RECLAIM_MAX_DAYS = numberEnv('RECLAIM_MAX_DAYS', 5);
const RECLAIM_MAX_MA_SPREAD = numberEnv('RECLAIM_MAX_MA_SPREAD', 0.1);
const RECLAIM_MIN_VOLUME_RATIO = numberEnv('RECLAIM_MIN_VOLUME_RATIO', 1.5);
const RECLAIM_MIN_MA120_SLOPE = numberEnv('RECLAIM_MIN_MA120_SLOPE', 0.01);
const RECLAIM_MIN_MA60_SLOPE = numberEnv('RECLAIM_MIN_MA60_SLOPE', -0.005);
const CLUSTER_BREAKOUT_MAX_MA_SPREAD = numberEnv('CLUSTER_BREAKOUT_MAX_MA_SPREAD', 0.08);
const CLUSTER_BREAKOUT_MIN_VOLUME_RATIO = numberEnv('CLUSTER_BREAKOUT_MIN_VOLUME_RATIO', 2);
const CLUSTER_BREAKOUT_MIN_GAIN = numberEnv('CLUSTER_BREAKOUT_MIN_GAIN', 0.07);
const CLUSTER_BREAKOUT_MAX_DISTANCE = numberEnv('CLUSTER_BREAKOUT_MAX_DISTANCE', 0.25);
const DRYUP_LOOKBACK_DAYS = numberEnv('DRYUP_LOOKBACK_DAYS', 15);
const DRYUP_MIN_SURGE_GAIN = numberEnv('DRYUP_MIN_SURGE_GAIN', 0.04);
const DRYUP_MIN_SURGE_VOLUME_RATIO = numberEnv('DRYUP_MIN_SURGE_VOLUME_RATIO', 1.8);
const DRYUP_MIN_SURGE_TRADING_VALUE = numberEnv('DRYUP_MIN_SURGE_TRADING_VALUE', 5000000000);
const DRYUP_MAX_PULLBACK = numberEnv('DRYUP_MAX_PULLBACK', 0.06);
const DRYUP_MAX_RUNUP = numberEnv('DRYUP_MAX_RUNUP', 0.3);
const DRYUP_MAX_POST_AVG_VOLUME_RATIO = numberEnv('DRYUP_MAX_POST_AVG_VOLUME_RATIO', 0.7);
const DRYUP_MAX_RECENT_VOLUME_RATIO = numberEnv('DRYUP_MAX_RECENT_VOLUME_RATIO', 0.5);
const DRYUP_RISE_MIN_MA20_DISTANCE = numberEnv('DRYUP_RISE_MIN_MA20_DISTANCE', 0.03);
const DRYUP_RISE_MAX_MA20_DISTANCE = numberEnv('DRYUP_RISE_MAX_MA20_DISTANCE', 0.22);
const DRYUP_RISE_MIN_MA60_DISTANCE = numberEnv('DRYUP_RISE_MIN_MA60_DISTANCE', 0);
const DRYUP_RISE_MAX_MA60_DISTANCE = numberEnv('DRYUP_RISE_MAX_MA60_DISTANCE', 0.4);
const DRYUP_SUPPORT_MIN_PULLBACK = numberEnv('DRYUP_SUPPORT_MIN_PULLBACK', 0.05);
const DRYUP_SUPPORT_MAX_PULLBACK = numberEnv('DRYUP_SUPPORT_MAX_PULLBACK', 0.15);
const DRYUP_SUPPORT_MIN_MA20_DISTANCE = numberEnv('DRYUP_SUPPORT_MIN_MA20_DISTANCE', -0.03);
const DRYUP_SUPPORT_MAX_MA20_DISTANCE = numberEnv('DRYUP_SUPPORT_MAX_MA20_DISTANCE', 0.14);
const DRYUP_SUPPORT_MIN_MA60_DISTANCE = numberEnv('DRYUP_SUPPORT_MIN_MA60_DISTANCE', -0.05);
const DRYUP_SUPPORT_MAX_MA60_DISTANCE = numberEnv('DRYUP_SUPPORT_MAX_MA60_DISTANCE', 0.3);
const SEND_FCM = String(process.env.SEND_FCM || '0') === '1';
const FCM_TOPIC = process.env.FCM_TOPIC || 'new_pick_alerts';
const DRY_RUN = String(process.env.DRY_RUN || '0') === '1';
const MARKET_FEATURES = String(process.env.MARKET_FEATURES || '0') === '1';
const FEATURE_GROUP = String(process.env.FEATURE_GROUP || '').trim();
const FEATURE_MAX_PER_GROUP = numberEnv('FEATURE_MAX_PER_GROUP', 20);
const FEATURE_MIN_TRADING_VALUE = numberEnv('FEATURE_MIN_TRADING_VALUE', 5000000000);
const FEATURE_VALUE_SPIKE_RATIO = numberEnv('FEATURE_VALUE_SPIKE_RATIO', 2.5);
const FEATURE_GAINER_MIN_RETURN = numberEnv('FEATURE_GAINER_MIN_RETURN', 0.07);
const FEATURE_VOLUME_SPIKE_MIN_RETURN = numberEnv('FEATURE_VOLUME_SPIKE_MIN_RETURN', 0.03);
const FEATURE_HIGH_BREAKOUT_MIN_RETURN = numberEnv('FEATURE_HIGH_BREAKOUT_MIN_RETURN', 0.03);
const FEATURE_COOLDOWN_DAYS = numberEnv('FEATURE_COOLDOWN_DAYS', 3);

function pad2(value) {
  return String(value).padStart(2, '0');
}

function formatYmd(date, sep = '') {
  return `${date.getFullYear()}${sep}${pad2(date.getMonth() + 1)}${sep}${pad2(date.getDate())}`;
}

function getKstNow() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date());

  const get = (type) => Number(parts.find((p) => p.type === type)?.value || 0);
  return new Date(
    get('year'),
    get('month') - 1,
    get('day'),
    get('hour'),
    get('minute'),
    get('second'),
  );
}

function resolveEndDate() {
  const raw = String(process.env.END_DATE || '').trim();
  if (!raw) return getKstNow();
  const match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) throw new Error('END_DATE must be YYYY-MM-DD.');
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 16, 0, 0);
}

function normalizeDateKey(value) {
  return String(value || '').replace(/[^0-9]/g, '');
}

function fetchBuffer(url, headers = {}) {
  return new Promise((resolve, reject) => {
    https
      .get(url, { headers }, (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          if (res.statusCode >= 400) {
            reject(new Error(`HTTP ${res.statusCode}: ${url}`));
            return;
          }
          resolve(Buffer.concat(chunks));
        });
      })
      .on('error', reject);
  });
}

function stripHtml(value) {
  return String(value || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseKrxRows(html) {
  const rows = [];
  const trRegex = /<tr[\s\S]*?>([\s\S]*?)<\/tr>/gi;
  let trMatch;
  while ((trMatch = trRegex.exec(html)) !== null) {
    const cells = [];
    const tdRegex = /<td[^>]*>([\s\S]*?)<\/td>/gi;
    let tdMatch;
    while ((tdMatch = tdRegex.exec(trMatch[1])) !== null) {
      cells.push(stripHtml(tdMatch[1]));
    }
    if (cells.length < 3) continue;

    const name = cells[0] || '';
    const market = cells[1] || '';
    const ticker = cells[2] || '';
    if (/^\d{6}$/.test(ticker) && name) {
      rows.push({ ticker, name, market: market.includes('KOSDAQ') ? 'KQ' : 'KS' });
    }
  }
  return rows;
}

async function loadStocks() {
  try {
    const body = await fetchBuffer(KRX_LIST_URL, {
      'User-Agent': 'Mozilla/5.0',
      Referer: 'https://kind.krx.co.kr/corpgeneral/corpList.do?method=loadInitPage',
    });
    const html = iconv.decode(body, 'euc-kr');
    const rows = parseKrxRows(html);
    if (rows.length) return rows;
  } catch (error) {
    console.warn(`[warn] failed to fetch KRX list: ${error.message}`);
  }

  const fallbackPath = path.join(__dirname, 'stock_aliases.generated.json');
  const fallback = JSON.parse(fs.readFileSync(fallbackPath, 'utf8'));
  return fallback.map((item) => ({
    ticker: item.ticker,
    name: item.name,
    market: 'KS',
  }));
}

function parseNaverHistory(body) {
  const rows = [];
  const rowRegex =
    /\["(\d{8})",\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),/g;
  let match;
  while ((match = rowRegex.exec(body)) !== null) {
    rows.push({
      date: match[1],
      open: Number(match[2]),
      high: Number(match[3]),
      low: Number(match[4]),
      close: Number(match[5]),
      volume: Number(match[6]),
    });
  }
  return rows;
}

function parseRowDate(row) {
  const raw = String(row.date || '');
  if (!/^\d{8}$/.test(raw)) return null;
  return new Date(Number(raw.slice(0, 4)), Number(raw.slice(4, 6)) - 1, Number(raw.slice(6, 8)));
}

function daysBetweenRows(a, b) {
  const da = parseRowDate(a);
  const db = parseRowDate(b);
  if (!da || !db) return 0;
  return Math.round((db - da) / 86400000);
}

function hasRecentTradingHaltOrAbnormalGap(rows, lookback = 80) {
  const recent = rows.slice(-lookback);
  for (let i = 1; i < recent.length; i += 1) {
    const calendarGap = daysBetweenRows(recent[i - 1], recent[i]);
    if (calendarGap > MAX_CALENDAR_GAP_DAYS) return true;

    const prevClose = recent[i - 1].close;
    const openGap = prevClose ? Math.abs(recent[i].open - prevClose) / prevClose : 0;
    if (openGap > MAX_OPEN_GAP) return true;
  }
  return false;
}

async function fetchHistory(ticker, endDate) {
  const start = new Date(endDate);
  start.setDate(start.getDate() - LOOKBACK_DAYS * 1.7);
  const url =
    `https://api.finance.naver.com/siseJson.naver?symbol=${ticker}` +
    `&requestType=1&startTime=${formatYmd(start)}&endTime=${formatYmd(endDate)}&timeframe=day`;
  const body = await fetchBuffer(url, {
    'User-Agent': 'Mozilla/5.0',
    Referer: 'https://finance.naver.com',
  });
  return parseNaverHistory(body.toString('utf8')).slice(-LOOKBACK_DAYS);
}

function average(values) {
  if (!values.length) return 0;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function sma(rows, period, offset = 0, field = 'close') {
  const end = rows.length - offset;
  const start = end - period;
  if (start < 0) return null;
  return average(rows.slice(start, end).map((row) => row[field]));
}

function slope(rows, period, compareOffset, field = 'close') {
  const current = sma(rows, period, 0, field);
  const previous = sma(rows, period, compareOffset, field);
  if (!current || !previous) return 0;
  return (current - previous) / previous;
}

function isGoldenCross(rows, shortPeriod, longPeriod) {
  const shortNow = sma(rows, shortPeriod);
  const shortPrev = sma(rows, shortPeriod, 1);
  const longNow = sma(rows, longPeriod);
  const longPrev = sma(rows, longPeriod, 1);
  if (!shortNow || !shortPrev || !longNow || !longPrev) return false;
  return shortPrev <= longPrev && shortNow > longNow;
}

function highest(rows, field = 'high') {
  return Math.max(...rows.map((row) => row[field]));
}

function lowest(rows, field = 'low') {
  return Math.min(...rows.map((row) => row[field]));
}

function maxIndex(rows, field = 'high') {
  let bestIndex = 0;
  for (let i = 1; i < rows.length; i += 1) {
    if (rows[i][field] > rows[bestIndex][field]) bestIndex = i;
  }
  return bestIndex;
}

function minIndex(rows, field = 'low') {
  let bestIndex = 0;
  for (let i = 1; i < rows.length; i += 1) {
    if (rows[i][field] < rows[bestIndex][field]) bestIndex = i;
  }
  return bestIndex;
}

function closeReturn(rows, period) {
  if (rows.length <= period) return 0;
  const last = rows[rows.length - 1].close;
  const base = rows[rows.length - 1 - period].close;
  return base ? (last - base) / base : 0;
}

function detectCupAndHandle(rows) {
  const last = rows[rows.length - 1];
  if (rows.length < CUP_MIN_DAYS + HANDLE_MIN_DAYS + 40) return null;

  let best = null;
  const maxCupDays = Math.min(CUP_MAX_DAYS, rows.length - HANDLE_MIN_DAYS);
  for (let handleDays = HANDLE_MIN_DAYS; handleDays <= HANDLE_MAX_DAYS; handleDays += 1) {
    const handle = rows.slice(-handleDays);
    if (handle.length < handleDays) continue;

    for (let cupDays = CUP_MIN_DAYS; cupDays <= maxCupDays; cupDays += 5) {
      const start = rows.length - handleDays - cupDays;
      if (start < 20) continue;

      const cup = rows.slice(start, start + cupDays);
      const leftZone = cup.slice(0, Math.max(8, Math.floor(cup.length * 0.35)));
      const midZone = cup.slice(Math.floor(cup.length * 0.18), Math.floor(cup.length * 0.82));
      const rightZone = cup.slice(Math.floor(cup.length * 0.55));
      if (leftZone.length < 8 || midZone.length < 15 || rightZone.length < 8) continue;

      const leftHighIndex = maxIndex(leftZone, 'high');
      const leftHigh = leftZone[leftHighIndex].high;
      const cupLowRel = minIndex(midZone, 'low');
      const cupLowIndex = Math.floor(cup.length * 0.18) + cupLowRel;
      const cupLow = cup[cupLowIndex].low;
      const rightHighRel = maxIndex(rightZone, 'high');
      const rightHighIndex = Math.floor(cup.length * 0.55) + rightHighRel;
      const rightHigh = cup[rightHighIndex].high;

      const declineDays = cupLowIndex - leftHighIndex;
      const recoveryDays = rightHighIndex - cupLowIndex;
      if (declineDays < 15 || recoveryDays < 15) continue;

      const cupDepth = (leftHigh - cupLow) / leftHigh;
      if (cupDepth < CUP_MIN_DEPTH || cupDepth > CUP_MAX_DEPTH) continue;
      if (rightHigh < leftHigh * 0.88 || rightHigh > leftHigh * 1.08) continue;

      const rim = Math.max(leftHigh, rightHigh);
      const handleHigh = highest(handle, 'high');
      const handleLow = lowest(handle, 'low');
      const handleDepth = (rim - handleLow) / rim;
      const maxHandleDepth = Math.min(0.15, cupDepth / 3);
      if (handleDepth < 0.025 || handleDepth > maxHandleDepth) continue;
      if (handleLow < cupLow + (rim - cupLow) * 0.5) continue;
      if (handleHigh > rim * 1.04) continue;

      const firstHandleClose = handle[0].close;
      const lastHandleClose = handle[handle.length - 1].close;
      const handleSlope = firstHandleClose ? (lastHandleClose - firstHandleClose) / firstHandleClose : 0;
      if (handleSlope > 0.08) continue;

      const bottomBand = cupLow * 1.08;
      const bottomDays = cup.filter((row) => row.low <= bottomBand).length;
      if (bottomDays < Math.max(3, Math.floor(cup.length * 0.04))) continue;

      const sideBalance = Math.min(declineDays, recoveryDays) / Math.max(declineDays, recoveryDays);
      if (sideBalance < 0.35) continue;

      const beforeCup = rows.slice(Math.max(0, start - 45), start);
      const priorAdvance =
        beforeCup.length >= 20 && beforeCup[0].close
          ? (leftHigh - beforeCup[0].close) / beforeCup[0].close
          : 0;

      const leftVolume = average(cup.slice(0, Math.floor(cup.length * 0.35)).map((row) => row.volume));
      const bottomVolume = average(
        cup
          .slice(Math.max(0, cupLowIndex - 5), Math.min(cup.length, cupLowIndex + 6))
          .map((row) => row.volume),
      );
      const rightVolume = average(cup.slice(Math.floor(cup.length * 0.55)).map((row) => row.volume));
      const handleVolume = average(handle.slice(0, -1).map((row) => row.volume));
      const breakoutVolumeRatio = handleVolume ? last.volume / handleVolume : 0;
      if (handleVolume > leftVolume * 0.95) continue;

      const breakoutLine = Math.max(rim, highest(handle.slice(0, -1), 'high'));
      const distanceFromBreakout = (last.close - breakoutLine) / breakoutLine;
      const setupReady = distanceFromBreakout >= -0.03 && distanceFromBreakout < 0;
      const breakout = distanceFromBreakout >= 0 && distanceFromBreakout <= 0.06;
      if (!setupReady && !breakout) continue;
      if (breakout && breakoutVolumeRatio < 1.25) continue;

      let quality = 0;
      quality += 25;
      quality += Math.max(0, 12 - Math.abs(cupDepth - 0.22) * 80);
      quality += Math.max(0, 12 - Math.abs(handleDepth - 0.07) * 120);
      quality += Math.round(sideBalance * 10);
      quality += bottomVolume < leftVolume ? 6 : 0;
      quality += rightVolume > bottomVolume ? 6 : 0;
      quality += priorAdvance >= 0.15 ? 8 : 0;
      quality += breakout ? 10 : 4;

      const candidate = {
        cupDepth,
        cupDays,
        handleDepth,
        handleDays,
        breakoutLine,
        distanceFromBreakout,
        breakoutVolumeRatio,
        setupState: breakout ? 'breakout' : 'ready',
        quality,
      };
      if (!best || candidate.quality > best.quality) best = candidate;
    }
  }
  return best;
}

function lowerTailRatio(row) {
  const range = row.high - row.low;
  if (range <= 0) return 0;
  const lowerBody = Math.min(row.open, row.close);
  return (lowerBody - row.low) / range;
}

function closePositionRatio(row) {
  const range = row.high - row.low;
  if (range <= 0) return 0.5;
  return (row.close - row.low) / range;
}

function detectVolumeSurgePullbackTail(rows) {
  if (rows.length < 80) return null;
  const last = rows[rows.length - 1];
  const start = Math.max(20, rows.length - SURGE_LOOKBACK_DAYS - 1);
  let best = null;

  for (let i = start; i < rows.length - 3; i += 1) {
    const surge = rows[i];
    const previous = rows[i - 1];
    const avgVolBefore = average(rows.slice(Math.max(0, i - 20), i).map((row) => row.volume));
    const gain = previous.close ? (surge.close - previous.close) / previous.close : 0;
    const volumeRatio = avgVolBefore ? surge.volume / avgVolBefore : 0;
    const closeNearHigh = closePositionRatio(surge) >= 0.65;
    if (gain < SURGE_MIN_GAIN || volumeRatio < SURGE_MIN_VOLUME_RATIO || !closeNearHigh) continue;

    const after = rows.slice(i + 1);
    if (after.length < 3 || after.length > SURGE_LOOKBACK_DAYS) continue;
    if (highest(after, 'high') > surge.high * 1.003) continue;
    const afterLow = lowest(after, 'low');
    const afterCloseLow = lowest(after, 'close');
    if (afterCloseLow < previous.close) continue;
    const pullback = (surge.high - afterLow) / surge.high;
    const closePullback = (surge.close - afterLow) / surge.close;
    const targetPullbackMin = Math.max(PULLBACK_MIN, PULLBACK_TARGET - PULLBACK_TOLERANCE);
    const targetPullbackMax = Math.min(PULLBACK_MAX, PULLBACK_TARGET + PULLBACK_TOLERANCE);
    if (pullback < targetPullbackMin || pullback > targetPullbackMax) continue;
    if (closePullback < targetPullbackMin * 0.85) continue;
    if (afterLow < surge.low * 0.96) continue;

    const lowIndexAfterSurge = after.findIndex((row) => row.low === afterLow);
    if (lowIndexAfterSurge < MIN_DROP_DAYS_AFTER_SURGE) continue;
    const dropLeg = after.slice(0, lowIndexAfterSurge + 1);
    const lowerCloses = dropLeg.filter((row, idx) => idx > 0 && row.close < dropLeg[idx - 1].close).length;
    if (lowerCloses < 2) continue;

    const leftPullback = after.slice(0, lowIndexAfterSurge + 1);
    const rightRecovery = after.slice(lowIndexAfterSurge);
    if (leftPullback.length < 2 || rightRecovery.length < U_BASE_MIN_DAYS) continue;

    const baseZone = rightRecovery.filter((row) => row.low <= afterLow * (1 + U_BASE_ZONE_PCT));
    if (baseZone.length < U_BASE_MIN_DAYS) continue;

    const lastCloseFromLow = afterLow ? (last.close - afterLow) / afterLow : 0;
    const currentPullback = (surge.high - last.close) / surge.high;
    const recoveredTooFast =
      rightRecovery.length <= 3 && last.close > afterLow + (surge.high - afterLow) * 0.45;
    if (recoveredTooFast) continue;
    if (
      lastCloseFromLow < MIN_BOUNCE_FROM_PULLBACK_LOW ||
      lastCloseFromLow > MAX_BOUNCE_FROM_PULLBACK_LOW
    ) {
      continue;
    }
    if (currentPullback < targetPullbackMin * 0.7) continue;
    if (last.close > surge.close * 0.96) continue;

    const tailWindow = after.slice(lowIndexAfterSurge).slice(-LOWER_TAIL_WINDOW_DAYS);
    if (tailWindow.length < LOWER_TAIL_MIN_COUNT) continue;
    const pullbackBase = afterLow;
    const tailCandles = tailWindow.filter((row) => {
      const bodyRatio = Math.abs(row.close - row.open) / Math.max(1, row.high - row.low);
      const lowNearPullbackZone = row.low <= pullbackBase * (1 + U_BASE_ZONE_PCT);
      return (
        lowNearPullbackZone &&
        lowerTailRatio(row) >= LOWER_TAIL_MIN_RATIO &&
        closePositionRatio(row) >= LOWER_TAIL_MIN_CLOSE_POSITION &&
        bodyRatio <= LOWER_TAIL_MAX_BODY_RATIO
      );
    });
    if (tailCandles.length < LOWER_TAIL_MIN_COUNT) continue;

    const pullbackVolumes = after.slice(0, -1).map((row) => row.volume);
    const avgPullbackVolume = average(pullbackVolumes);
    if (avgPullbackVolume > surge.volume * 0.65) continue;

    const ma20 = sma(rows.slice(0, rows.length), 20);
    const ma60 = sma(rows.slice(0, rows.length), 60);
    const supportNearMa20 = ma20 ? Math.abs(last.close - ma20) / ma20 <= 0.08 || afterLow <= ma20 * 1.04 : false;
    const supportNearMa60 = ma60 ? Math.abs(last.close - ma60) / ma60 <= 0.08 || afterLow <= ma60 * 1.04 : false;
    if (!supportNearMa20 && !supportNearMa60) continue;

    const tailLows = tailCandles.map((row) => row.low);
    const tailLowMin = Math.min(...tailLows);
    const tailLowMax = Math.max(...tailLows);
    const lowSpread = tailLowMin ? (tailLowMax - tailLowMin) / tailLowMin : 1;
    if (lowSpread > 0.08) continue;

    const returnAfterSurge = surge.close ? (last.close - surge.close) / surge.close : 0;
    if (returnAfterSurge > 0.1) continue;

    const recoverySignal =
      last.close > sma(rows, 5) ||
      last.close > rows[rows.length - 2].high ||
      last.volume > avgPullbackVolume * 1.2;

    let quality = 40;
    quality += Math.min(18, volumeRatio * 2);
    quality += Math.max(0, 16 - Math.abs(pullback - PULLBACK_TARGET) * 180);
    quality += tailCandles.length * 5;
    quality += supportNearMa20 ? 8 : 4;
    quality += recoverySignal ? 8 : 0;
    quality += avgPullbackVolume < surge.volume * 0.45 ? 6 : 0;

    const candidate = {
      surgeDaysAgo: rows.length - 1 - i,
      surgeGain: gain,
      surgeVolumeRatio: volumeRatio,
      pullback,
      currentPullback,
      tailCount: tailCandles.length,
      avgPullbackVolumeRatio: avgPullbackVolume / surge.volume,
      support: supportNearMa20 ? 'ma20' : 'ma60',
      recoverySignal,
      baseDays: baseZone.length,
      quality,
    };
    if (
      !best ||
      candidate.surgeDaysAgo > best.surgeDaysAgo ||
      (candidate.surgeDaysAgo === best.surgeDaysAgo && candidate.quality > best.quality)
    ) {
      best = candidate;
    }
  }

  return best;
}

function detectStrictGoldenCross(rows) {
  if (rows.length < 130) return null;
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const ma20 = sma(rows, 20);
  const ma60 = sma(rows, 60);
  const ma120 = sma(rows, 120);
  const ma20Prev = sma(rows, 20, 1);
  const ma60Prev = sma(rows, 60, 1);
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const volumeRatio = avgVolume20 ? last.volume / avgVolume20 : 0;
  if (!ma20 || !ma60 || !ma120 || !ma20Prev || !ma60Prev) return null;

  const cross20_60 = ma20Prev <= ma60Prev && ma20 > ma60;
  const cross5_20 = isGoldenCross(rows, 5, 20);
  if (!cross20_60 && !cross5_20) return null;
  if (volumeRatio < GOLDEN_MIN_VOLUME_RATIO) return null;
  if (volumeRatio > GOLDEN_MAX_VOLUME_RATIO) return null;
  if (last.close < ma20) return null;
  if (last.close < ma60) return null;

  const ma20Slope = slope(rows, 20, 5);
  const ma60Slope = slope(rows, 60, 10);
  if (ma20Slope <= 0) return null;
  if (ma60Slope < -0.005) return null;

  const distanceFromMa20 = (last.close - ma20) / ma20;
  if (distanceFromMa20 > GOLDEN_MAX_DISTANCE_FROM_MA20) return null;
  if (closeReturn(rows, 5) > GOLDEN_MAX_5D_RETURN) return null;
  if (closeReturn(rows, 20) > GOLDEN_MAX_20D_RETURN) return null;

  const previous60 = rows.slice(-61, -1);
  const resistance60 = highest(previous60, 'high');
  const distanceToResistance = resistance60 ? (last.close - resistance60) / resistance60 : 0;
  const breakoutEarly =
    distanceToResistance >= -GOLDEN_BREAKOUT_BAND &&
    distanceToResistance <= GOLDEN_BREAKOUT_BAND &&
    last.close >= prev.close;
  if (!breakoutEarly) return null;

  const recentLow20 = lowest(rows.slice(-20), 'low');
  const baseCompression = resistance60 && recentLow20 ? (resistance60 - recentLow20) / recentLow20 : 1;
  if (baseCompression > 0.35) return null;

  let quality = 45;
  quality += cross20_60 ? 20 : 10;
  quality += Math.min(16, volumeRatio * 4);
  quality += ma60Slope > 0 ? 8 : 3;
  quality += Math.max(0, 10 - Math.abs(distanceToResistance) * 120);
  quality += Math.max(0, 8 - distanceFromMa20 * 60);
  quality += baseCompression < 0.22 ? 6 : 0;

  return {
    type: cross20_60 ? '20_60' : '5_20',
    volumeRatio,
    distanceFromMa20,
    distanceToResistance,
    ma20Slope,
    ma60Slope,
    baseCompression,
    quality,
  };
}

function detectMaClusterTouch(rows) {
  if (rows.length < 130) return null;
  const last = rows[rows.length - 1];
  const ma20 = sma(rows, 20);
  const ma60 = sma(rows, 60);
  const ma120 = sma(rows, 120);
  if (!ma20 || !ma60 || !ma120) return null;

  const maValues = [ma20, ma60, ma120];
  const maHigh = Math.max(...maValues);
  const maLow = Math.min(...maValues);
  const clusterSpread = maLow ? (maHigh - maLow) / maLow : 1;
  if (clusterSpread > MA_CLUSTER_MAX_SPREAD) return null;

  const clusterCenter = average(maValues);
  const distanceFromCluster = clusterCenter ? Math.abs(last.close - clusterCenter) / clusterCenter : 1;
  if (distanceFromCluster > MA_CLUSTER_MAX_DISTANCE) return null;
  if (closeReturn(rows, 5) > 0.15 || closeReturn(rows, 20) > 0.3) return null;
  const ma120Past = sma(rows, 120, 20);
  if (!ma120Past || (ma120 - ma120Past) / ma120Past < MA120_MIN_SLOPE) return null;

  const noBreakStart = Math.max(120, rows.length - MA_NO_120_BREAK_LOOKBACK);
  for (let idx = noBreakStart; idx < rows.length - MA_TOUCH_LOOKBACK_DAYS; idx += 1) {
    const historyUntil = rows.slice(0, idx + 1);
    const ma120AtIdx = sma(historyUntil, 120);
    if (!ma120AtIdx) continue;
    if (rows[idx].close < ma120AtIdx * 0.995 || rows[idx].low < ma120AtIdx * 0.98) {
      return null;
    }
  }

  const recent = rows.slice(-MA_TOUCH_LOOKBACK_DAYS);
  let bestTouch = null;
  for (const row of recent) {
    const candidates = [
      ['ma20', ma20],
      ['ma60', ma60],
      ['ma120', ma120],
    ];
    for (const [name, ma] of candidates) {
      const lowDistance = Math.abs(row.low - ma) / ma;
      if (MA_REQUIRE_120_TOUCH && name !== 'ma120') continue;
      const touchedFromAbove = row.low <= ma * 1.003 && row.low >= ma * (1 - MA_TOUCH_BAND);
      const piercedAndRecovered = row.low < ma && row.low >= ma * (1 - MA_TOUCH_BAND) && row.close >= ma * 1.005;
      if (!touchedFromAbove && !piercedAndRecovered) continue;

      const tail = lowerTailRatio(row);
      const closePos = closePositionRatio(row);
      if (tail < 0.28 && closePos < 0.6) continue;
      let touchQuality = 20;
      touchQuality += name === 'ma120' ? 16 : name === 'ma60' ? 10 : 6;
      touchQuality += Math.max(0, 10 - lowDistance * 200);
      touchQuality += tail >= 0.35 ? 10 : 0;
      touchQuality += closePos >= 0.55 ? 6 : 0;
      if (!bestTouch || touchQuality > bestTouch.touchQuality) {
        bestTouch = {
          maName: name,
          ma,
          lowDistance,
          tail,
          closePos,
          touchQuality,
          date: row.date,
        };
      }
    }
  }
  if (!bestTouch) return null;

  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const volumeRatio = avgVolume20 ? last.volume / avgVolume20 : 0;
  const recoveredAboveCluster = last.close >= maHigh * 0.995;
  const stillNearCluster = last.close <= maHigh * 1.05;
  if (!stillNearCluster) return null;
  const prev = rows[rows.length - 2];
  const reboundSignal =
    volumeRatio >= MA_MIN_REBOUND_VOLUME_RATIO &&
    last.close > last.open &&
    (last.close >= prev.high || recoveredAboveCluster);
  if (!reboundSignal) return null;

  const recentHigh20 = highest(rows.slice(-20), 'high');
  const recentLow20 = lowest(rows.slice(-20), 'low');
  const boxRange20 = recentLow20 ? (recentHigh20 - recentLow20) / recentLow20 : 1;
  if (boxRange20 > 0.24) return null;

  let quality = 35 + bestTouch.touchQuality;
  quality += recoveredAboveCluster ? 10 : 0;
  quality += volumeRatio >= 1.2 ? Math.min(10, volumeRatio * 3) : 0;
  quality += boxRange20 <= 0.22 ? 8 : 0;
  quality += slope(rows, 20, 5) >= -0.005 ? 5 : 0;
  quality += slope(rows, 60, 10) >= -0.005 ? 5 : 0;

  return {
    maName: bestTouch.maName,
    touchDate: bestTouch.date,
    touchDistance: bestTouch.lowDistance,
    tailRatio: bestTouch.tail,
    clusterSpread,
    distanceFromCluster,
    recoveredAboveCluster,
    volumeRatio,
    boxRange20,
    quality,
  };
}

function detectMa120ReclaimCompressionBreakout(rows) {
  if (rows.length < 150) return null;
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const ma20 = sma(rows, 20);
  const ma60 = sma(rows, 60);
  const ma120 = sma(rows, 120);
  if (!ma20 || !ma60 || !ma120) return null;

  const maValues = [ma20, ma60, ma120];
  const maHigh = Math.max(...maValues);
  const maLow = Math.min(...maValues);
  const maSpread = maLow ? (maHigh - maLow) / maLow : 1;
  if (maSpread > RECLAIM_MAX_MA_SPREAD) return null;

  const ma120Past = sma(rows, 120, 20);
  const ma120Slope = ma120Past ? (ma120 - ma120Past) / ma120Past : 0;
  const ma60Slope = slope(rows, 60, 20);
  const ma20Slope = slope(rows, 20, 10);
  if (ma120Slope < RECLAIM_MIN_MA120_SLOPE) return null;
  if (ma60Slope < RECLAIM_MIN_MA60_SLOPE) return null;
  if (ma20Slope < -0.01) return null;
  if (ma20 < ma120 * 0.97 && ma60 < ma120 * 0.97) return null;

  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const volumeRatio = avgVolume20 ? last.volume / avgVolume20 : 0;
  if (volumeRatio < RECLAIM_MIN_VOLUME_RATIO) return null;
  if (last.close <= last.open) return null;
  if (closePositionRatio(last) < 0.65) return null;
  if (closeReturn(rows, 5) > 0.25 || closeReturn(rows, 20) > 0.45) return null;

  let best = null;
  const start = Math.max(120, rows.length - RECLAIM_LOOKBACK_DAYS);
  for (let i = start; i < rows.length - 3; i += 1) {
    const historyUntilUndercut = rows.slice(0, i + 1);
    const ma120AtUndercut = sma(historyUntilUndercut, 120);
    if (!ma120AtUndercut) continue;

    const undercut = (ma120AtUndercut - rows[i].low) / ma120AtUndercut;
    if (undercut < RECLAIM_MIN_UNDERCUT || undercut > RECLAIM_MAX_UNDERCUT) continue;
    if (rows[i].close < ma120AtUndercut * (1 - RECLAIM_MAX_UNDERCUT)) continue;

    let reclaimIndex = -1;
    for (let j = i; j <= Math.min(rows.length - 2, i + RECLAIM_MAX_DAYS); j += 1) {
      const historyUntilReclaim = rows.slice(0, j + 1);
      const ma120AtReclaim = sma(historyUntilReclaim, 120);
      if (!ma120AtReclaim) continue;
      if (rows[j].close >= ma120AtReclaim * 1.005) {
        reclaimIndex = j;
        break;
      }
    }
    if (reclaimIndex < 0) continue;

    const base = rows.slice(reclaimIndex, rows.length - 1);
    if (base.length < 2) continue;
    const baseLow = lowest(base, 'low');
    const baseHigh = highest(base, 'high');
    const baseRange = baseLow ? (baseHigh - baseLow) / baseLow : 1;
    if (baseRange > 0.28) continue;

    const baseVolume = average(base.map((row) => row.volume));
    if (base.length >= 5 && avgVolume20 && baseVolume > avgVolume20 * 1.15) continue;

    const previousBox = rows.slice(Math.max(0, rows.length - 21), rows.length - 1);
    const boxHigh = highest(previousBox, 'high');
    const reclaimedMaCluster = last.close >= maHigh * 1.02;
    const breakout = (last.close >= boxHigh * 0.995 || reclaimedMaCluster) && last.close > prev.close;
    if (!breakout) continue;

    const supportAfterReclaim = baseLow >= ma120 * 0.95;
    if (!supportAfterReclaim) continue;

    let quality = 45;
    quality += Math.max(0, 14 - Math.abs(undercut - 0.035) * 220);
    quality += Math.max(0, 12 - maSpread * 120);
    quality += Math.min(14, volumeRatio * 4);
    quality += baseRange < 0.18 ? 8 : 0;
    quality += ma120Slope >= 0 ? 8 : 3;
    quality += rows.length - 1 - reclaimIndex >= 5 ? 5 : 0;

    const candidate = {
      undercutDate: rows[i].date,
      reclaimDate: rows[reclaimIndex].date,
      undercut,
      reclaimDays: reclaimIndex - i,
      maSpread,
      ma120Slope,
      ma60Slope,
      ma20Slope,
      baseDays: rows.length - 1 - reclaimIndex,
      baseRange,
      volumeRatio,
      boxDistance: boxHigh ? (last.close - boxHigh) / boxHigh : 0,
      quality,
    };
    if (
      !best ||
      candidate.surgeDaysAgo > best.surgeDaysAgo ||
      (candidate.surgeDaysAgo === best.surgeDaysAgo && candidate.quality > best.quality)
    ) {
      best = candidate;
    }
  }

  return best;
}

function detectMaClusterVolumeBreakout(rows) {
  if (rows.length < 140) return null;
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const ma20 = sma(rows, 20);
  const ma60 = sma(rows, 60);
  const ma120 = sma(rows, 120);
  if (!ma20 || !ma60 || !ma120 || !prev) return null;

  const maValues = [ma20, ma60, ma120];
  const maHigh = Math.max(...maValues);
  const maLow = Math.min(...maValues);
  const maCenter = average(maValues);
  const maSpread = maLow ? (maHigh - maLow) / maLow : 1;
  if (maSpread > CLUSTER_BREAKOUT_MAX_MA_SPREAD) return null;

  const gain = prev.close ? (last.close - prev.close) / prev.close : 0;
  if (gain < CLUSTER_BREAKOUT_MIN_GAIN) return null;
  if (last.close <= last.open) return null;
  if (closePositionRatio(last) < 0.7) return null;

  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const volumeRatio = avgVolume20 ? last.volume / avgVolume20 : 0;
  if (volumeRatio < CLUSTER_BREAKOUT_MIN_VOLUME_RATIO) return null;

  const distanceFromCluster = maCenter ? (last.close - maCenter) / maCenter : 1;
  if (distanceFromCluster < 0 || distanceFromCluster > CLUSTER_BREAKOUT_MAX_DISTANCE) return null;

  const previous20 = rows.slice(-21, -1);
  const previousHigh20 = highest(previous20, 'high');
  const previousLow20 = lowest(previous20, 'low');
  const boxRange20 = previousLow20 ? (previousHigh20 - previousLow20) / previousLow20 : 1;
  if (boxRange20 > 0.28) return null;
  if (last.close < previousHigh20 * 0.995 && last.close < maHigh * 1.04) return null;

  const clusterTouches = previous20.filter((row) => row.low <= maHigh * 1.04 && row.high >= maLow * 0.96).length;
  if (clusterTouches < 5) return null;

  const ma120Past = sma(rows, 120, 20);
  const ma120Slope = ma120Past ? (ma120 - ma120Past) / ma120Past : 0;
  if (ma120Slope < -0.03) return null;
  if (closeReturn(rows, 5) > 0.32 || closeReturn(rows, 20) > 0.6) return null;

  let quality = 45;
  quality += Math.max(0, 14 - maSpread * 150);
  quality += Math.min(16, volumeRatio * 4);
  quality += Math.max(0, 12 - Math.abs(gain - 0.11) * 100);
  quality += boxRange20 < 0.2 ? 8 : 0;
  quality += distanceFromCluster <= 0.18 ? 8 : 3;
  quality += ma120Slope >= 0 ? 6 : 2;

  return {
    gain,
    volumeRatio,
    maSpread,
    distanceFromCluster,
    boxRange20,
    clusterTouches,
    ma120Slope,
    quality,
  };
}

function detectVolumeSpikeBreakoutDryUpRise(rows) {
  if (rows.length < 80) return null;
  const last = rows[rows.length - 1];
  const start = Math.max(20, rows.length - DRYUP_LOOKBACK_DAYS - 1);
  let best = null;

  for (let i = start; i < rows.length - 4; i += 1) {
    const surge = rows[i];
    const previous = rows[i - 1];
    const avgVolBefore = average(rows.slice(Math.max(0, i - 20), i).map((row) => row.volume));
    const surgeGain = previous.close ? (surge.close - previous.close) / previous.close : 0;
    const surgeVolumeRatio = avgVolBefore ? surge.volume / avgVolBefore : 0;
    const surgeTradingValue = surge.close * surge.volume;
    if (surgeGain < DRYUP_MIN_SURGE_GAIN || surgeVolumeRatio < DRYUP_MIN_SURGE_VOLUME_RATIO) continue;
    if (surgeTradingValue < DRYUP_MIN_SURGE_TRADING_VALUE) continue;
    if (surge.close <= surge.open || closePositionRatio(surge) < 0.7) continue;

    const after = rows.slice(i + 1);
    if (after.length < 4 || after.length > DRYUP_LOOKBACK_DAYS) continue;
    const afterLow = lowest(after, 'low');
    const afterCloseLow = lowest(after, 'close');
    const afterHigh = highest(after, 'high');
    if (afterCloseLow < previous.close) continue;
    const maxPullback = (surge.high - afterLow) / surge.high;
    if (maxPullback > DRYUP_MAX_PULLBACK) continue;
    if (last.close < surge.close * 0.995) continue;

    const runup = (last.close - surge.close) / surge.close;
    if (runup < 0.01 || runup > DRYUP_MAX_RUNUP) continue;
    if (last.close < afterHigh * 0.95) continue;

    const postAvgVolume = average(after.map((row) => row.volume));
    const recentVolume = average(after.slice(-3).map((row) => row.volume));
    const postAvgVolumeRatio = postAvgVolume / surge.volume;
    const recentVolumeRatio = recentVolume / surge.volume;
    if (postAvgVolumeRatio > DRYUP_MAX_POST_AVG_VOLUME_RATIO) continue;
    if (recentVolumeRatio > DRYUP_MAX_RECENT_VOLUME_RATIO) continue;

    const closes = after.map((row) => row.close);
    const higherCloseCount = closes.filter((close, idx) => idx > 0 && close >= closes[idx - 1]).length;
    const upwardDrift = higherCloseCount >= Math.floor((closes.length - 1) * 0.45);
    if (!upwardDrift && last.close < average(closes)) continue;

    const recentLows = after.slice(-5).map((row) => row.low);
    const recentLowMin = Math.min(...recentLows);
    const recentLowMax = Math.max(...recentLows);
    const lowStability = recentLowMin ? (recentLowMax - recentLowMin) / recentLowMin : 1;
    if (lowStability > 0.12) continue;

    const ma20 = sma(rows, 20);
    const ma60 = sma(rows, 60);
    if (!ma20 || !ma60) continue;
    const ma20Distance = (last.close - ma20) / ma20;
    const ma60Distance = (last.close - ma60) / ma60;
    if (
      ma20Distance < DRYUP_RISE_MIN_MA20_DISTANCE ||
      ma20Distance > DRYUP_RISE_MAX_MA20_DISTANCE ||
      ma60Distance < DRYUP_RISE_MIN_MA60_DISTANCE ||
      ma60Distance > DRYUP_RISE_MAX_MA60_DISTANCE
    ) {
      continue;
    }

    let quality = 45;
    quality += Math.min(18, surgeVolumeRatio * 3);
    quality += Math.max(0, 12 - maxPullback * 160);
    quality += Math.max(0, 12 - postAvgVolumeRatio * 18);
    quality += Math.max(0, 10 - recentVolumeRatio * 25);
    quality += Math.max(0, 8 - Math.abs(runup - 0.12) * 60);
    quality += upwardDrift ? 6 : 0;

    const candidate = {
      surgeDaysAgo: rows.length - 1 - i,
      surgeGain,
      surgeVolumeRatio,
      surgeTradingValue,
      maxPullback,
      runup,
      postAvgVolumeRatio,
      recentVolumeRatio,
      lowStability,
      ma20Distance,
      ma60Distance,
      quality,
    };
    if (!best || candidate.quality > best.quality) best = candidate;
  }

  return best;
}

function detectVolumeSpikeDryUpPullbackSupport(rows) {
  if (rows.length < 80) return null;
  const last = rows[rows.length - 1];
  const start = Math.max(20, rows.length - DRYUP_LOOKBACK_DAYS - 1);
  let best = null;

  for (let i = start; i < rows.length - 4; i += 1) {
    const surge = rows[i];
    const previous = rows[i - 1];
    const avgVolBefore = average(rows.slice(Math.max(0, i - 20), i).map((row) => row.volume));
    const surgeGain = previous.close ? (surge.close - previous.close) / previous.close : 0;
    const surgeVolumeRatio = avgVolBefore ? surge.volume / avgVolBefore : 0;
    const surgeTradingValue = surge.close * surge.volume;
    if (surgeGain < DRYUP_MIN_SURGE_GAIN || surgeVolumeRatio < DRYUP_MIN_SURGE_VOLUME_RATIO) continue;
    if (surgeTradingValue < DRYUP_MIN_SURGE_TRADING_VALUE) continue;
    if (surge.close <= surge.open || closePositionRatio(surge) < 0.65) continue;

    const after = rows.slice(i + 1);
    if (after.length < 4 || after.length > DRYUP_LOOKBACK_DAYS) continue;
    if (highest(after, 'high') > surge.high * 1.003) continue;

    const afterLow = lowest(after, 'low');
    const afterCloseLow = lowest(after, 'close');
    if (afterCloseLow < previous.close) continue;
    const pullback = (surge.high - afterLow) / surge.high;
    if (pullback < DRYUP_SUPPORT_MIN_PULLBACK || pullback > DRYUP_SUPPORT_MAX_PULLBACK) continue;
    if (afterLow < surge.low * 0.97) continue;

    const bodyMid = Math.min(surge.open, surge.close) + Math.abs(surge.close - surge.open) * 0.5;
    if (last.close < bodyMid) continue;
    if (last.close > surge.high * 0.98) continue;

    const postAvgVolume = average(after.map((row) => row.volume));
    const recentVolume = average(after.slice(-3).map((row) => row.volume));
    const postAvgVolumeRatio = postAvgVolume / surge.volume;
    const recentVolumeRatio = recentVolume / surge.volume;
    if (
      postAvgVolumeRatio > DRYUP_MAX_POST_AVG_VOLUME_RATIO ||
      recentVolumeRatio > DRYUP_MAX_RECENT_VOLUME_RATIO
    ) continue;

    const recent = after.slice(-7);
    const recentLow = lowest(recent, 'low');
    const recentLowSpread = recentLow ? (highest(recent, 'low') - recentLow) / recentLow : 1;
    if (recentLowSpread > 0.12) continue;

    const lastTwo = after.slice(-2);
    const supportSignal = lastTwo.some((row) => row.close > row.open || lowerTailRatio(row) >= 0.35);
    if (!supportSignal) continue;

    const ma20 = sma(rows, 20);
    const ma60 = sma(rows, 60);
    if (!ma20 || !ma60) continue;
    const ma20Distance = (last.close - ma20) / ma20;
    const ma60Distance = (last.close - ma60) / ma60;
    if (
      ma20Distance < DRYUP_SUPPORT_MIN_MA20_DISTANCE ||
      ma20Distance > DRYUP_SUPPORT_MAX_MA20_DISTANCE ||
      ma60Distance < DRYUP_SUPPORT_MIN_MA60_DISTANCE ||
      ma60Distance > DRYUP_SUPPORT_MAX_MA60_DISTANCE
    ) {
      continue;
    }

    let quality = 42;
    quality += Math.min(18, surgeVolumeRatio * 3);
    quality += Math.max(0, 14 - Math.abs(pullback - 0.09) * 120);
    quality += Math.max(0, 12 - postAvgVolumeRatio * 18);
    quality += Math.max(0, 10 - recentVolumeRatio * 25);
    quality += recentLowSpread < 0.08 ? 8 : 3;
    quality += supportSignal ? 6 : 0;
    quality += ma20Distance >= 0 ? 5 : 0;

    const candidate = {
      surgeDaysAgo: rows.length - 1 - i,
      surgeGain,
      surgeVolumeRatio,
      surgeTradingValue,
      pullback,
      postAvgVolumeRatio,
      recentVolumeRatio,
      recentLowSpread,
      ma20Distance,
      ma60Distance,
      quality,
    };
    if (
      !best ||
      candidate.surgeDaysAgo > best.surgeDaysAgo ||
      (candidate.surgeDaysAgo === best.surgeDaysAgo && candidate.quality > best.quality)
    ) {
      best = candidate;
    }
  }

  return best;
}

function scoreStock(stock, rows) {
  if (rows.length < MIN_HISTORY_DAYS) return null;
  if (hasRecentTradingHaltOrAbnormalGap(rows)) return null;

  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const avgTradingValue20 = average(rows.slice(-20).map((row) => row.close * row.volume));
  if (last.close < MIN_PRICE || avgTradingValue20 < MIN_AVG_TRADING_VALUE) return null;

  const ma20 = sma(rows, 20);
  const ma60 = sma(rows, 60);
  const ma120 = sma(rows, 120);
  const high52w = highest(rows.slice(-240));
  const recentHigh60 = highest(rows.slice(-60));
  const cupAndHandle = detectCupAndHandle(rows);
  const surgePullbackTail = detectVolumeSurgePullbackTail(rows);
  const strictGoldenCross = detectStrictGoldenCross(rows);
  const maClusterTouch = detectMaClusterTouch(rows);
  const ma120Reclaim = detectMa120ReclaimCompressionBreakout(rows);
  const maClusterVolumeBreakout = detectMaClusterVolumeBreakout(rows);
  const dryUpRise = detectVolumeSpikeBreakoutDryUpRise(rows);
  const dryUpPullbackSupport = detectVolumeSpikeDryUpPullbackSupport(rows);
  const volumeRatio = avgVolume20 ? last.volume / avgVolume20 : 0;
  const categories = [];
  const reasons = [];
  let score = 0;
  const return5d = closeReturn(rows, 5);
  const return20d = closeReturn(rows, 20);
  const distanceFromMa20 = ma20 ? (last.close - ma20) / ma20 : 0;

  if (
    return5d > MAX_5D_RETURN ||
    return20d > MAX_20D_RETURN ||
    distanceFromMa20 > MAX_DISTANCE_FROM_MA20
  ) {
    return null;
  }

  if (!strictGoldenCross && isGoldenCross(rows, 5, 20)) {
    score += 18;
    categories.push('golden_cross_5_20');
    reasons.push('5-day average crossed above 20-day average.');
  }
  if (!strictGoldenCross && isGoldenCross(rows, 20, 60)) {
    score += 24;
    categories.push('golden_cross_20_60');
    reasons.push('20-day average crossed above 60-day average.');
  }
  if (ma20 && ma60 && ma120 && last.close > ma20 && ma20 > ma60 && ma60 > ma120) {
    score += 8;
    categories.push('ma_alignment');
    reasons.push('Price is above aligned 20/60/120-day averages.');
  }
  if (volumeRatio >= 1.5) {
    score += Math.min(18, 8 + volumeRatio * 4);
    categories.push('volume_breakout');
    reasons.push(`Volume is ${volumeRatio.toFixed(1)}x the 20-day average.`);
  }
  if (last.close >= recentHigh60 * 0.995 && prev.close < recentHigh60 * 0.995) {
    score += 14;
    categories.push('recent_high_breakout');
    reasons.push('Price is breaking the recent 60-day high area.');
  }
  if (high52w && last.close >= high52w * 0.85) {
    score += 8;
    categories.push('near_52w_high');
    reasons.push('Price is within 15% of its 52-week high.');
  }
  if (slope(rows, 20, 5) > 0 && slope(rows, 60, 10) > 0) {
    score += 10;
    categories.push('rising_trend');
    reasons.push('20-day and 60-day averages are rising.');
  }
  if (cupAndHandle) {
    score += 30 + Math.min(15, Math.round(cupAndHandle.quality / 5));
    categories.unshift('cup_and_handle');
    reasons.push(
      `Cup-and-handle ${cupAndHandle.setupState}: cup ${cupAndHandle.cupDays}d depth ${(cupAndHandle.cupDepth * 100).toFixed(1)}%, handle ${cupAndHandle.handleDays}d depth ${(cupAndHandle.handleDepth * 100).toFixed(1)}%, pivot distance ${(cupAndHandle.distanceFromBreakout * 100).toFixed(1)}%, breakout volume ${cupAndHandle.breakoutVolumeRatio.toFixed(1)}x handle avg.`,
    );
  }
  if (surgePullbackTail) {
    score += 32 + Math.min(18, Math.round(surgePullbackTail.quality / 6));
    categories.unshift('volume_surge_pullback_tail');
    reasons.push(
      `Volume surge U-base pullback: surge ${surgePullbackTail.surgeDaysAgo}d ago +${(surgePullbackTail.surgeGain * 100).toFixed(1)}% with ${surgePullbackTail.surgeVolumeRatio.toFixed(1)}x volume, max pullback ${(surgePullbackTail.pullback * 100).toFixed(1)}%, current pullback ${(surgePullbackTail.currentPullback * 100).toFixed(1)}%, U-base ${surgePullbackTail.baseDays}d, ${surgePullbackTail.tailCount} lower-tail candles, pullback volume ${(surgePullbackTail.avgPullbackVolumeRatio * 100).toFixed(0)}% of surge volume, support near ${surgePullbackTail.support}.`,
    );
  }
  if (strictGoldenCross) {
    score += 34 + Math.min(24, Math.round(strictGoldenCross.quality / 4));
    categories.unshift('strict_golden_cross');
    categories.push(`golden_cross_${strictGoldenCross.type}`);
    reasons.push(
      `Strict golden cross ${strictGoldenCross.type}: volume ${strictGoldenCross.volumeRatio.toFixed(1)}x, price ${(strictGoldenCross.distanceFromMa20 * 100).toFixed(1)}% above MA20, ${(strictGoldenCross.distanceToResistance * 100).toFixed(1)}% from 60d resistance, 20d base range ${(strictGoldenCross.baseCompression * 100).toFixed(1)}%, MA20 slope ${(strictGoldenCross.ma20Slope * 100).toFixed(1)}%, MA60 slope ${(strictGoldenCross.ma60Slope * 100).toFixed(1)}%.`,
    );
  }
  if (maClusterTouch) {
    score += 30 + Math.min(24, Math.round(maClusterTouch.quality / 4));
    categories.unshift('ma_cluster_touch');
    reasons.push(
      `MA cluster touch: touched ${maClusterTouch.maName} on ${maClusterTouch.touchDate}, touch distance ${(maClusterTouch.touchDistance * 100).toFixed(1)}%, lower-tail ${(maClusterTouch.tailRatio * 100).toFixed(0)}%, MA20/60/120 spread ${(maClusterTouch.clusterSpread * 100).toFixed(1)}%, price ${(maClusterTouch.distanceFromCluster * 100).toFixed(1)}% from cluster center, 20d box ${(maClusterTouch.boxRange20 * 100).toFixed(1)}%, volume ${maClusterTouch.volumeRatio.toFixed(1)}x.`,
    );
  }
  if (ma120Reclaim) {
    score += 34 + Math.min(26, Math.round(ma120Reclaim.quality / 4));
    categories.unshift('ma120_reclaim_compression_breakout');
    reasons.push(
      `MA120 reclaim compression breakout: undercut ${ma120Reclaim.undercutDate} ${(ma120Reclaim.undercut * 100).toFixed(1)}%, reclaimed ${ma120Reclaim.reclaimDays}d later on ${ma120Reclaim.reclaimDate}, base ${ma120Reclaim.baseDays}d range ${(ma120Reclaim.baseRange * 100).toFixed(1)}%, MA spread ${(ma120Reclaim.maSpread * 100).toFixed(1)}%, MA120 slope ${(ma120Reclaim.ma120Slope * 100).toFixed(1)}%, MA60 slope ${(ma120Reclaim.ma60Slope * 100).toFixed(1)}%, MA20 slope ${(ma120Reclaim.ma20Slope * 100).toFixed(1)}%, breakout volume ${ma120Reclaim.volumeRatio.toFixed(1)}x, box distance ${(ma120Reclaim.boxDistance * 100).toFixed(1)}%.`,
    );
  }
  if (maClusterVolumeBreakout) {
    score += 34 + Math.min(26, Math.round(maClusterVolumeBreakout.quality / 4));
    categories.unshift('ma_cluster_volume_breakout');
    reasons.push(
      `MA cluster volume breakout: gain ${(maClusterVolumeBreakout.gain * 100).toFixed(1)}%, volume ${maClusterVolumeBreakout.volumeRatio.toFixed(1)}x, MA spread ${(maClusterVolumeBreakout.maSpread * 100).toFixed(1)}%, price ${(maClusterVolumeBreakout.distanceFromCluster * 100).toFixed(1)}% above cluster center, 20d box ${(maClusterVolumeBreakout.boxRange20 * 100).toFixed(1)}%, cluster touches ${maClusterVolumeBreakout.clusterTouches}, MA120 slope ${(maClusterVolumeBreakout.ma120Slope * 100).toFixed(1)}%.`,
    );
  }
  if (dryUpRise) {
    score += 34 + Math.min(26, Math.round(dryUpRise.quality / 4));
    categories.unshift('volume_spike_breakout_dry_up_rise');
    reasons.push(
      `Volume spike dry-up rise: surge ${dryUpRise.surgeDaysAgo}d ago +${(dryUpRise.surgeGain * 100).toFixed(1)}% with ${dryUpRise.surgeVolumeRatio.toFixed(1)}x volume and ${Math.round(dryUpRise.surgeTradingValue).toLocaleString('en-US')} trading value, max pullback ${(dryUpRise.maxPullback * 100).toFixed(1)}%, runup ${(dryUpRise.runup * 100).toFixed(1)}%, post avg volume ${(dryUpRise.postAvgVolumeRatio * 100).toFixed(0)}% of surge, recent volume ${(dryUpRise.recentVolumeRatio * 100).toFixed(0)}% of surge, low stability ${(dryUpRise.lowStability * 100).toFixed(1)}%.`,
    );
  }
  if (dryUpPullbackSupport) {
    score += 32 + Math.min(26, Math.round(dryUpPullbackSupport.quality / 4));
    categories.unshift('volume_spike_dry_up_pullback_support');
    reasons.push(
      `Volume spike dry-up pullback support: surge ${dryUpPullbackSupport.surgeDaysAgo}d ago +${(dryUpPullbackSupport.surgeGain * 100).toFixed(1)}% with ${dryUpPullbackSupport.surgeVolumeRatio.toFixed(1)}x volume and ${Math.round(dryUpPullbackSupport.surgeTradingValue).toLocaleString('en-US')} trading value, pullback ${(dryUpPullbackSupport.pullback * 100).toFixed(1)}%, post avg volume ${(dryUpPullbackSupport.postAvgVolumeRatio * 100).toFixed(0)}% of surge, recent volume ${(dryUpPullbackSupport.recentVolumeRatio * 100).toFixed(0)}% of surge, low spread ${(dryUpPullbackSupport.recentLowSpread * 100).toFixed(1)}%, MA20 distance ${(dryUpPullbackSupport.ma20Distance * 100).toFixed(1)}%, MA60 distance ${(dryUpPullbackSupport.ma60Distance * 100).toFixed(1)}%.`,
    );
  }

  const oneDayRate = prev.close ? (last.close - prev.close) / prev.close : 0;
  if (oneDayRate > 0.12) {
    score -= 20;
    reasons.push('Penalty: one-day move is already overheated.');
  }

  const hasPrimarySetup =
    categories.includes('cup_and_handle') ||
    categories.includes('volume_surge_pullback_tail') ||
    categories.includes('strict_golden_cross') ||
    categories.includes('ma_cluster_touch') ||
    categories.includes('ma120_reclaim_compression_breakout') ||
    categories.includes('ma_cluster_volume_breakout') ||
    categories.includes('volume_spike_breakout_dry_up_rise') ||
    categories.includes('volume_spike_dry_up_pullback_support') ||
    categories.includes('golden_cross_5_20') ||
    categories.includes('golden_cross_20_60') ||
    categories.includes('recent_high_breakout');
  if (REQUIRE_PATTERN && !categories.includes(REQUIRE_PATTERN)) return null;
  if (!hasPrimarySetup || score < MIN_SCORE) return null;

  const reason = [
    `Auto score ${Math.round(score)}.`,
    ...reasons,
    `Last close ${last.close.toLocaleString('en-US')}, 20-day avg trading value ${Math.round(avgTradingValue20).toLocaleString('en-US')}.`,
  ].join('\n');

  return {
    ticker: stock.ticker,
    name: stock.name,
    market: stock.market,
    buyPrice: last.close,
    targetPrice: Math.round(last.close * (1 + TARGET_RETURN_RATE)),
    score: Math.round(score),
    category: categories[0],
    categories,
    reason,
    currentPrice: last.close,
    sourceDate: last.date,
    avgTradingValue20: Math.round(avgTradingValue20),
    volumeRatio: Number(volumeRatio.toFixed(2)),
  };
}

function makeFeatureItem(stock, rows, group, pattern, title, reason, score) {
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const tradingValue = last.close * last.volume;
  const changeRate = prev?.close ? ((last.close - prev.close) / prev.close) * 100 : 0;
  return {
    ticker: stock.ticker,
    name: stock.name,
    market: stock.market,
    group,
    pattern,
    title,
    reason,
    price: last.close,
    changeRate: Number(changeRate.toFixed(2)),
    score: Math.round(score),
    tradingValue: Math.round(tradingValue),
    volumeRatio: Number((avgVolume20 ? last.volume / avgVolume20 : 0).toFixed(2)),
    sourceDate: last.date,
  };
}

function mergeFeatureReasonTexts(reasons) {
  const seen = new Set();
  const merged = [];
  for (const reason of reasons) {
    const normalized = String(reason || '').replace(/\s+/g, ' ').trim();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    merged.push(normalized);
  }
  return merged.join('\n\n');
}

function mergeFeatureItemsByTicker(items) {
  const byTicker = new Map();
  for (const item of items) {
    const key = item.ticker;
    if (!byTicker.has(key)) {
      byTicker.set(key, {
        ...item,
        patterns: item.pattern ? [item.pattern] : [],
        titles: item.title ? [item.title] : [],
        reasonParts: item.reason ? [item.reason] : [],
      });
      continue;
    }

    const current = byTicker.get(key);
    if (item.score > current.score) {
      current.group = item.group;
      current.pattern = item.pattern;
      current.title = item.title;
      current.price = item.price;
      current.changeRate = item.changeRate;
      current.tradingValue = item.tradingValue;
      current.volumeRatio = item.volumeRatio;
      current.sourceDate = item.sourceDate;
    }
    current.score = Math.max(current.score, item.score);
    if (item.pattern && !current.patterns.includes(item.pattern)) current.patterns.push(item.pattern);
    if (item.title && !current.titles.includes(item.title)) current.titles.push(item.title);
    if (item.reason) current.reasonParts.push(item.reason);
  }

  return Array.from(byTicker.values()).map((item) => {
    const mergedPatterns = item.patterns.filter(Boolean);
    const mergedTitles = item.titles.filter(Boolean);
    const header = mergedTitles.length > 1
      ? `복합 포착: ${mergedTitles.join(', ')}`
      : null;
    const body = mergeFeatureReasonTexts(item.reasonParts);
    return {
      ...item,
      pattern: mergedPatterns[0] || item.pattern,
      title: mergedTitles[0] || item.title,
      reason: header ? `${header}\n${body}` : body,
    };
  });
}

function formatFeatureTradingValue(value) {
  const rounded = Math.round(value || 0);
  if (rounded >= 1000000000000) return `${(rounded / 1000000000000).toFixed(1)}조원`;
  if (rounded >= 100000000) return `${Math.round(rounded / 100000000).toLocaleString('ko-KR')}억원`;
  return `${rounded.toLocaleString('ko-KR')}원`;
}

function formatFeaturePct(value, digits = 1) {
  return `${(value * 100).toFixed(digits)}%`;
}

function buildChartSetupReason(pattern, setup) {
  if (pattern === 'ma20_reclaim') {
    return [
      `최근 ${setup.belowDays}거래일 동안 20일선 아래에 머문 뒤 종가가 20일선을 다시 회복했습니다.`,
      `현재가는 20일선 대비 ${formatFeaturePct(setup.ma20Distance)} 위에 있고, 거래량은 20일 평균 대비 ${setup.volumeRatio.toFixed(1)}배입니다.`,
      `단기 낙폭 이후 반등을 시도하는 관심 구간으로 포착했습니다.`,
    ].join(' ');
  }
  if (pattern === 'prior_high_retest') {
    return [
      `${setup.priorHighAge}거래일 전 고점까지 종가 기준 남은 거리가 ${formatFeaturePct(setup.distanceToHigh)}입니다.`,
      `당일 등락률은 ${formatFeaturePct(setup.oneDayRate)}이고 거래량은 20일 평균 대비 ${setup.volumeRatio.toFixed(1)}배입니다.`,
      `전고점 근처로 다시 접근하는 구간으로 포착했습니다.`,
    ].join(' ');
  }
  if (pattern === 'volume_surge_cooldown') {
    return [
      `${setup.surgeDaysAgo}거래일 전 거래량이 평소보다 ${setup.surgeVolumeRatio.toFixed(1)}배 늘며 ${formatFeaturePct(setup.surgeGain)} 상승했습니다.`,
      `이후 최대 조정은 ${formatFeaturePct(setup.pullback)}였고 현재가는 급등일 종가 대비 ${formatFeaturePct(setup.currentFromSurgeClose)} 위치입니다.`,
      `급등 후 지지 패턴으로 포착했습니다.`,
    ].join(' ');
  }
  if (pattern === 'box_upper_approach') {
    return [
      `최근 ${setup.lookbackDays}거래일 박스권 등락폭은 ${formatFeaturePct(setup.boxRange)}입니다.`,
      `당일 고가 기준 박스권 상단까지 ${formatFeaturePct(setup.distanceToHigh)} 남았고, 거래량은 20일 평균 대비 ${setup.volumeRatio.toFixed(1)}배입니다.`,
      `박스권 상단 테스트 가능성이 높아지는 구간으로 포착했습니다.`,
    ].join(' ');
  }
  if (pattern === 'volume_surge_pullback_tail') {
    return [
      `${setup.surgeDaysAgo}거래일 전 거래량이 평소보다 ${setup.surgeVolumeRatio.toFixed(1)}배 늘며 ${formatFeaturePct(setup.surgeGain)} 상승했습니다.`,
      `이후 최대 눌림은 ${formatFeaturePct(setup.pullback)}였고 현재 눌림은 ${formatFeaturePct(setup.currentPullback)} 수준입니다.`,
      `${setup.baseDays}거래일 동안 U자형 베이스를 만들며 아래꼬리 캔들이 ${setup.tailCount}회 확인됐습니다.`,
      `눌림 구간 거래량은 급등일 대비 ${formatFeaturePct(setup.avgPullbackVolumeRatio, 0)} 수준으로 줄었고, ${Math.round(setup.support).toLocaleString('ko-KR')}원 부근 지지를 확인했습니다.`,
    ].join(' ');
  }
  if (pattern === 'volume_spike_breakout_dry_up_rise') {
    return [
      `${setup.surgeDaysAgo}거래일 전 거래량이 ${setup.surgeVolumeRatio.toFixed(1)}배 늘며 ${formatFeaturePct(setup.surgeGain)} 상승했습니다.`,
      `급등 이후 최대 눌림은 ${formatFeaturePct(setup.maxPullback)}였고, 이후 반등 폭은 ${formatFeaturePct(setup.runup)}입니다.`,
      `급등 후 평균 거래량은 급등일 대비 ${formatFeaturePct(setup.postAvgVolumeRatio, 0)}, 최근 거래량은 ${formatFeaturePct(setup.recentVolumeRatio, 0)}로 줄었습니다.`,
      `저점 안정도는 ${formatFeaturePct(setup.lowStability)}로 집계돼, 급등 후 거래량 감소하며 상승 패턴으로 포착했습니다.`,
    ].join(' ');
  }
  if (pattern === 'volume_spike_dry_up_pullback_support') {
    return [
      `${setup.surgeDaysAgo}거래일 전 거래량이 ${setup.surgeVolumeRatio.toFixed(1)}배 늘며 ${formatFeaturePct(setup.surgeGain)} 상승했습니다.`,
      `이후 눌림 폭은 ${formatFeaturePct(setup.pullback)}이고, 급등 후 평균 거래량은 급등일 대비 ${formatFeaturePct(setup.postAvgVolumeRatio, 0)} 수준입니다.`,
      `최근 거래량은 급등일 대비 ${formatFeaturePct(setup.recentVolumeRatio, 0)}로 줄었고 저점 변동폭은 ${formatFeaturePct(setup.recentLowSpread)}입니다.`,
      `현재가는 20일선 대비 ${formatFeaturePct(setup.ma20Distance)}, 60일선 대비 ${formatFeaturePct(setup.ma60Distance)} 위치에 있어 급등 후 거래량 감소하며 지지 패턴으로 포착했습니다.`,
    ].join(' ');
  }
  return `차트 패턴 점수 ${Math.round(setup.quality)}점으로 특징주에 포착됐습니다.`;
}

function detectMa20ReclaimFeature(rows) {
  if (rows.length < 45) return null;
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const ma20 = sma(rows, 20);
  const prevMa20 = sma(rows, 20, 1);
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  if (!ma20 || !prevMa20 || !avgVolume20) return null;
  if (last.close <= ma20 || prev.close > prevMa20) return null;

  const ma20Distance = (last.close - ma20) / ma20;
  const oneDayRate = prev.close ? (last.close - prev.close) / prev.close : 0;
  const volumeRatio = last.volume / avgVolume20;
  const recent = rows.slice(-8, -1);
  const belowDays = recent.filter((row, idx) => {
    const offset = recent.length - idx;
    const ma = sma(rows, 20, offset);
    return ma && row.close < ma;
  }).length;
  if (belowDays < 2) return null;
  if (ma20Distance > 0.08 || oneDayRate < 0.005 || oneDayRate > 0.11 || volumeRatio < 1.05) return null;

  let quality = 48;
  quality += Math.min(16, volumeRatio * 5);
  quality += Math.max(0, 14 - Math.abs(ma20Distance - 0.025) * 220);
  quality += Math.min(12, oneDayRate * 180);
  quality += Math.min(10, belowDays * 2);
  return { belowDays, ma20Distance, oneDayRate, volumeRatio, quality };
}

function detectPriorHighRetestFeature(rows) {
  if (rows.length < 80) return null;
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const lookbackDays = 60;
  const prior = rows.slice(-(lookbackDays + 1), -1);
  const priorHighIndex = maxIndex(prior, 'high');
  const priorHigh = prior[priorHighIndex]?.high;
  const priorHighAge = prior.length - priorHighIndex;
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  if (!priorHigh || !avgVolume20) return null;
  const distanceToHigh = (priorHigh - last.close) / priorHigh;
  const oneDayRate = prev.close ? (last.close - prev.close) / prev.close : 0;
  const volumeRatio = last.volume / avgVolume20;
  if (priorHighAge < 5) return null;
  if (last.high >= priorHigh || distanceToHigh < 0.005 || distanceToHigh > 0.06) return null;
  if (oneDayRate < 0.01 || oneDayRate > 0.12 || volumeRatio < 1.0) return null;
  if (prev.close > last.close) return null;
  if (closePositionRatio(last) < 0.65) return null;

  let quality = 46;
  quality += Math.max(0, 20 - distanceToHigh * 260);
  quality += Math.min(14, volumeRatio * 4);
  quality += Math.min(12, oneDayRate * 160);
  return { lookbackDays, priorHigh, priorHighAge, distanceToHigh, oneDayRate, volumeRatio, quality };
}

function detectVolumeSurgeCooldownFeature(rows) {
  if (rows.length < 70) return null;
  const last = rows[rows.length - 1];
  const start = Math.max(20, rows.length - 24);
  let best = null;

  for (let i = start; i < rows.length - 3; i += 1) {
    const surge = rows[i];
    const previous = rows[i - 1];
    const avgVolBefore = average(rows.slice(Math.max(0, i - 20), i).map((row) => row.volume));
    const surgeGain = previous.close ? (surge.close - previous.close) / previous.close : 0;
    const surgeVolumeRatio = avgVolBefore ? surge.volume / avgVolBefore : 0;
    const surgeTradingValue = surge.close * surge.volume;
    if (
      surgeGain < SURGE_MIN_GAIN ||
      surgeVolumeRatio < SURGE_MIN_VOLUME_RATIO ||
      surgeTradingValue < FEATURE_MIN_TRADING_VALUE
    ) continue;

    const after = rows.slice(i + 1);
    const afterLow = lowest(after, 'low');
    const afterCloseLow = lowest(after, 'close');
    const afterHigh = highest(after, 'high');
    if (afterCloseLow < previous.close) continue;
    const pullback = (surge.high - afterLow) / surge.high;
    const currentFromSurgeClose = surge.close ? (last.close - surge.close) / surge.close : 0;
    if (pullback < 0.02 || pullback > 0.22) continue;
    if (last.close < surge.close * 0.9 || last.close > surge.high * 1.02) continue;
    if (afterHigh > surge.high * 1.05) continue;

    const recentAvgVolume = average(after.slice(-3).map((row) => row.volume));
    const recentVolumeRatio = recentAvgVolume / surge.volume;
    if (recentVolumeRatio > 0.85) continue;

    let quality = 45;
    quality += Math.min(18, surgeVolumeRatio * 3);
    quality += Math.max(0, 16 - Math.abs(pullback - 0.09) * 140);
    quality += Math.max(0, 12 - Math.abs(currentFromSurgeClose) * 120);
    quality += Math.max(0, 8 - recentVolumeRatio * 8);
    const candidate = {
      surgeDaysAgo: rows.length - 1 - i,
      surgeGain,
      surgeVolumeRatio,
      pullback,
      currentFromSurgeClose,
      recentVolumeRatio,
      quality,
    };
    if (!best || candidate.quality > best.quality) best = candidate;
  }
  return best;
}

function detectBoxUpperApproachFeature(rows) {
  if (rows.length < 70) return null;
  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const lookbackDays = 40;
  const box = rows.slice(-(lookbackDays + 1), -1);
  const boxHigh = highest(box, 'high');
  const boxLow = lowest(box, 'low');
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  if (!boxHigh || !boxLow || !avgVolume20) return null;
  const boxRange = (boxHigh - boxLow) / boxLow;
  const distanceToHigh = (boxHigh - last.high) / boxHigh;
  const oneDayRate = prev.close ? (last.close - prev.close) / prev.close : 0;
  const volumeRatio = last.volume / avgVolume20;
  const position = (last.close - boxLow) / (boxHigh - boxLow);
  if (boxRange < 0.08 || boxRange > 0.35) return null;
  if (last.high >= boxHigh || position < 0.72 || distanceToHigh < 0.003 || distanceToHigh > 0.07) return null;
  if (oneDayRate < 0 || oneDayRate > 0.1 || volumeRatio < 0.9) return null;

  let quality = 44;
  quality += Math.max(0, 18 - distanceToHigh * 220);
  quality += Math.min(12, volumeRatio * 4);
  quality += Math.min(10, position * 10);
  quality += Math.min(8, oneDayRate * 120);
  return { lookbackDays, boxHigh, boxLow, boxRange, distanceToHigh, oneDayRate, volumeRatio, quality };
}

function buildMarketFeatureStocks(stock, rows) {
  if (rows.length < MIN_HISTORY_DAYS) return [];
  if (hasRecentTradingHaltOrAbnormalGap(rows)) return [];

  const last = rows[rows.length - 1];
  const prev = rows[rows.length - 2];
  const avgVolume20 = sma(rows, 20, 0, 'volume') || 0;
  const avgTradingValue20 = average(rows.slice(-20).map((row) => row.close * row.volume));
  const tradingValue = last.close * last.volume;
  const valueRatio = avgTradingValue20 ? tradingValue / avgTradingValue20 : 0;
  const volumeRatio = avgVolume20 ? last.volume / avgVolume20 : 0;
  const oneDayRate = prev?.close ? (last.close - prev.close) / prev.close : 0;
  const previous60High = highest(rows.slice(-61, -1), 'high');
  const previous240High = highest(rows.slice(-241, -1), 'high');
  if (last.close < MIN_PRICE || tradingValue < FEATURE_MIN_TRADING_VALUE) return [];

  const items = [];
  items.push(
    makeFeatureItem(
      stock,
      rows,
      'top_trading_value',
      'top_trading_value',
      '거래대금 상위',
      `오늘 거래대금은 ${formatFeatureTradingValue(tradingValue)}로 집계됐습니다. 최근 20거래일 평균 거래대금 대비 ${valueRatio.toFixed(1)}배 수준이라 거래대금 상위 종목으로 포착했습니다.`,
      Math.min(100, 45 + Math.log10(Math.max(1, tradingValue / 100000000)) * 12 + Math.min(20, valueRatio * 3)),
    ),
  );

  if (oneDayRate >= FEATURE_GAINER_MIN_RETURN) {
    items.push(
      makeFeatureItem(
        stock,
        rows,
        'gainers',
        'gainers',
        '급등주',
        `당일 주가가 ${formatFeaturePct(oneDayRate)} 상승했습니다. 거래대금은 ${formatFeatureTradingValue(tradingValue)}로 동반 증가해 급등주로 포착했습니다.`,
        45 + Math.min(35, oneDayRate * 220) + Math.min(20, valueRatio * 4),
      ),
    );
  }

  if (valueRatio >= FEATURE_VALUE_SPIKE_RATIO && oneDayRate >= FEATURE_VOLUME_SPIKE_MIN_RETURN) {
    items.push(
      makeFeatureItem(
        stock,
        rows,
        'volume_spike',
        'trading_value_spike',
        '거래량/거래대금 급증',
        `거래대금이 최근 20거래일 평균 대비 ${valueRatio.toFixed(1)}배로 늘었습니다. 거래량은 ${volumeRatio.toFixed(1)}배, 당일 등락률은 ${formatFeaturePct(oneDayRate)}로 거래량과 가격 움직임이 함께 포착됐습니다.`,
        42 + Math.min(32, valueRatio * 8) + Math.min(18, volumeRatio * 4) + Math.min(8, oneDayRate * 80),
      ),
    );
  }

  if (
    oneDayRate >= FEATURE_HIGH_BREAKOUT_MIN_RETURN &&
    previous60High &&
    last.close >= previous60High * 1.005
  ) {
    const isYearHigh = previous240High && last.close >= previous240High * 1.005;
    // 라벨만 다르고 설명이 똑같으면 사용자 입장에선 두 카테고리가 같아 보이므로,
    // 신고가는 240거래일(≈1년) 기준을, 전고점은 60거래일 기준을 본문에 인용한다.
    const refHigh = isYearHigh ? previous240High : previous60High;
    const refLabel = isYearHigh ? '약 1년(240거래일)' : '최근 60거래일';
    const breakoutPct = (((last.close / refHigh) - 1) * 100).toFixed(1);
    items.push(
      makeFeatureItem(
        stock,
        rows,
        'high_breakout',
        isYearHigh ? 'new_52w_high' : 'prior_high_breakout',
        isYearHigh ? '신고가 돌파' : '전고점 돌파',
        isYearHigh
          ? `종가가 ${refLabel} 고점을 ${breakoutPct}% 상회하며 신고가를 새로 썼습니다. 거래량도 20거래일 평균 대비 ${volumeRatio.toFixed(1)}배로 늘어 신고가 돌파 흐름으로 포착했습니다.`
          : `종가가 ${refLabel} 고점을 ${breakoutPct}% 넘어섰습니다. 거래량도 20거래일 평균 대비 ${volumeRatio.toFixed(1)}배로 늘어 중기 전고점 돌파 흐름으로 포착했습니다.`,
        50 + (isYearHigh ? 15 : 5) + Math.min(20, volumeRatio * 5) + Math.min(15, oneDayRate * 100),
      ),
    );
  }

  const chartSetups = [
    ['ma20_reclaim', '20일선 회복', detectMa20ReclaimFeature(rows)],
    ['prior_high_retest', '전고점 재도전', detectPriorHighRetestFeature(rows)],
    ['volume_surge_cooldown', '급등 후 재정비 구간', detectVolumeSurgeCooldownFeature(rows)],
    ['box_upper_approach', '박스권 상단 접근', detectBoxUpperApproachFeature(rows)],
    ['volume_surge_pullback_tail', '급등 뒤 조정 후 반등 시도', detectVolumeSurgePullbackTail(rows)],
    ['volume_spike_breakout_dry_up_rise', '급등 후 재정비 구간', detectVolumeSpikeBreakoutDryUpRise(rows)],
    ['volume_spike_dry_up_pullback_support', '급등 후 재정비 구간', detectVolumeSpikeDryUpPullbackSupport(rows)],
  ];
  for (const [pattern, title, setup] of chartSetups) {
    if (!setup) continue;
    items.push(
      makeFeatureItem(
        stock,
        rows,
        'chart_capture',
        pattern,
        title,
        buildChartSetupReason(pattern, setup),
        60 + Math.min(30, setup.quality / 5),
      ),
    );
  }

  return items;
}

async function mapLimit(items, limit, worker) {
  const results = [];
  let cursor = 0;
  const runners = Array.from({ length: limit }, async () => {
    while (cursor < items.length) {
      const index = cursor;
      cursor += 1;
      try {
        const result = await worker(items[index], index);
        if (result) results.push(result);
      } catch (error) {
        console.warn(`[warn] ${items[index].ticker} failed: ${error.message}`);
      }
    }
  });
  await Promise.all(runners);
  return results;
}

function initFirebase() {
  if (admin.apps.length) return admin.firestore();
  let serviceAccount;
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  } else {
    serviceAccount = require('./service-account.json');
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  return admin.firestore();
}

async function uploadPicks(picks, dateKey) {
  if (DRY_RUN) {
    console.log(`[dry-run] would upload ${picks.length} picks`);
    const outDir = path.join(__dirname, 'out', 'auto-picks');
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(
      path.join(outDir, `${dateKey}.json`),
      JSON.stringify(picks, null, 2),
      'utf8',
    );
    const markdown = [
      `# Auto Stock Picks ${dateKey}`,
      '',
      ...picks.flatMap((pick, index) => [
        `## ${index + 1}. ${pick.name} (${pick.ticker})`,
        '',
        `- Score: ${pick.score}`,
        `- Category: ${pick.category}`,
        `- Buy price: ${pick.buyPrice.toLocaleString('en-US')}`,
        `- Target price: ${pick.targetPrice.toLocaleString('en-US')}`,
        `- Volume ratio: ${pick.volumeRatio}x`,
        `- 20-day avg trading value: ${pick.avgTradingValue20.toLocaleString('en-US')}`,
        '',
        pick.reason,
        '',
      ]),
    ].join('\n');
    fs.writeFileSync(path.join(outDir, `${dateKey}.md`), `\uFEFF${markdown}`, 'utf8');
    for (const pick of picks) {
      console.log(
        `[pick] ${pick.ticker} ${pick.name} score=${pick.score} category=${pick.category} price=${pick.buyPrice}`,
      );
    }
    console.log(`[dry-run] wrote ${path.join(outDir, `${dateKey}.md`)}`);
    return;
  }

  const db = initFirebase();
  const batch = db.batch();
  let createdCount = 0;
  for (const pick of picks) {
    const docId = `auto_${dateKey}_${pick.ticker}`;
    const ref = db.collection('stock_picks').doc(docId);
    const exists = await ref.get();
    if (exists.exists) continue;
    createdCount += 1;
    batch.set(ref, {
      ticker: pick.ticker,
      name: pick.name,
      buyPrice: pick.buyPrice,
      targetPrice: pick.targetPrice,
      reason: pick.reason,
      category: pick.category,
      categories: pick.categories,
      market: pick.market,
      isPremium: false,
      createdAt: admin.firestore.Timestamp.fromDate(new Date()),
      currentPrice: pick.currentPrice,
      status: 'active',
      autoGenerated: true,
      autoPickKey: docId,
      autoScore: pick.score,
      sourceDate: pick.sourceDate,
      avgTradingValue20: pick.avgTradingValue20,
      volumeRatio: pick.volumeRatio,
    });
  }

  if (createdCount > 0) await batch.commit();
  console.log(`[done] uploaded ${createdCount}/${picks.length} picks`);

  if (createdCount > 0 && SEND_FCM) {
    await admin.messaging().send({
      topic: FCM_TOPIC,
      notification: {
        title: 'New auto stock picks',
        body: `${createdCount} chart-screened picks were uploaded.`,
      },
      data: {
        type: 'new_pick',
        source: 'auto_stock_picker',
      },
    });
    console.log(`[done] sent FCM topic=${FCM_TOPIC}`);
  }
}

function selectFeatureStocks(items) {
  const buckets = new Map();
  for (const item of items) {
    const key = item.group === 'chart_capture' ? `${item.group}:${item.pattern}` : item.group;
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(item);
  }

  const selected = [];
  for (const [bucketKey, list] of buckets.entries()) {
    const sorted = list.sort((a, b) => {
      if (bucketKey === 'top_trading_value') {
        return b.tradingValue - a.tradingValue;
      }
      return b.score - a.score || b.tradingValue - a.tradingValue;
    });
    // Dedup within each group/pattern bucket only — cross-group duplicates are intentional
    const deduped = mergeFeatureItemsByTicker(sorted);
    selected.push(...deduped.slice(0, FEATURE_MAX_PER_GROUP));
  }
  return selected.sort((a, b) => b.score - a.score || b.tradingValue - a.tradingValue);
}

function parseKstSourceDate(value) {
  const raw = String(value || '').trim();
  const match = raw.match(/^(\d{4})-?(\d{2})-?(\d{2})$/);
  if (!match) return new Date();
  const [, year, month, day] = match;
  return new Date(`${year}-${month}-${day}T12:00:00+09:00`);
}

async function uploadMarketFeatureStocks(items, dateKey) {
  if (DRY_RUN) {
    console.log(`[dry-run] would upload ${items.length} market feature stocks`);
    const outDir = path.join(__dirname, 'out', 'market-features');
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(
      path.join(outDir, `${dateKey}.json`),
      JSON.stringify(items, null, 2),
      'utf8',
    );
    const markdown = [
      `# Market Feature Stocks ${dateKey}`,
      '',
      ...items.flatMap((item, index) => [
        `## ${index + 1}. ${item.name} (${item.ticker})`,
        '',
        `- Group: ${item.group}`,
        `- Pattern: ${item.pattern}`,
        `- Score: ${item.score}`,
        `- Change: ${item.changeRate}%`,
        `- Trading value: ${item.tradingValue.toLocaleString('en-US')}`,
        `- Volume ratio: ${item.volumeRatio}x`,
        '',
        item.reason,
        '',
      ]),
    ].join('\n');
    fs.writeFileSync(path.join(outDir, `${dateKey}.md`), `\uFEFF${markdown}`, 'utf8');
    for (const item of items) {
      console.log(
        `[feature] ${item.ticker} ${item.name} group=${item.group} pattern=${item.pattern} score=${item.score}`,
      );
    }
    console.log(`[dry-run] wrote ${path.join(outDir, `${dateKey}.md`)}`);
    return;
  }

  const db = initFirebase();
  const batch = db.batch();
  let writeCount = 0;
  let cooldownSkipped = 0;
  for (const item of items) {
    // Cooldown: prevent the same ticker/group from being repeatedly uploaded on consecutive days.
    if (FEATURE_COOLDOWN_DAYS > 0) {
      const sourceDate = parseKstSourceDate(item.sourceDate);
      const cutoff = new Date(sourceDate);
      cutoff.setDate(cutoff.getDate() - FEATURE_COOLDOWN_DAYS);
      const recentSnap = await db
        .collection('market_feature_stocks')
        .where('ticker', '==', item.ticker)
        .where('group', '==', item.group)
        .where('sourceDate', '>=', admin.firestore.Timestamp.fromDate(cutoff))
        .where('sourceDate', '<', admin.firestore.Timestamp.fromDate(sourceDate))
        .limit(1)
        .get();
      if (!recentSnap.empty) {
        cooldownSkipped += 1;
        continue;
      }
    }

    const docId = `${dateKey}_${item.group}_${item.pattern}_${item.ticker}`;
    const ref = db.collection('market_feature_stocks').doc(docId);
    batch.set(
      ref,
      {
        ...item,
        createdAt: admin.firestore.Timestamp.fromDate(new Date()),
        sourceDate: admin.firestore.Timestamp.fromDate(parseKstSourceDate(item.sourceDate)),
      },
      { merge: true },
    );
    writeCount += 1;
  }
  if (writeCount > 0) await batch.commit();
  console.log(`[done] uploaded ${writeCount} market feature stocks (cooldownSkipped=${cooldownSkipped})`);
}

async function main() {
  const endDate = resolveEndDate();
  const dateKey = formatYmd(endDate, '-');
  let stocks = await loadStocks();
  if (MAX_STOCKS > 0) stocks = stocks.slice(0, MAX_STOCKS);

  console.log(`[start] stocks=${stocks.length} date=${dateKey} dryRun=${DRY_RUN}`);
  if (String(process.env.DEBUG_VOLUME_PULLBACK || '0') === '1') {
    const counts = {
      histories: 0,
      surge: 0,
      noHighBreak: 0,
      pullback: 0,
      dropLeg: 0,
      uBase: 0,
      bounce: 0,
      tails: 0,
      volume: 0,
      support: 0,
      final: 0,
    };
    await mapLimit(stocks, CONCURRENCY, async (stock) => {
      const rows = await fetchHistory(stock.ticker, endDate);
      if (rows.length < 80) return;
      counts.histories += 1;
      const last = rows[rows.length - 1];
      const start = Math.max(20, rows.length - SURGE_LOOKBACK_DAYS - 1);
      for (let i = start; i < rows.length - 3; i += 1) {
        const surge = rows[i];
        const previous = rows[i - 1];
        const avgVolBefore = average(rows.slice(Math.max(0, i - 20), i).map((row) => row.volume));
        const gain = previous.close ? (surge.close - previous.close) / previous.close : 0;
        const volumeRatio = avgVolBefore ? surge.volume / avgVolBefore : 0;
        const closeNearHigh = closePositionRatio(surge) >= 0.65;
        if (gain < SURGE_MIN_GAIN || volumeRatio < SURGE_MIN_VOLUME_RATIO || !closeNearHigh) continue;
        counts.surge += 1;
        const after = rows.slice(i + 1);
        if (after.length < 3 || after.length > SURGE_LOOKBACK_DAYS) continue;
        if (highest(after, 'high') > surge.high * 1.003) continue;
        counts.noHighBreak += 1;
        const afterLow = lowest(after, 'low');
        const pullback = (surge.high - afterLow) / surge.high;
        const closePullback = (surge.close - afterLow) / surge.close;
        const targetPullbackMin = Math.max(PULLBACK_MIN, PULLBACK_TARGET - PULLBACK_TOLERANCE);
        const targetPullbackMax = Math.min(PULLBACK_MAX, PULLBACK_TARGET + PULLBACK_TOLERANCE);
        if (pullback < targetPullbackMin || pullback > targetPullbackMax) continue;
        if (closePullback < targetPullbackMin * 0.85) continue;
        if (afterLow < surge.low * 0.96) continue;
        counts.pullback += 1;
        const lowIndexAfterSurge = after.findIndex((row) => row.low === afterLow);
        if (lowIndexAfterSurge < MIN_DROP_DAYS_AFTER_SURGE) continue;
        const dropLeg = after.slice(0, lowIndexAfterSurge + 1);
        const lowerCloses = dropLeg.filter((row, idx) => idx > 0 && row.close < dropLeg[idx - 1].close).length;
        if (lowerCloses < 2) continue;
        counts.dropLeg += 1;
        const rightRecovery = after.slice(lowIndexAfterSurge);
        if (rightRecovery.length < U_BASE_MIN_DAYS) continue;
        const baseZone = rightRecovery.filter((row) => row.low <= afterLow * (1 + U_BASE_ZONE_PCT));
        if (baseZone.length < U_BASE_MIN_DAYS) continue;
        counts.uBase += 1;
        const lastCloseFromLow = afterLow ? (last.close - afterLow) / afterLow : 0;
        const currentPullback = (surge.high - last.close) / surge.high;
        if (lastCloseFromLow < MIN_BOUNCE_FROM_PULLBACK_LOW || lastCloseFromLow > MAX_BOUNCE_FROM_PULLBACK_LOW) continue;
        if (currentPullback < targetPullbackMin * 0.7) continue;
        if (last.close > surge.close * 0.96) continue;
        counts.bounce += 1;
        const tailWindow = after.slice(lowIndexAfterSurge).slice(-LOWER_TAIL_WINDOW_DAYS);
        const tailCandles = tailWindow.filter((row) => {
          const bodyRatio = Math.abs(row.close - row.open) / Math.max(1, row.high - row.low);
          return (
            row.low <= afterLow * (1 + U_BASE_ZONE_PCT) &&
            lowerTailRatio(row) >= LOWER_TAIL_MIN_RATIO &&
            closePositionRatio(row) >= LOWER_TAIL_MIN_CLOSE_POSITION &&
            bodyRatio <= LOWER_TAIL_MAX_BODY_RATIO
          );
        });
        if (tailCandles.length < LOWER_TAIL_MIN_COUNT) continue;
        counts.tails += 1;
        const avgPullbackVolume = average(after.slice(0, -1).map((row) => row.volume));
        if (avgPullbackVolume > surge.volume * 0.65) continue;
        counts.volume += 1;
        const ma20 = sma(rows, 20);
        const ma60 = sma(rows, 60);
        const supportNearMa20 = ma20 ? Math.abs(last.close - ma20) / ma20 <= 0.08 || afterLow <= ma20 * 1.04 : false;
        const supportNearMa60 = ma60 ? Math.abs(last.close - ma60) / ma60 <= 0.08 || afterLow <= ma60 * 1.04 : false;
        if (!supportNearMa20 && !supportNearMa60) continue;
        counts.support += 1;
        counts.final += 1;
      }
    });
    console.log('[debug]', JSON.stringify(counts, null, 2));
    return;
  }
  if (MARKET_FEATURES) {
    const featureItems = await mapLimit(stocks, CONCURRENCY, async (stock, index) => {
      if ((index + 1) % 100 === 0) {
        console.log(`[progress] ${index + 1}/${stocks.length}`);
      }
      const rows = await fetchHistory(stock.ticker, endDate);
      return buildMarketFeatureStocks(stock, rows);
    });
    const allFeatures = featureItems.flat();
    const sameDateFeatures = allFeatures.filter((item) => normalizeDateKey(item.sourceDate) === normalizeDateKey(dateKey));
    const filteredFeatures = FEATURE_GROUP
      ? sameDateFeatures.filter((item) => item.group === FEATURE_GROUP)
      : sameDateFeatures;
    const skippedByDate = allFeatures.length - sameDateFeatures.length;
    const selected = selectFeatureStocks(filteredFeatures);
    console.log(
      `[done] featureCandidates=${allFeatures.length} skippedByDate=${skippedByDate} selected=${selected.length}`,
    );
    await uploadMarketFeatureStocks(selected, dateKey);
    return;
  }
  const scored = await mapLimit(stocks, CONCURRENCY, async (stock, index) => {
    if ((index + 1) % 100 === 0) {
      console.log(`[progress] ${index + 1}/${stocks.length}`);
    }
    const rows = await fetchHistory(stock.ticker, endDate);
    return scoreStock(stock, rows);
  });

  const picks = scored
    .sort((a, b) => b.score - a.score || b.avgTradingValue20 - a.avgTradingValue20)
    .slice(0, MAX_PICKS);

  console.log(`[done] candidates=${scored.length} selected=${picks.length}`);
  await uploadPicks(picks, dateKey);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
