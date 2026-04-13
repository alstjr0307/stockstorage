const puppeteerExtra = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const admin = require('firebase-admin');
puppeteerExtra.use(StealthPlugin());

let serviceAccount;
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
} else {
  serviceAccount = require('./service-account.json');
}

if (!admin.apps.length) {
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}
const db = admin.firestore();

const MAX_PAGES = Number(process.env.MAX_PAGES || 5000);
const REQUEST_DELAY_MS = Number(process.env.REQUEST_DELAY_MS || 120);
const CONCURRENCY = Number(process.env.CONCURRENCY || 4);
const SAVE_FULL_MAP = String(process.env.SAVE_FULL_MAP || 'false') === 'true';
const SAVE_ALIAS_CANDIDATES =
  String(process.env.SAVE_ALIAS_CANDIDATES || 'true') === 'true';
const EXCLUDED_STOCK_NAMES = new Set(['?덉씠']);

function pad2(n) {
  return String(n).padStart(2, '0');
}

function formatDate(d) {
  return `${d.getFullYear()}.${pad2(d.getMonth() + 1)}.${pad2(d.getDate())}`;
}

function getKstNow() {
  const now = new Date();
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(now);

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

function getYesterdayKey(nowKst) {
  const d = new Date(nowKst.getFullYear(), nowKst.getMonth(), nowKst.getDate());
  d.setDate(d.getDate() - 1);
  return formatDate(d);
}

function getTodayKey(nowKst) {
  return formatDate(
    new Date(nowKst.getFullYear(), nowKst.getMonth(), nowKst.getDate()),
  );
}

function resolveTargetDateKey(nowKst) {
  if (process.env.TARGET_DATE_KEY) return process.env.TARGET_DATE_KEY;
  const mode = String(process.env.TARGET_MODE || 'today').toLowerCase();
  // 00:00~00:10 실행은 전날 집계 마감으로 처리한다.
  if (mode === 'today' && nowKst.getHours() === 0 && nowKst.getMinutes() <= 10) {
    return getYesterdayKey(nowKst);
  }
  if (mode === 'yesterday') return getYesterdayKey(nowKst);
  return getTodayKey(nowKst);
}

function parseTokenToDateKey(token, now) {
  if (!token) return null;
  const t = token.trim();

  const hhmm = /^(\d{2}):(\d{2})$/;
  const md = /^(\d{2})\.(\d{2})$/;
  const yymd = /^(\d{2})\.(\d{2})\.(\d{2})$/;
  const ymd = /^(\d{4})\.(\d{2})\.(\d{2})$/;

  let m = t.match(hhmm);
  if (m) {
    const hh = Number(m[1]);
    const mm = Number(m[2]);
    if (hh > 23 || mm > 59) return null;

    const nowMinutes = now.getHours() * 60 + now.getMinutes();
    const tokenMinutes = hh * 60 + mm;
    const base = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    if (tokenMinutes > nowMinutes) {
      base.setDate(base.getDate() - 1);
    }
    return formatDate(base);
  }

  m = t.match(md);
  if (m) {
    const month = Number(m[1]);
    const day = Number(m[2]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    let candidate = new Date(today.getFullYear(), month - 1, day);
    const tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
    if (candidate >= tomorrow) {
      candidate = new Date(today.getFullYear() - 1, month - 1, day);
    }
    return formatDate(candidate);
  }

  m = t.match(yymd);
  if (m) {
    const year = 2000 + Number(m[1]);
    const month = Number(m[2]);
    const day = Number(m[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return `${year}.${pad2(month)}.${pad2(day)}`;
  }

  m = t.match(ymd);
  if (m) {
    const year = Number(m[1]);
    const month = Number(m[2]);
    const day = Number(m[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return `${year}.${pad2(month)}.${pad2(day)}`;
  }

  return null;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function normalizeForContains(text) {
  return String(text || '')
    .toLowerCase()
    .replace(/[\u200B-\u200D\uFEFF]/g, '')
    .replace(/[\s`~!@#$%^&*()\-_=+\[\]{}\\|;:'",.<>/?]/g, '');
}

function generateHeuristicAliases(name) {
  const out = new Set();
  const raw = String(name || '').trim();
  if (!raw) return out;

  const compact = normalizeForContains(raw);
  if (!compact) return out;

  const suffixes = [
    '전자', '공업', '바이오', '제약', '홀딩스', '지주', '인더스트리', '테크',
    '테크놀로지', '에너지', '산업', '금융', '증권', '건설', '화학',
    '무산', '식품', '제강', '전기', '통신',
  ];

  if (/^[가-힣]+$/.test(compact)) {
    if (compact.length >= 2) out.add(compact.slice(0, 2));
    if (compact.length >= 3) out.add(compact.slice(0, 3));

    for (const sfx of suffixes) {
      if (!compact.endsWith(sfx)) continue;
      const stem = compact.slice(0, compact.length - sfx.length);
      if (stem.length >= 2) {
        out.add(stem);
        if (stem.length >= 3) out.add(stem.slice(0, 2));
      }
    }
  }

  return out;
}

async function scrapePageRows(browser, pageNum, retries = 2) {
  let page = null;
  const url = `https://www.fmkorea.com/stock?page=${pageNum}`;
  try {
    page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 800 });
    await page.setExtraHTTPHeaders({ 'Accept-Language': 'ko-KR,ko;q=0.9' });
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 35000 });
    await sleep(2500);
    await page.waitForSelector('table tbody tr td.time', { timeout: 20000 });

    const rows = await page.$$eval('table tbody tr:not(.notice)', (trs) =>
      trs
        .map((tr) => {
          const time = (tr.querySelector('td.time')?.textContent || '').trim();
          const anchor = tr.querySelector('td.title a');
          const title = (anchor?.textContent || '').trim().replace(/\s+/g, ' ');
          const href = anchor?.getAttribute('href') || '';
          const nidMatch = href.match(/\/(\d+)$/);
          const nid = nidMatch ? nidMatch[1] : null;
          return { time, title, href, nid };
        })
        .filter((r) => r.time && r.title),
    );
    return { ok: true, rows };
  } catch (err) {
    if (retries > 0) {
      if (page) {
        try {
          await page.close();
        } catch (_) {}
      }
      await sleep(350);
      return scrapePageRows(browser, pageNum, retries - 1);
    }
    return { ok: false, rows: [], error: String(err) };
  } finally {
    if (page) {
      try {
        await page.close();
      } catch (_) {}
    }
  }
}

async function loadManualAliases() {
  const file = './stock_aliases.json';
  const debug = String(process.env.DEBUG_ALIAS || 'false') === 'true';

  try {
    const data = require(file);
    if (!Array.isArray(data)) return [];
    if (debug) console.log(`[alias:file] ${file} count=${data.length}`);
    return data
      .map((item) => ({
        ticker: String(item.ticker || '').trim().toUpperCase(),
        name: String(item.name || '').trim(),
        aliases: Array.isArray(item.aliases)
          ? item.aliases.map((x) => String(x || '').trim()).filter(Boolean)
          : [],
        negative_aliases: Array.isArray(item.negative_aliases)
          ? item.negative_aliases.map((x) => String(x || '').trim()).filter(Boolean)
          : [],
      }))
      .filter((x) => x.ticker && x.name);
  } catch (_) {
    if (debug) console.log(`[alias:file] ${file} missing_or_invalid`);
    return [];
  }
}

async function loadAliasUniverse() {
  const byTicker = new Map();

  const manual = await loadManualAliases();
  for (const item of manual) {
    if (!byTicker.has(item.ticker)) {
      byTicker.set(item.ticker, {
        ticker: item.ticker,
        name: item.name,
        aliases: new Set([item.name, item.ticker]),
        negative_aliases: new Set(),
      });
    }
    const entity = byTicker.get(item.ticker);
    entity.aliases.add(item.name);
    entity.aliases.add(item.ticker);
    for (const a of item.aliases) entity.aliases.add(a);
    for (const a of item.negative_aliases) entity.negative_aliases.add(a);
  }

  const universe = [];
  for (const entity of byTicker.values()) {
    const aliasEntries = [];
    const seen = new Set();

    const pushAlias = (rawValue, keyValue, useCompact) => {
      const raw = String(rawValue || '').trim();
      const key = String(keyValue || '').trim();
      if (!raw || !key || key.length < 2) return;
      const dedupeKey = `${useCompact ? 'c' : 'p'}:${key}`;
      if (seen.has(dedupeKey)) return;
      seen.add(dedupeKey);
      aliasEntries.push({ raw, key, useCompact });
    };

    const rawAliases = Array.from(entity.aliases)
      .map((a) => a.trim())
      .filter((a) => a.length >= 2)
      .sort((a, b) => b.length - a.length);

    // Disabled for full-universe mode to avoid broad false positives.

    for (const raw of rawAliases) {
      const plainKey = raw.toLowerCase();
      const compactKey = normalizeForContains(raw);
      pushAlias(raw, plainKey, false);
      if (compactKey !== plainKey) {
        pushAlias(raw, compactKey, true);
      }
    }

    aliasEntries.sort((a, b) => b.key.length - a.key.length || b.raw.length - a.raw.length);

    universe.push({
      ticker: entity.ticker,
      name: entity.name,
      aliases: aliasEntries,
      negative_aliases: Array.from(entity.negative_aliases).map((a) => normalizeForContains(a)),
    });
  }
  return universe;
}

function extractMentionTickers(title, universe) {
  const plainTitle = String(title || '').toLowerCase();
  const compactTitle = normalizeForContains(title);
  const tickers = new Set();
  for (const stock of universe) {
    if (EXCLUDED_STOCK_NAMES.has(String(stock.name || '').trim())) continue;
    // negative_aliases: 제목에 이 단어가 포함되면 해당 종목 집계 제외
    if (stock.negative_aliases && stock.negative_aliases.some((neg) => compactTitle.includes(neg))) continue;
    for (const alias of stock.aliases) {
      const haystack = alias.useCompact ? compactTitle : plainTitle;
      if (haystack.includes(alias.key)) {
        tickers.add(stock.ticker);
        break;
      }
    }
  }
  return Array.from(tickers);
}

function tokenizeTitle(text) {
  const tokens = String(text || '').match(/[A-Za-z]{2,15}|[가-힣]{2,10}/g) || [];
  return tokens.map((t) => t.toLowerCase());
}

function buildKnownAliasSet(universe) {
  const known = new Set();
  for (const stock of universe) {
    known.add(String(stock.ticker || '').toLowerCase());
    for (const a of stock.aliases || []) {
      known.add(String(a.key || '').toLowerCase());
      known.add(normalizeForContains(String(a.raw || '')));
    }
  }
  return known;
}

function buildAliasCandidates(rows, universeByTicker, universe) {
  const knownAlias = buildKnownAliasSet(universe);
  const perTickerTokenCount = new Map();
  const tokenToTickerCount = new Map();

  const stopwords = new Set([
    '오늘', '내일', '어제', '지금', '진짜', '그냥', '추천', '매수', '매도', '단타', '스윙',
    '목표가', '실적', '급등', '급락', '상한가', '하한가', '코스피', '코스닥', '국장',
    '뉴스', '속보', '동향', '마감', '시황', '분석', '주식', '종목', '관심', '가격',
  ]);

  const bump = (map, key, n = 1) => map.set(key, (map.get(key) || 0) + n);

  for (const row of rows) {
    const tickers = Array.isArray(row.mentionedTickers) ? row.mentionedTickers : [];
    if (tickers.length !== 1) continue;
    const ticker = tickers[0];
    const tokens = tokenizeTitle(row.title);
    const uniqueTokens = new Set(tokens);

    for (const token of uniqueTokens) {
      const compact = normalizeForContains(token);
      if (!compact || compact.length < 2) continue;
      if (knownAlias.has(token) || knownAlias.has(compact)) continue;
      if (stopwords.has(token) || stopwords.has(compact)) continue;
      if (/^\d+$/.test(compact)) continue;

      if (!perTickerTokenCount.has(ticker)) perTickerTokenCount.set(ticker, new Map());
      bump(perTickerTokenCount.get(ticker), compact, 1);

      if (!tokenToTickerCount.has(compact)) tokenToTickerCount.set(compact, new Map());
      bump(tokenToTickerCount.get(compact), ticker, 1);
    }
  }

  const candidates = [];
  for (const [ticker, tokenMap] of perTickerTokenCount.entries()) {
    const name = universeByTicker.get(ticker)?.name || ticker;
    const top = Array.from(tokenMap.entries())
      .map(([token, count]) => {
        const dist = tokenToTickerCount.get(token) || new Map();
        const total = Array.from(dist.values()).reduce((a, b) => a + b, 0);
        const mine = dist.get(ticker) || 0;
        const dominance = total > 0 ? mine / total : 0;
        return {
          token,
          count,
          dominance: Number(dominance.toFixed(3)),
        };
      })
      .filter((x) => x.count >= 2)
      .sort((a, b) => b.count - a.count || b.dominance - a.dominance)
      .slice(0, 15);

    if (top.length) {
      candidates.push({ ticker, name, tokens: top });
    }
  }

  candidates.sort((a, b) => a.ticker.localeCompare(b.ticker));
  return candidates;
}

async function collectTargetDateTitleRows(browser, targetDateKey, nowKst) {
  const matchedRows = [];
  let scannedPages = 0;
  let seenOlderThanTarget = false;
  let hitAnyTarget = false;
  let consecutiveFailures = 0;

  for (let pageNum = 1; pageNum <= MAX_PAGES; pageNum += 1) {
    const { ok, rows, error } = await scrapePageRows(browser, pageNum);
    scannedPages += 1;

    if (!ok) {
      consecutiveFailures += 1;
      console.log(`[page=${pageNum}] failed: ${error || 'unknown'}`);
      if (consecutiveFailures >= 5) {
        console.log('[stop] too many consecutive page failures');
        break;
      }
      continue;
    }
    consecutiveFailures = 0;
    if (!rows.length) {
      console.log(`[page=${pageNum}] empty rows, stop`);
      break;
    }

    let pageHasTarget = false;
    let pageHasOlder = false;
    let oldestOnPage = null;

    for (const row of rows) {
      const dateKey = parseTokenToDateKey(row.time, nowKst);
      if (!dateKey) continue;
      if (!oldestOnPage || dateKey < oldestOnPage) oldestOnPage = dateKey;
      if (dateKey === targetDateKey) {
        pageHasTarget = true;
        hitAnyTarget = true;
        matchedRows.push({ ...row, dateKey, pageNum });
      } else if (dateKey < targetDateKey) {
        pageHasOlder = true;
      }
    }

    if (pageHasOlder) {
      seenOlderThanTarget = true;
    }

    console.log(
      `[page=${pageNum}] targetRows=${pageHasTarget ? 'yes' : 'no'} oldest=${oldestOnPage || '-'} totalMatched=${matchedRows.length}`,
    );

    // 타겟 날짜보다 과거 날짜가 이미 노출됐는데 타겟이 1건도 없으면 더 볼 필요가 없다.
    if (seenOlderThanTarget && !hitAnyTarget) {
      console.log('[stop] target date not found before older dates');
      break;
    }

    if (seenOlderThanTarget && !pageHasTarget && hitAnyTarget) {
      console.log('[stop] passed target date range');
      break;
    }

    if (REQUEST_DELAY_MS > 0) {
      await sleep(REQUEST_DELAY_MS);
    }
  }

  return { matchedRows, scannedPages };
}

function aggregateMentions(rows, universeByTicker) {
  const counts = new Map();
  const postHitCount = new Map();
  let matchedPostCount = 0;

  for (const row of rows) {
    const uniqueTickers = Array.isArray(row.mentionedTickers)
      ? row.mentionedTickers
      : [];
    if (uniqueTickers.length) matchedPostCount += 1;
    for (const ticker of uniqueTickers) {
      counts.set(ticker, (counts.get(ticker) || 0) + 1);
      postHitCount.set(ticker, (postHitCount.get(ticker) || 0) + 1);
    }
  }

  const topMentions = Array.from(counts.entries())
    .map(([ticker, mentionCount]) => ({
      ticker,
      name: universeByTicker.get(ticker)?.name || ticker,
      mentionCount,
      postCount: postHitCount.get(ticker) || 0,
    }))
    .sort((a, b) => b.mentionCount - a.mentionCount || a.ticker.localeCompare(b.ticker));

  return { topMentions, matchedPostCount };
}

async function saveResult({
  nowKst,
  targetDateKey,
  scannedPages,
  totalPosts,
  topMentions,
  matchedPostCount,
  aliasCandidates,
  modeOverride,
  noteOverride,
  mentionsMapOverride,
}) {
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const docId = targetDateKey.replace(/\./g, '-');
  const todayKey = getTodayKey(nowKst);
  const isTodayTarget = targetDateKey === todayKey;
  const ref = db.collection('fmkorea_stock_mentions_daily').doc(docId);

  const payload = {
    dateKey: targetDateKey,
    scannedPages,
    totalPosts,
    matchedPostCount,
    uniqueStockCount: topMentions.length,
    topMentions: topMentions.slice(0, 200),
    updatedAt: nowTs,
    source: 'fmkorea_title_only',
    mode: modeOverride || (isTodayTarget ? 'realtime_today_cumulative' : 'daily_snapshot'),
    note: noteOverride || (isTodayTarget
      ? 'Today cumulative stock mentions from title only'
      : 'Daily stock mentions from title only'),
  };

  if (mentionsMapOverride) {
    payload.mentionsMap = mentionsMapOverride;
  } else if (SAVE_FULL_MAP) {
    payload.mentionsMap = Object.fromEntries(
      topMentions.map((x) => [x.ticker, { name: x.name, mentionCount: x.mentionCount, postCount: x.postCount }]),
    );
  }

  await ref.set(payload, { merge: true });

  if (isTodayTarget && topMentions.length > 0 && matchedPostCount > 0) {
    const realtimeRef = db.collection('fmkorea_stock_mentions_realtime').doc('today');
    const toNum = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
    const existingSnap = await realtimeRef.get();
    if (existingSnap.exists) {
      const prev = existingSnap.data() || {};
      const prevDateKey = String(prev.dateKey || '');
      const prevMatched = toNum(prev.matchedPostCount);
      const prevPosts = toNum(prev.totalPosts);
      const prevMentions = Array.isArray(prev.topMentions) ? prev.topMentions : [];

      // 같은 날짜(today)에서 누적 값이 감소하면 부분 스크래핑으로 판단하고 기존 TOP을 유지한다.
      const regressed =
        prevDateKey === targetDateKey &&
        prevMentions.length > 0 &&
        (matchedPostCount < prevMatched || totalPosts < prevPosts);

      if (regressed) {
        console.log(
          `[realtime] keep previous topMentions (regressed) prevMatched=${prevMatched} newMatched=${matchedPostCount} prevPosts=${prevPosts} newPosts=${totalPosts}`,
        );
      } else {
        await realtimeRef.set(
          {
            ...payload,
            id: 'today',
          },
          { merge: true },
        );
      }
    } else {
      await realtimeRef.set(
        {
          ...payload,
          id: 'today',
        },
        { merge: true },
      );
    }
  } else if (isTodayTarget) {
    console.log('[realtime] skip overwrite because result is empty');
  }

  if (SAVE_ALIAS_CANDIDATES && Array.isArray(aliasCandidates)) {
    const aliasRef = db.collection('fmkorea_stock_alias_candidates').doc(docId);
    await aliasRef.set(
      {
        dateKey: targetDateKey,
        updatedAt: nowTs,
        candidates: aliasCandidates,
        note: 'Auto-mined alias candidates from single-ticker title rows',
      },
      { merge: true },
    );
  }
}

async function main() {
  const nowKst = getKstNow();
  const targetDateKey = resolveTargetDateKey(nowKst);
  const mode = String(process.env.TARGET_MODE || (process.env.TARGET_DATE_KEY ? 'custom' : 'today')).toLowerCase();
  console.log(`[start] targetDate=${targetDateKey} nowKst=${formatDate(nowKst)} ${pad2(nowKst.getHours())}:${pad2(nowKst.getMinutes())}`);
  console.log(`[start] mode=${mode}`);

  const browser = await puppeteerExtra.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  try {
    const universe = await loadAliasUniverse();
    const universeByTicker = new Map(universe.map((x) => [x.ticker, x]));
    console.log(`[alias] loaded=${universe.length}`);

    const warmup = await browser.newPage();
    await warmup.goto('https://www.fmkorea.com/stock', {
      waitUntil: 'domcontentloaded',
      timeout: 30000,
    });
    await warmup.close();

    const { matchedRows, scannedPages } = await collectTargetDateTitleRows(
      browser,
      targetDateKey,
      nowKst,
    );

    console.log(`[collect] scannedPages=${scannedPages} targetPosts=${matchedRows.length}`);

    const enrichedRows = [];
    for (let i = 0; i < matchedRows.length; i += CONCURRENCY) {
      const chunk = matchedRows.slice(i, i + CONCURRENCY);
      const chunkOut = chunk.map((row) => ({
        ...row,
        mentionedTickers: extractMentionTickers(row.title, universe),
      }));
      enrichedRows.push(...chunkOut);
    }

    const { topMentions, matchedPostCount } = aggregateMentions(
      enrichedRows,
      universeByTicker,
    );
    const aliasCandidates = buildAliasCandidates(
      enrichedRows,
      universeByTicker,
      universe,
    );

    await saveResult({
      nowKst,
      targetDateKey,
      scannedPages,
      totalPosts: enrichedRows.length,
      topMentions,
      matchedPostCount,
      aliasCandidates,
      modeOverride:
        mode === 'today' && !process.env.TARGET_DATE_KEY
          ? 'realtime_today_cumulative_full_scan'
          : undefined,
      noteOverride:
        mode === 'today' && !process.env.TARGET_DATE_KEY
          ? 'Today cumulative stock mentions from title only (full scan each run)'
          : undefined,
    });

    console.log(
      `[done] date=${targetDateKey} posts=${enrichedRows.length} matchedPosts=${matchedPostCount} uniqueStocks=${topMentions.length}`,
    );
    console.log(`[done] top10=${topMentions.slice(0, 10).map((x) => `${x.name}(${x.mentionCount})`).join(', ')}`);
    console.log(`[done] aliasCandidatesTickers=${aliasCandidates.length}`);
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error('[fatal]', err);
  process.exit(1);
});


