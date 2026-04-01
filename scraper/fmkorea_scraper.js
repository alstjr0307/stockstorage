const puppeteer = require('puppeteer');
const admin = require('firebase-admin');

// Firebase 초기화 (GitHub Secret → 환경변수로 전달)
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

  // td.time 요소가 나타날 때까지 대기 (최대 10초)
  try {
    await page.waitForSelector('td.time', { timeout: 10000 });
  } catch (_) {
    console.log(`페이지 ${pageNum}: td.time 없음 (공지만 있는 페이지거나 로드 실패)`);
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
  const browser = await puppeteer.launch({
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
    headless: true,
  });

  try {
    const page = await browser.newPage();
    await page.setUserAgent(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
    );

    const today = new Date();
    const cutoff = new Date(today);
    cutoff.setDate(cutoff.getDate() - DAYS_BACK);

    const totalCounts = {};
    let hitCutoff = false;

    // 첫 페이지: 봇 감지 쿠키 세팅용 (결과도 수집)
    console.log('첫 페이지 로딩 (봇 감지 통과용)...');
    await page.goto('https://www.fmkorea.com/stock', { waitUntil: 'networkidle2', timeout: 30000 });
    await new Promise(r => setTimeout(r, 2000)); // 봇 감지 JS 실행 대기

    for (let p = 1; p <= MAX_PAGES && !hitCutoff; p++) {
      const times = await scrapePage(page, p);
      if (times.length === 0 && p > 1) break;

      const { counts, hitCutoff: h } = parseTimes(times, today, cutoff);
      for (const [k, v] of Object.entries(counts)) {
        totalCounts[k] = (totalCounts[k] ?? 0) + v;
      }
      hitCutoff = h;

      if (!hitCutoff && p < MAX_PAGES) {
        await new Promise(r => setTimeout(r, 1000)); // 요청 간 간격
      }
    }

    console.log('수집된 날짜:', Object.keys(totalCounts).sort());

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
