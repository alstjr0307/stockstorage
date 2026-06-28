// ── 경제·실적·IPO 캘린더 자동 수집 ──────────────────────────────────────────
// 데이터 소스 (모두 무료):
//   - 실적/IPO: Finnhub  (https://finnhub.io)  무료 키, 60req/분
//   - 거시지표 : FRED     (https://fred.stlouisfed.org) 미 연준 공식, 무료 키
// 저장 위치: market_calendar/{eventId}  (읽기 공개, 쓰기 서버 전용)
// index.js 의 onSchedule 래퍼에서 호출한다 (runAiBriefGeneration 패턴과 동일).

const axios = require('axios');

const FINNHUB_BASE = 'https://finnhub.io/api/v1';
const FRED_BASE = 'https://api.stlouisfed.org/fred';

// 향후 며칠치를 수집할지
const WINDOW_DAYS = 21;

// 한국 투자자 관심이 큰 미국 대형주 — 실적은 항상 포함
const MEGA_CAP_SYMBOLS = new Set([
  'AAPL', 'MSFT', 'NVDA', 'GOOGL', 'GOOG', 'AMZN', 'META', 'TSLA', 'AVGO', 'AMD',
  'NFLX', 'INTC', 'MU', 'QCOM', 'ARM', 'PLTR', 'COIN', 'SMCI', 'TSM', 'ASML',
  'JPM', 'BAC', 'LLY', 'UNH', 'V', 'MA', 'DIS', 'BA', 'KO', 'PEP', 'WMT', 'COST',
]);

// FRED 릴리스 이름 → 한국어 라벨 + 중요도. 여기 매칭되는 핵심 지표만 수집한다.
const FRED_RELEASE_MAP = [
  { match: /consumer price index/i, label: '미국 CPI (소비자물가)', importance: 3 },
  { match: /employment situation/i, label: '미국 고용보고서', importance: 3 },
  { match: /personal income and outlays/i, label: '미국 PCE 물가', importance: 3 },
  { match: /gross domestic product/i, label: '미국 GDP', importance: 2 },
  { match: /producer price index/i, label: '미국 PPI (생산자물가)', importance: 2 },
  { match: /advance monthly sales for retail/i, label: '미국 소매판매', importance: 2 },
  { match: /job openings and labor turnover/i, label: '미국 JOLTS (구인)', importance: 2 },
  { match: /^industrial production/i, label: '미국 산업생산', importance: 1 },
  { match: /university of michigan/i, label: '미시간대 소비자심리', importance: 1 },
];

// ── 유틸 ────────────────────────────────────────────────────────────────────
function ymd(date, tz = 'America/New_York') {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(date);
}

function addDays(date, n) {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + n);
  return d;
}

function numOrNull(v) {
  const n = Number(v);
  return Number.isFinite(n) && n !== 0 ? n : null;
}

function dateToTimestamp(dateStr) {
  // 'YYYY-MM-DD' → 정오 UTC (정렬·D-1 계산용 기준점)
  return new Date(`${dateStr}T12:00:00Z`);
}

// ── 실적 (Finnhub) ──────────────────────────────────────────────────────────
async function fetchEarnings(finnhubKey, from, to) {
  const { data } = await axios.get(`${FINNHUB_BASE}/calendar/earnings`, {
    params: { from, to, token: finnhubKey },
    timeout: 20000,
  });
  const list = Array.isArray(data?.earningsCalendar) ? data.earningsCalendar : [];
  const events = [];
  for (const e of list) {
    const symbol = String(e.symbol || '').trim().toUpperCase();
    if (!symbol || !e.date) continue;
    const rev = Number(e.revenueEstimate) || 0;
    const isMega = MEGA_CAP_SYMBOLS.has(symbol);
    // 메가캡이거나 매출 추정 5B 이상인 대형주만 (쓰기량 제한)
    if (!isMega && rev < 5e9) continue;
    const importance = isMega ? 3 : rev >= 2e10 ? 2 : 1;
    const hour = e.hour === 'bmo' ? '장전' : e.hour === 'amc' ? '장마감 후' : null;
    events.push({
      id: `earnings_${e.date}_${symbol}`,
      type: 'earnings',
      country: 'US',
      date: e.date,
      symbol,
      name: symbol,
      title: `${symbol} 실적 발표`,
      importance,
      extra: {
        hour,
        epsEstimate: numOrNull(e.epsEstimate),
        revenueEstimate: rev || null,
        quarter: e.quarter ?? null,
        year: e.year ?? null,
      },
      source: 'finnhub',
    });
  }
  return events;
}

// ── IPO (Finnhub) ───────────────────────────────────────────────────────────
async function fetchIpo(finnhubKey, from, to) {
  const { data } = await axios.get(`${FINNHUB_BASE}/calendar/ipo`, {
    params: { from, to, token: finnhubKey },
    timeout: 20000,
  });
  const list = Array.isArray(data?.ipoCalendar) ? data.ipoCalendar : [];
  const events = [];
  for (const e of list) {
    const symbol = String(e.symbol || '').trim().toUpperCase();
    const name = String(e.name || '').trim();
    if (!e.date || (!symbol && !name)) continue;
    events.push({
      id: `ipo_${e.date}_${symbol || name.replace(/[^a-zA-Z0-9]/g, '').slice(0, 20)}`,
      type: 'ipo',
      country: 'US',
      date: e.date,
      symbol: symbol || null,
      name: name || symbol,
      title: `${name || symbol} 상장 (IPO)`,
      importance: 1,
      extra: {
        exchange: e.exchange || null,
        priceRange: e.price || null,
        numberOfShares: numOrNull(e.numberOfShares),
        status: e.status || null,
      },
      source: 'finnhub',
    });
  }
  return events;
}

// ── 거시지표 (FRED 릴리스 일정) ──────────────────────────────────────────────
async function fetchEconomic(fredKey, from, to) {
  const { data } = await axios.get(`${FRED_BASE}/releases/dates`, {
    params: {
      api_key: fredKey,
      file_type: 'json',
      include_release_dates_with_no_data: 'true', // 미래 예정일 포함
      sort_order: 'asc',
      realtime_start: from,
      realtime_end: '9999-12-31',
    },
    timeout: 20000,
  });
  const list = Array.isArray(data?.release_dates) ? data.release_dates : [];
  const events = [];
  const seen = new Set();
  for (const r of list) {
    const date = r.date;
    if (!date || date < from || date > to) continue;
    const name = String(r.release_name || '');
    const matched = FRED_RELEASE_MAP.find((x) => x.match.test(name));
    if (!matched) continue;
    const id = `economic_${date}_${r.release_id ?? matched.label.length}`;
    if (seen.has(id)) continue;
    seen.add(id);
    events.push({
      id,
      type: 'economic',
      country: 'US',
      date,
      symbol: null,
      name: matched.label,
      title: `${matched.label} 발표`,
      importance: matched.importance,
      extra: { releaseId: r.release_id ?? null, releaseName: name },
      source: 'fred',
    });
  }
  return events;
}

// ── 전체 동기화 ──────────────────────────────────────────────────────────────
// keys 중 없는 것은 건너뛴다 (키 미설정 시 안전하게 no-op).
async function runCalendarSync(db, { finnhubKey, fredKey } = {}) {
  const now = new Date();
  const from = ymd(now, 'America/New_York');
  const to = ymd(addDays(now, WINDOW_DAYS), 'America/New_York');

  const collected = [];
  const result = { earnings: 0, economic: 0, ipo: 0, deleted: 0, skipped: [] };

  if (finnhubKey) {
    try {
      const earnings = await fetchEarnings(finnhubKey, from, to);
      collected.push(...earnings);
      result.earnings = earnings.length;
    } catch (e) {
      console.error('[Calendar] 실적 수집 실패:', e?.message || e);
    }
    try {
      const ipo = await fetchIpo(finnhubKey, from, to);
      collected.push(...ipo);
      result.ipo = ipo.length;
    } catch (e) {
      console.error('[Calendar] IPO 수집 실패:', e?.message || e);
    }
  } else {
    result.skipped.push('finnhub(키 없음)');
  }

  if (fredKey) {
    try {
      const econ = await fetchEconomic(fredKey, from, to);
      collected.push(...econ);
      result.economic = econ.length;
    } catch (e) {
      console.error('[Calendar] 거시지표 수집 실패:', e?.message || e);
    }
  } else {
    result.skipped.push('fred(키 없음)');
  }

  const col = db.collection('market_calendar');
  const today = ymd(now, 'America/New_York');

  // 기존 문서 조회 → 사라진/지난 이벤트는 삭제, 신규는 upsert
  const existingSnap = await col.get();
  const newIds = new Set(collected.map((e) => e.id));
  let batch = db.batch();
  let ops = 0;
  const commitIfNeeded = async () => {
    if (ops >= 450) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  };

  for (const doc of existingSnap.docs) {
    const d = doc.data();
    const stale = (d.date && d.date < today) || !newIds.has(doc.id);
    if (stale) {
      batch.delete(doc.ref);
      ops++;
      result.deleted++;
      await commitIfNeeded();
    }
  }

  for (const ev of collected) {
    batch.set(
      col.doc(ev.id),
      { ...ev, timestamp: dateToTimestamp(ev.date), updatedAt: new Date() },
      { merge: true }
    );
    ops++;
    await commitIfNeeded();
  }

  if (ops > 0) await batch.commit();

  console.log(
    `[Calendar] 동기화 완료 — 실적 ${result.earnings}, 지표 ${result.economic}, IPO ${result.ipo}, 삭제 ${result.deleted}` +
      (result.skipped.length ? `, 건너뜀: ${result.skipped.join(', ')}` : '')
  );
  return result;
}

// ── 당일 주요 일정 푸시 (notification_queue 트리거 재사용) ───────────────────
// US 기준 오늘 발생하는 중요 이벤트(importance>=2)를 한 건의 요약 푸시로 발송.
// 한국 사용자에게는 "오늘 밤" 일정에 해당.
async function notifyTodayEvents(db) {
  const todayUs = ymd(new Date(), 'America/New_York');
  const metaRef = db.collection('market_calendar_meta').doc(`notify_${todayUs}`);
  const meta = await metaRef.get();
  if (meta.exists) {
    return { skipped: true, reason: 'already-notified' };
  }

  const snap = await db.collection('market_calendar').where('date', '==', todayUs).get();
  const items = snap.docs
    .map((d) => d.data())
    .filter((e) => (e.importance || 0) >= 2);

  if (items.length === 0) {
    await metaRef.set({ notifiedAt: new Date(), count: 0 });
    return { count: 0 };
  }

  items.sort((a, b) => (b.importance || 0) - (a.importance || 0));
  const labels = items
    .slice(0, 4)
    .map((e) => (e.type === 'earnings' && e.symbol ? `${e.symbol} 실적` : e.name))
    .filter(Boolean);
  const extra = items.length > labels.length ? ` 외 ${items.length - labels.length}건` : '';
  const body = `오늘 밤 ${labels.join(', ')}${extra} 예정. 캘린더에서 확인하세요 →`;

  await db.collection('notification_queue').add({
    title: '📅 오늘의 주요 일정',
    body,
    topic: 'stock_alerts',
    route: 'market_calendar',
    createdAt: new Date(),
  });
  await metaRef.set({ notifiedAt: new Date(), count: items.length });
  console.log(`[Calendar] 당일 일정 푸시 발송: ${labels.join(', ')}${extra}`);
  return { count: items.length };
}

module.exports = { runCalendarSync, notifyTodayEvents };
