const puppeteerExtra = require('puppeteer-extra');
const admin = require('firebase-admin');

let serviceAccount;
if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
} else {
  serviceAccount = require('./service-account.json');
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const DAYS_BACK = Number(process.env.DAYS_BACK || 30);
const COARSE_STEP = Number(process.env.COARSE_STEP || 1000);
const CONCURRENCY = Number(process.env.CONCURRENCY || 10);
const MAX_COARSE_PAGE = Number(process.env.MAX_COARSE_PAGE || 300000);
const POSTS_PER_PAGE = 20;
const pageSummaryCache = new Map();

function pad2(n) {
  return String(n).padStart(2, '0');
}

function formatDate(d) {
  return `${d.getFullYear()}.${pad2(d.getMonth() + 1)}.${pad2(d.getDate())}`;
}

function buildTargetDateKeys(now, daysBack) {
  const base = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const keys = [];

  for (let i = 0; i < daysBack; i += 1) {
    const d = new Date(base);
    d.setDate(base.getDate() - i);
    keys.push(formatDate(d));
  }

  return keys;
}

function parseTokenToDateKey(token, now) {
  if (!token) return null;
  const t = token.trim();

  // FMKorea rule: when now is 20:13, posts after yesterday 20:13 are shown as HH:mm.
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
      base.setDate(base.getDate() - 1); // yesterday
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

    // Year rollover handling around Jan.
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
    const y = Number(m[1]);
    const month = Number(m[2]);
    const day = Number(m[3]);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return `${y}.${pad2(month)}.${pad2(day)}`;
  }

  return null;
}

async function scrapePageTokens(browser, pageNum, retries = 2) {
  const url = `https://www.fmkorea.com/stock?page=${pageNum}`;
  const page = await browser.newPage();

  try {
    await page.setViewport({ width: 1280, height: 800 });
    await page.setExtraHTTPHeaders({ 'Accept-Language': 'ko-KR,ko;q=0.9' });
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    await page.waitForSelector('table tbody tr td.time', { timeout: 12000 });

    const rows = await page.$$eval('table tbody tr:not(.notice)', (trs) =>
      trs.map((tr) => {
        const time = (tr.querySelector('td.time')?.textContent || '').trim();
        const href = tr.querySelector('td.title a')?.getAttribute('href') || '';
        return { time, href };
      }).filter((row) => row.time)
    );
    const tokens = rows.map((row) => row.time);
    const fingerprint = rows
      .slice(0, 8)
      .map((row) => `${row.href}|${row.time}`)
      .join('||');

    return {
      ok: true,
      pageNum,
      finalUrl: page.url(),
      title: await page.title(),
      tokens,
      fingerprint,
    };
  } catch (err) {
    if (retries > 0) {
      await page.close();
      return scrapePageTokens(browser, pageNum, retries - 1);
    }

    return {
      ok: false,
      pageNum,
      finalUrl: '',
      title: '',
      tokens: [],
      fingerprint: '',
      error: String(err),
    };
  } finally {
    await page.close();
  }
}

function summarizeTokens(tokens, now) {
  const counts = {};
  let parsedCount = 0;
  let newestKey = null;
  let oldestKey = null;

  for (const token of tokens) {
    const key = parseTokenToDateKey(token, now);
    if (!key) continue;

    parsedCount += 1;

    if (!newestKey || key > newestKey) newestKey = key;
    if (!oldestKey || key < oldestKey) oldestKey = key;

    counts[key] = (counts[key] || 0) + 1;
  }

  return { counts, parsedCount, newestKey, oldestKey };
}

async function getPageSummary(browser, pageNum, now) {
  if (pageSummaryCache.has(pageNum)) {
    return pageSummaryCache.get(pageNum);
  }

  const res = await scrapePageTokens(browser, pageNum);
  const summary = summarizeTokens(res.tokens, now);
  const combined = {
    ...res,
    ...summary,
  };

  pageSummaryCache.set(pageNum, combined);
  return combined;
}

function mergeCounts(target, source) {
  for (const [k, v] of Object.entries(source)) {
    target[k] = (target[k] || 0) + v;
  }
}

async function findDetailEndPage(browser, now, cutoffKey) {
  console.log(`[coarse] start step=${COARSE_STEP}, max=${MAX_COARSE_PAGE}`);

  let lower = 1;
  let upper = null;
  let prevFingerprint = null;
  let repeatFingerprintCount = 0;

  for (let pageNum = 1; pageNum <= MAX_COARSE_PAGE; pageNum += COARSE_STEP) {
    const info = await getPageSummary(browser, pageNum, now);
    const hitCutoff = Boolean(info.oldestKey && info.oldestKey < cutoffKey);

    console.log(
      `[coarse] page=${pageNum} parsed=${info.parsedCount} oldest=${info.oldestKey || '-'} hitCutoff=${hitCutoff}`
    );

    if (!info.ok || info.parsedCount === 0) {
      upper = pageNum;
      break;
    }

    if (info.fingerprint && info.fingerprint === prevFingerprint) {
      repeatFingerprintCount += 1;
    } else {
      repeatFingerprintCount = 0;
    }
    prevFingerprint = info.fingerprint;

    if (repeatFingerprintCount >= 2) {
      // Likely redirected/clamped pages repeating the same content.
      upper = pageNum;
      break;
    }

    if (hitCutoff) {
      upper = pageNum;
      lower = Math.max(1, pageNum - COARSE_STEP);
      break;
    }

    lower = pageNum;
  }

  if (upper == null) {
    console.log('[coarse] cutoff was not found within max coarse page; fallback to lower bound.');
    return lower;
  }

  if (upper <= lower) {
    return upper;
  }

  console.log(`[binary] range ${lower}..${upper}`);
  let lo = lower;
  let hi = upper;

  while (lo + 1 < hi) {
    const mid = Math.floor((lo + hi) / 2);
    const info = await getPageSummary(browser, mid, now);

    const isOldOrInvalid =
      !info.ok ||
      info.parsedCount === 0 ||
      Boolean(info.oldestKey && info.oldestKey < cutoffKey);

    console.log(
      `[binary] page=${mid} parsed=${info.parsedCount} oldest=${info.oldestKey || '-'} move=${isOldOrInvalid ? 'left' : 'right'}`
    );

    if (isOldOrInvalid) {
      hi = mid;
    } else {
      lo = mid;
    }
  }

  return hi;
}

async function findFirstPageWithOldestAtMost(browser, now, lastPage, targetKey) {
  let lo = 1;
  let hi = lastPage;
  let answer = null;

  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    const info = await getPageSummary(browser, mid, now);

    if (info.ok && info.parsedCount > 0 && info.oldestKey && info.oldestKey <= targetKey) {
      answer = mid;
      hi = mid - 1;
    } else {
      lo = mid + 1;
    }
  }

  return answer;
}

async function findFirstPageWithOldestLessThan(browser, now, lastPage, targetKey, startPage) {
  let lo = startPage;
  let hi = lastPage;
  let answer = null;

  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    const info = await getPageSummary(browser, mid, now);

    if (info.ok && info.parsedCount > 0 && info.oldestKey && info.oldestKey < targetKey) {
      answer = mid;
      hi = mid - 1;
    } else {
      lo = mid + 1;
    }
  }

  return answer;
}

async function collectDailyCounts(browser, now, lastDataPage, targetKeys) {
  const totalCounts = {};

  for (const targetKey of targetKeys) {
    const startPage = await findFirstPageWithOldestAtMost(
      browser,
      now,
      lastDataPage,
      targetKey
    );

    if (startPage == null) {
      totalCounts[targetKey] = 0;
      console.log(`[daily] ${targetKey} pageRange=(none) count=0`);
      continue;
    }

    const startInfo = await getPageSummary(browser, startPage, now);
    if (!startInfo.newestKey || startInfo.newestKey < targetKey) {
      totalCounts[targetKey] = 0;
      console.log(`[daily] ${targetKey} pageRange=(none) count=0`);
      continue;
    }

    const endExclusive =
      (await findFirstPageWithOldestLessThan(
        browser,
        now,
        lastDataPage,
        targetKey,
        startPage
      )) ??
      (lastDataPage + 1);

    const lastPage = endExclusive - 1;
    let total = 0;

    if (lastPage === startPage) {
      total = startInfo.counts[targetKey] || 0;
    } else {
      const lastInfo = await getPageSummary(browser, lastPage, now);
      total += startInfo.counts[targetKey] || 0;
      total += lastInfo.counts[targetKey] || 0;
      total += Math.max(0, lastPage - startPage - 1) * POSTS_PER_PAGE;
    }

    totalCounts[targetKey] = total;
    console.log(`[daily] ${targetKey} pageRange=${startPage}-${lastPage} count=${total}`);
  }

  return totalCounts;
}

async function saveCountsToFirestore(totalCounts) {
  const entries = Object.entries(totalCounts).filter(([, count]) => count > 0);
  if (entries.length === 0) {
    console.log('[save] no data');
    return;
  }

  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  for (let i = 0; i < entries.length; i += 400) {
    const batch = db.batch();
    for (const [dateKey, count] of entries.slice(i, i + 400)) {
      batch.set(
        db.collection('fmkorea_index').doc(dateKey),
        { count, updatedAt: nowTs },
        { merge: true }
      );
    }
    await batch.commit();
  }

  console.log(`[save] Firestore upsert complete: ${entries.length} day docs`);
}

async function run() {
  const browser = await puppeteerExtra.launch({
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-blink-features=AutomationControlled',
    ],
    headless: true,
  });

  try {
    const now = new Date();
    const targetKeys = buildTargetDateKeys(now, DAYS_BACK);
    const cutoffKey = targetKeys[targetKeys.length - 1];

    console.log(`[run] now=${now.toISOString()} daysBack=${DAYS_BACK} cutoff=${cutoffKey}`);

    // Warm-up once for anti-bot cookie/init.
    const warmup = await browser.newPage();
    await warmup.setViewport({ width: 1280, height: 800 });
    await warmup.goto('https://www.fmkorea.com/stock', {
      waitUntil: 'networkidle2',
      timeout: 30000,
    });
    await new Promise((r) => setTimeout(r, 2500));
    console.log(`[warmup] title=${await warmup.title()}`);
    await warmup.close();

    const endPage = await findDetailEndPage(browser, now, cutoffKey);
    console.log(`[run] detail scrape endPage=${endPage}`);

    const totalCounts = await collectDailyCounts(browser, now, endPage - 1, targetKeys);
    const keys = Object.keys(totalCounts).sort();

    console.log(`[result] dates=${keys.length ? keys.join(', ') : '(none)'}`);
    console.log(`[result] counts=${JSON.stringify(totalCounts)}`);

    await saveCountsToFirestore(totalCounts);
  } finally {
    await browser.close();
    process.exit(0);
  }
}

run().catch((err) => {
  console.error('[fatal]', err);
  process.exit(1);
});
