const puppeteerExtra = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
const admin = require('firebase-admin');

puppeteerExtra.use(StealthPlugin());

// Firebase 초기화
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});
const db = admin.firestore();

const MAX_PAGES = 15;
const DAYS_BACK = 31;

function formatDate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}.${m}.${day}`;
}

async function scrapePage(page, pageNum) {
  const url = `https://www.fmkorea.com/stock?page=${pageNum}`;
  console.log(`페이지 ${pageNum} 로딩: ${url}`);
  await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });

  // td.time 요소가 나타날 때까지 대기 (최대 15초)
  try {
    await page.waitForSelector('td.time', { timeout: 15000 });
  } catch (_) {
    // 실제 HTML 샘플 출력해서 디버깅
    const sample = await page.evaluate(() => document.body.innerHTML.substring(0, 500));
    console.log(`페이지 ${pageNum}: td.time 없음. HTML 앞부분: ${sample}`);
    return [];
  }

  const times = await page.$$eval('td.time', (els) =>
    els.map((el) => el.innerText.trim()).filter(Boolean)
  );
  console.log(`페이지 ${pageNum}: ${times.length}개 시간 수집`);
  return times;
}

function parseTimes(timesList, today, cutoff) {
  const counts = {};
  const todayKey = formatDate(today);
  const todayRe = /^\d{2}:\d{2}$/;
  const mdRe = /^\d{2}\.\d{2}$/;
  const ymdRe = /^\d{4}\.\d{2}\.\d{2}$/;
  let hitCutoff = false;

  for (const t of timesList) {
    let key = null;
    if (todayRe.test(t)) {
      key = todayKey;
    } else if (mdRe.test(t)) {
      const [m, d] = t.split('.').map(Number);
      const dt = new Date(today.getFullYear(), m - 1, d);
      if (dt < cutoff) { hitCutoff = true; break; }
      key = formatDate(dt);
    } else if (ymdRe.test(t)) {
      const [y, m, d] = t.split('.').map(Number);
      const dt = new Date(y, m - 1, d);
      if (dt < cutoff) { hitCutoff = true; break; }
      key = t;
    }
    if (key) counts[key] = (counts[key] ?? 0) + 1;
  }

  return { counts, hitCutoff };
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
    const page = await browser.newPage();

    // 실제 브라우저처럼 viewport 설정
    await page.setViewport({ width: 1280, height: 800 });
    await page.setExtraHTTPHeaders({
      'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
    });

    const today = new Date();
    const cutoff = new Date(today);
    cutoff.setDate(cutoff.getDate() - DAYS_BACK);

    const totalCounts = {};
    let hitCutoff = false;

    // 첫 페이지: 봇 감지 쿠키 세팅용
    console.log('첫 페이지 로딩 (봇 감지 통과용)...');
    await page.goto('https://www.fmkorea.com/stock', { waitUntil: 'networkidle2', timeout: 30000 });
    await new Promise(r => setTimeout(r, 3000));

    // 봇 감지 통과 확인
    const title = await page.title();
    console.log('페이지 타이틀:', title);

    for (let p = 1; p <= MAX_PAGES && !hitCutoff; p++) {
      const times = await scrapePage(page, p);
      if (times.length === 0 && p > 1) break;

      const { counts, hitCutoff: h } = parseTimes(times, today, cutoff);
      for (const [k, v] of Object.entries(counts)) {
        totalCounts[k] = (totalCounts[k] ?? 0) + v;
      }
      hitCutoff = h;

      if (!hitCutoff && p < MAX_PAGES) {
        await new Promise(r => setTimeout(r, 1500));
      }
    }

    console.log('수집된 날짜:', Object.keys(totalCounts).sort());
    console.log('날짜별 카운트:', JSON.stringify(totalCounts));

    if (Object.keys(totalCounts).length === 0) {
      console.log('데이터 없음 - Firestore 저장 건너뜀');
      return;
    }

    // Firestore 저장
    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();
    for (const [dateKey, count] of Object.entries(totalCounts)) {
      const ref = db.collection('fmkorea_index').doc(dateKey);
      batch.set(ref, { count, updatedAt: now }, { merge: true });
    }
    await batch.commit();
    console.log(`Firestore 저장 완료: ${Object.keys(totalCounts).length}개 날짜`);
  } finally {
    await browser.close();
    process.exit(0);
  }
}

run().catch((e) => {
  console.error('오류:', e);
  process.exit(1);
});
