/**
 * AI 한 줄 시황 즉시 생성 스크립트
 * 사용법: node generate_brief_now.js sk-ant-xxxxxxx
 */

const axios = require('axios');
const cheerio = require('cheerio');
const path = require('path');
const fs = require('fs');
const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const Anthropic = require('@anthropic-ai/sdk');

// ── 설정 ─────────────────────────────────────────────────────────────────────
const ANTHROPIC_API_KEY = process.argv[2];
if (!ANTHROPIC_API_KEY || !ANTHROPIC_API_KEY.startsWith('sk-ant')) {
  console.error('사용법: node generate_brief_now.js sk-ant-xxxxx');
  process.exit(1);
}

if (!getApps().length) {
  const keyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (!fs.existsSync(keyPath)) {
    console.error('❌ serviceAccountKey.json 파일이 없어요!');
    console.error('   Firebase Console → 프로젝트 설정 → 서비스 계정 → 새 비공개 키 생성');
    console.error('   다운로드한 JSON을 functions/serviceAccountKey.json 으로 저장하세요.');
    process.exit(1);
  }
  initializeApp({ credential: cert(keyPath) });
}
const db = getFirestore();

const NAVER_PC_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Referer': 'https://finance.naver.com/',
  'Accept-Language': 'ko-KR,ko;q=0.9',
};
const NAVER_MOBILE_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148',
  'Referer': 'https://m.finance.naver.com/',
  'Accept': 'application/json',
};

// ── 네이버 금융 지수 스크래핑 ────────────────────────────────────────────────
async function fetchMarketData() {
  const [kospiRes, kosdaqRes] = await Promise.all([
    axios.get('https://m.stock.naver.com/api/index/KOSPI/basic', { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }),
    axios.get('https://m.stock.naver.com/api/index/KOSDAQ/basic', { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }),
  ]);
  const parse = (d) => ({
    price: Number(d.closePrice?.replace(/,/g, '') || 0),
    change: Number(d.compareToPreviousClosePrice?.replace(/,/g, '') || 0),
    changeRate: Number(d.fluctuationsRatio || 0),
    isUp: Number(d.fluctuationsRatio || 0) >= 0,
    marketStatus: d.marketStatus || null,
    tradedDate: d.localTradedAt ? String(d.localTradedAt).slice(0, 10) : null,
  });
  return { kospi: parse(kospiRes.data), kosdaq: parse(kosdaqRes.data) };
}

const SECTOR_NAME_MAP = {
  '도로와철도운송': '운송',
  '항공화물운송서비스': '항공·물류',
  '생물공학': '바이오',
  '건강관리업체및서비스': '헬스케어',
  '판매업체': '유통',
  '음식료·담배': '음식료',
  '섬유·의류': '섬유의류',
  '의약품': '제약',
  '의료장비': '의료기기',
  '전기·전자': '전기전자',
  '디스플레이패널': '디스플레이',
  'IT하드웨어': 'IT하드웨어',
  '미디어·교육': '미디어·교육',
  '소매업체': '소매유통',
  '다각화된금융서비스': '금융서비스',
  '특수소매업': '특수소매',
  '복합유틸리티': '유틸리티',
  '가스유틸리티': '가스',
  '전기유틸리티': '전기',
};
const normSector = (name) => SECTOR_NAME_MAP[name] || name;

// ── 네이버 금융 업종별 시세 스크래핑 ─────────────────────────────────────────
async function fetchSectorData() {
  try {
    const [kospiRes, kosdaqRes] = await Promise.all([
      axios.get('https://finance.naver.com/sise/sise_group.nhn?type=upjong', {
        headers: NAVER_PC_HEADERS, responseType: 'arraybuffer', timeout: 8000,
      }),
      axios.get('https://finance.naver.com/sise/sise_group.nhn?type=upjong&sosok=1', {
        headers: NAVER_PC_HEADERS, responseType: 'arraybuffer', timeout: 8000,
      }),
    ]);

    const decoder = new TextDecoder('euc-kr');
    const parseSectors = (buffer) => {
      const $ = cheerio.load(decoder.decode(buffer));
      const sectors = [];
      $('table.type_1 tbody tr').each((_, row) => {
        const cells = $(row).find('td');
        if (cells.length < 3) return;
        const name = $(cells[0]).find('a').text().trim();
        if (!name) return;
        // cells[1] = 등락률(%), cells[2]=종목수, cells[3]=상승, cells[4]=보합, cells[5]=하락
        const rateText = $(cells[1]).text().trim().replace(/\s+/g, '');
        const rate = parseFloat(rateText.replace('%', '').replace(',', ''));
        if (!isNaN(rate)) sectors.push({ name: normSector(name), rate });
      });
      return sectors;
    };

    const kospiSectors = parseSectors(kospiRes.data);
    const kosdaqSectors = parseSectors(kosdaqRes.data);
    console.log(`  KOSPI 업종 ${kospiSectors.length}개, KOSDAQ 업종 ${kosdaqSectors.length}개 파싱`);
    return {
      kospi: {
        up: kospiSectors.filter(s => s.rate > 0).sort((a, b) => b.rate - a.rate).slice(0, 3),
        down: kospiSectors.filter(s => s.rate < 0).sort((a, b) => a.rate - b.rate).slice(0, 3),
      },
      kosdaq: {
        up: kosdaqSectors.filter(s => s.rate > 0).sort((a, b) => b.rate - a.rate).slice(0, 3),
        down: kosdaqSectors.filter(s => s.rate < 0).sort((a, b) => a.rate - b.rate).slice(0, 3),
      },
    };
  } catch (e) {
    console.warn('  ⚠️ 업종 데이터 실패:', e.message);
    return null;
  }
}

// ── 시장 폭 (상승/하락/보합 종목수) ─────────────────────────────────────────
async function fetchMarketBreadth() {
  try {
    const [kospiRes, kosdaqRes] = await Promise.all([
      axios.get('https://m.stock.naver.com/api/index/KOSPI/integration', {
        headers: NAVER_MOBILE_HEADERS, timeout: 8000,
      }),
      axios.get('https://m.stock.naver.com/api/index/KOSDAQ/integration', {
        headers: NAVER_MOBILE_HEADERS, timeout: 8000,
      }),
    ]);
    const parse = (d) => ({
      up: Number(d.risingCount || d.advancingCount || 0),
      down: Number(d.fallingCount || d.decliningCount || 0),
      flat: Number(d.steadyCount || d.unchangedCount || 0),
    });
    const result = { kospi: parse(kospiRes.data), kosdaq: parse(kosdaqRes.data) };
    if (result.kospi.up > 0 || result.kospi.down > 0) {
      console.log(`  KOSPI 상승 ${result.kospi.up}개 / 하락 ${result.kospi.down}개 / 보합 ${result.kospi.flat}개`);
    }
    return result;
  } catch (_) {
    console.warn('  ⚠️ 시장 폭 데이터 실패 (건너뜀)');
    return null;
  }
}

// ── Google News RSS 뉴스 헤드라인 ────────────────────────────────────────────
async function fetchMarketNews() {
  const queries = ['코스피 증시 주식', '한국 경제 금융', '미국 증시 나스닥 S&P500'];
  try {
    const results = await Promise.allSettled(queries.map(q =>
      axios.get(`https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=ko&gl=KR&ceid=KR:ko`, {
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
        timeout: 8000,
      })
    ));
    const seen = new Set();
    const items = [];
    for (const r of results) {
      if (r.status !== 'fulfilled') continue;
      const $ = cheerio.load(r.value.data, { xmlMode: true });
      $('item').each((_, el) => {
        if (items.length >= 12) return;
        const title = $(el).find('title').text().replace(/\s*-\s*[^-]+$/, '').trim();
        if (title && !seen.has(title)) { seen.add(title); items.push({ title }); }
      });
    }
    console.log(`  뉴스 헤드라인 ${items.length}개 수집`);
    return items.slice(0, 10);
  } catch (_) {
    console.warn('  ⚠️ 뉴스 수집 실패 (건너뜀)');
    return [];
  }
}

// ── 전일 미국장 주요 지수 ────────────────────────────────────────────────────
async function fetchUsMarketData() {
  const symbols = [
    ['S&P 500', '^GSPC'],
    ['NASDAQ', '^IXIC'],
    ['Dow', '^DJI'],
  ];
  const expectedUsMarketDate = () => {
    const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/New_York',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      weekday: 'short',
      hour: '2-digit',
      hour12: false,
    }).formatToParts(new Date()).map(p => [p.type, p.value]));
    const date = new Date(Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)));
    const hour = Number(parts.hour === '24' ? '0' : parts.hour);
    const weekday = date.getUTCDay();
    if (hour < 16 || weekday === 0 || weekday === 6) date.setUTCDate(date.getUTCDate() - 1);
    while (date.getUTCDay() === 0 || date.getUTCDay() === 6) date.setUTCDate(date.getUTCDate() - 1);
    return date.toISOString().slice(0, 10);
  };

  try {
    const results = await Promise.allSettled(symbols.map(([name, symbol]) =>
      axios.get(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=5d&interval=1d`, {
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
        timeout: 8000,
      }).then((res) => {
        const result = res.data?.chart?.result?.[0];
        const quote = result?.indicators?.quote?.[0];
        const timestamps = result?.timestamp || [];
        const closes = quote?.close || [];
        const lastIndex = closes.map((v, i) => ({ v, i })).filter(x => Number.isFinite(x.v)).at(-1)?.i;
        if (lastIndex == null) return null;

        const close = closes[lastIndex];
        const prevClose = closes.slice(0, lastIndex).filter(Number.isFinite).at(-1);
        const changeRate = prevClose ? ((close - prevClose) / prevClose) * 100 : null;
        return {
          name,
          close,
          changeRate,
          date: timestamps[lastIndex] ? new Date(timestamps[lastIndex] * 1000).toISOString().slice(0, 10) : null,
        };
      })
    ));

    const indices = results
      .filter(r => r.status === 'fulfilled' && r.value)
      .map(r => r.value);
    if (!indices.length) return null;

    const latestDate = indices.map(i => i.date).filter(Boolean).sort().at(-1) || null;
    const expectedDate = expectedUsMarketDate();
    return { indices, latestDate, expectedDate, isHolidayOrStale: !!latestDate && latestDate !== expectedDate };
  } catch (_) {
    console.warn('  ⚠️ 미국장 데이터 실패 (건너뜀)');
    return null;
  }
}

function getAiBriefSlotMeta(slot) {
  if (slot === '09') {
    return {
      label: '장 오픈(09:00)',
      timeLabel: '09:00',
      focus: `오전 9시 장 오픈 브리핑입니다. 전일 미국장(S&P 500·NASDAQ·Dow)의 등락과 핵심 이슈가 국내장 출발에 주는 영향을 가장 먼저 설명하세요. 단, 미국장이 휴장으로 보이거나 미국장 데이터가 없으면 미국 지수 흐름을 억지로 쓰지 말고 주요 이슈와 국내장 출발 분위기 위주로 작성하세요.`,
    };
  }
  if (slot === '12') {
    return {
      label: '장중 점검(12:00)',
      timeLabel: '12:00',
      focus: '낮 12시 장중 브리핑입니다. 국장이 오전장을 지나며 어떤 흐름인지 코스피·코스닥 현재 등락, 시장 폭, 업종 등락, 수급을 중심으로 설명하세요. 미국장은 배경으로만 짧게 다루고 국내 장중 흐름을 우선하세요.',
    };
  }
  return {
    label: '장 마감(15:30)',
    timeLabel: '15:30',
    focus: '오후 3시 30분 장 마감 브리핑입니다. 장이 어떻게 마무리됐는지 최종 지수 흐름, 두드러진 업종, 수급·시장 폭을 종합해 마무리 멘트 느낌으로 정리하세요. 장중이라는 표현은 피하고 종가 기준의 정리 톤을 사용하세요.',
  };
}

function getKstDateInfo(date = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  }).formatToParts(date).map(p => [p.type, p.value]));
  const dateKey = `${parts.year}-${parts.month}-${parts.day}`;
  return { dateKey, isWeekend: parts.weekday === 'Sat' || parts.weekday === 'Sun' };
}

function getMarketClosedInfo(marketData = null) {
  const { dateKey, isWeekend } = getKstDateInfo();
  if (isWeekend) return { reason: 'weekend', dateKey };

  const tradedDates = [marketData?.kospi?.tradedDate, marketData?.kosdaq?.tradedDate].filter(Boolean);
  const statuses = [marketData?.kospi?.marketStatus, marketData?.kosdaq?.marketStatus].filter(Boolean);
  const hasTodayTrade = tradedDates.includes(dateKey);
  const isOpenNow = statuses.some(status => status === 'OPEN');
  if (tradedDates.length > 0 && !hasTodayTrade && !isOpenNow) {
    return { reason: 'holiday', dateKey };
  }
  return null;
}

function getMarketClosedBrief(reason) {
  if (reason === 'weekend') {
    return '주말이라 한국 주식시장이 열리지 않습니다. 장이 열리는 다음 거래일에 AI 시황 브리핑이 업데이트됩니다.';
  }
  return '국내 증시 휴장일이라 장이 열리지 않습니다. 장이 열리는 다음 거래일에 AI 시황 브리핑이 업데이트됩니다.';
}

// ── Firestore investor_flow 데이터 ───────────────────────────────────────────
async function fetchInvestorFlow() {
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
    });
    const dateKey = formatter.format(new Date());
    const snap = await db.collection('investor_flow').doc(dateKey).get();
    return snap.exists ? snap.data() : null;
  } catch (_) { return null; }
}

// ── Claude로 시황 생성 ───────────────────────────────────────────────────────
async function generateBrief(marketData, sectorData, breadthData, investorFlow, news, usMarketData, slot) {
  const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
  const { kospi, kosdaq } = marketData;
  const slotMeta = getAiBriefSlotMeta(slot);

  let investorContext = '';
  if (investorFlow) {
    const fi = investorFlow;
    const fKospi = fi.kospi?.foreignNet != null ? (fi.kospi.foreignNet / 1e8).toFixed(0) + '억원' : null;
    const iKospi = fi.kospi?.institutionNet != null ? (fi.kospi.institutionNet / 1e8).toFixed(0) + '억원' : null;
    const fKosdaq = fi.kosdaq?.foreignNet != null ? (fi.kosdaq.foreignNet / 1e8).toFixed(0) + '억원' : null;
    if (fKospi || iKospi || fKosdaq) {
      investorContext = '\n\n[매매동향]';
      if (fKospi) investorContext += `\n- KOSPI 외국인 순매수: ${fKospi}`;
      if (iKospi) investorContext += `\n- KOSPI 기관 순매수: ${iKospi}`;
      if (fKosdaq) investorContext += `\n- KOSDAQ 외국인 순매수: ${fKosdaq}`;
    }
  }

  let sectorContext = '';
  if (sectorData) {
    const fmt = (list) => list.map(s => `${s.name}(${s.rate > 0 ? '+' : ''}${s.rate.toFixed(1)}%)`).join(', ');
    const parts = [];
    if (sectorData.kospi?.up?.length) parts.push(`KOSPI 상승: ${fmt(sectorData.kospi.up)}`);
    if (sectorData.kospi?.down?.length) parts.push(`KOSPI 하락: ${fmt(sectorData.kospi.down)}`);
    if (sectorData.kosdaq?.up?.length) parts.push(`KOSDAQ 상승: ${fmt(sectorData.kosdaq.up)}`);
    if (sectorData.kosdaq?.down?.length) parts.push(`KOSDAQ 하락: ${fmt(sectorData.kosdaq.down)}`);
    if (parts.length) sectorContext = '\n\n[업종 등락]\n- ' + parts.join('\n- ');
  }

  let breadthContext = '';
  if (breadthData) {
    const b = breadthData;
    if (b.kospi?.up || b.kospi?.down) {
      breadthContext += `\n\n[시장 폭]\n- KOSPI 상승:${b.kospi.up}개 / 하락:${b.kospi.down}개 / 보합:${b.kospi.flat}개`;
    }
    if (b.kosdaq?.up || b.kosdaq?.down) {
      breadthContext += `\n- KOSDAQ 상승:${b.kosdaq.up}개 / 하락:${b.kosdaq.down}개 / 보합:${b.kosdaq.flat}개`;
    }
  }

  let newsContext = '';
  if (news && news.length > 0) {
    newsContext = '\n\n[최신 뉴스 헤드라인]\n' + news.map((n, i) => `${i + 1}. ${n.title}`).join('\n');
  }

  let usContext = '';
  if (usMarketData?.indices?.length) {
    const fmt = usMarketData.indices
      .map(i => `${i.name}: ${i.changeRate == null ? i.close.toFixed(2) : `${i.changeRate >= 0 ? '+' : ''}${i.changeRate.toFixed(2)}%`}`)
      .join(', ');
    const staleNote = usMarketData.isHolidayOrStale ? ' (최근 거래일 데이터가 오래되어 휴장 가능성이 있습니다)' : '';
    usContext = `\n\n[전일 미국장]\n- 기준일: ${usMarketData.latestDate || '확인 불가'}${staleNote}\n- ${fmt}`;
  }

  const prompt = `지금은 한국 주식시장 ${slotMeta.label}입니다. 아래 데이터와 뉴스 헤드라인을 바탕으로 투자자를 위한 시황 브리핑을 작성해주세요.

[시간대별 작성 관점]
${slotMeta.focus}

[지수]
- 코스피: ${kospi.price.toLocaleString('ko-KR')}pt (${kospi.isUp ? '▲' : '▼'}${Math.abs(kospi.changeRate).toFixed(2)}%, ${kospi.change >= 0 ? '+' : ''}${kospi.change.toFixed(2)}pt)
- 코스닥: ${kosdaq.price.toLocaleString('ko-KR')}pt (${kosdaq.isUp ? '▲' : '▼'}${Math.abs(kosdaq.changeRate).toFixed(2)}%, ${kosdaq.change >= 0 ? '+' : ''}${kosdaq.change.toFixed(2)}pt)${usContext}${sectorContext}${breadthContext}${investorContext}${newsContext}

[작성 형식 — 반드시 아래 3개 문단을 빈 줄로 구분해서 출력]

문단1 (핵심 흐름): 시간대별 작성 관점을 반영해 가장 중요한 흐름부터 서술. 09시는 전일 미국장과 국내장 출발 연결, 12시는 국내 장중 흐름, 15:30은 장 마감 결과를 우선하세요.

문단2 (업종): 가장 두드러진 상승·하락 업종을 등락률 숫자와 함께 구체적으로 서술. 가능하면 상승 업종 1~2개와 하락 업종 1~2개를 모두 언급하고, "얼마나 올랐는지/내렸는지"가 보이게 작성. 업종 간 대조 포함. (제공된 데이터에 없는 업종명 절대 사용 금지)

문단3 (정리): 09시는 개장 초 체크할 이슈, 12시는 오후장으로 이어질 장중 포인트, 15:30은 하루를 마무리하는 정리 멘트로 작성. 뉴스가 있으면 핵심 뉴스 헤드라인의 구체 키워드(예: 미국증시, S&P500, 환율, 금리, 실적 등)를 포함하되, "투자심리에 우호적/부정적", "작용했습니다"처럼 딱딱하거나 단정적인 표현은 피하세요. "미국증시 강세 전망도 함께 거론됐습니다", "S&P500 목표치 상향 소식도 눈에 띄었습니다"처럼 자연스럽게 연결하고, 단순 헤드라인 나열은 하지 마세요.

[공통 규칙]
- 각 문단은 2~3문장
- 반드시 높임말(~습니다/~네요/~보입니다) 사용
- 사실 기반 서술만, 투자 권유·예측 금지
- 마침표로 끝낼 것
- "오늘은", "현재" 등으로 시작하지 말 것

3개 문단만 출력 (제목·번호·다른 설명 없이, 문단 사이 빈 줄 하나):`;

  const message = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 900,
    messages: [{ role: 'user', content: prompt }],
  });
  return message.content[0].text.trim();
}

// ── Firestore 저장 ───────────────────────────────────────────────────────────
async function saveBrief(brief, marketData, sectorData, breadthData, slot) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
  });
  const dateKey = formatter.format(new Date());
  const slotLabel = getAiBriefSlotMeta(slot).timeLabel;
  const payload = {
    brief,
    slot,
    slotLabel,
    date: dateKey,
    kospi: marketData.kospi,
    kosdaq: marketData.kosdaq,
    sectors: sectorData ?? null,
    generatedAt: new Date(),
  };
  const batch = db.batch();
  batch.set(db.collection('ai_briefs').doc('latest'), payload);
  batch.set(db.collection('ai_briefs').doc(dateKey), { [slot]: payload, updatedAt: new Date() }, { merge: true });
  await batch.commit();
  return dateKey;
}

async function saveMarketClosedBrief(slot, closedInfo, marketData = null) {
  const dateKey = closedInfo.dateKey;
  const slotLabel = getAiBriefSlotMeta(slot).timeLabel;
  const payload = {
    brief: getMarketClosedBrief(closedInfo.reason),
    slot,
    slotLabel,
    date: dateKey,
    isMarketClosed: true,
    closedReason: closedInfo.reason,
    kospi: marketData?.kospi ?? null,
    kosdaq: marketData?.kosdaq ?? null,
    sectors: null,
    generatedAt: new Date(),
  };
  const batch = db.batch();
  batch.set(db.collection('ai_briefs').doc('latest'), payload);
  batch.set(db.collection('ai_briefs').doc(dateKey), { [slot]: payload, updatedAt: new Date() }, { merge: true });
  await batch.commit();
  return dateKey;
}

// ── 메인 ─────────────────────────────────────────────────────────────────────
(async () => {
  try {
    // 현재 KST 시간으로 슬롯 결정
    const kstHour = Number(new Intl.DateTimeFormat('en', {
      timeZone: 'Asia/Seoul', hour: 'numeric', hour12: false,
    }).format(new Date()));
    const slot = kstHour < 11 ? '09' : kstHour < 14 ? '12' : '15';

    const weekendClosed = getMarketClosedInfo();
    if (weekendClosed) {
      const dateKey = await saveMarketClosedBrief(slot, weekendClosed);
      console.log(`  ai_briefs/latest 및 ai_briefs/${dateKey} 휴장 안내 저장 완료!`);
      process.exit(0);
    }

    console.log('📡 네이버 금융에서 지수 데이터 가져오는 중...');
    const marketData = await fetchMarketData();
    const marketClosed = getMarketClosedInfo(marketData);
    if (marketClosed) {
      const dateKey = await saveMarketClosedBrief(slot, marketClosed, marketData);
      console.log(`  ai_briefs/latest 및 ai_briefs/${dateKey} 휴장 안내 저장 완료!`);
      process.exit(0);
    }
    console.log(`  코스피 ${marketData.kospi.price.toLocaleString()}pt (${marketData.kospi.changeRate >= 0 ? '+' : ''}${marketData.kospi.changeRate.toFixed(2)}%)`);
    console.log(`  코스닥 ${marketData.kosdaq.price.toLocaleString()}pt (${marketData.kosdaq.changeRate >= 0 ? '+' : ''}${marketData.kosdaq.changeRate.toFixed(2)}%)`);

    console.log('\n📈 업종별 시세 가져오는 중...');
    const sectorData = await fetchSectorData();
    if (sectorData) {
      console.log(`  KOSPI 상승: ${(sectorData.kospi?.up || []).map(s => s.name).join(', ') || '없음'}`);
      console.log(`  KOSPI 하락: ${(sectorData.kospi?.down || []).map(s => s.name).join(', ') || '없음'}`);
      console.log(`  KOSDAQ 상승: ${(sectorData.kosdaq?.up || []).map(s => s.name).join(', ') || '없음'}`);
    }

    console.log('\n📊 시장 폭 (상승/하락 종목수) 가져오는 중...');
    const breadthData = await fetchMarketBreadth();

    console.log('\n📰 뉴스 헤드라인 수집 중...');
    const [investorFlow, news, usMarketData] = await Promise.all([fetchInvestorFlow(), fetchMarketNews(), fetchUsMarketData()]);
    console.log(investorFlow ? '  매매동향 데이터 있음' : '  매매동향 데이터 없음 (지수만 사용)');

    console.log(`\n🤖 Claude Haiku로 시황 생성 중... (슬롯: ${getAiBriefSlotMeta(slot).timeLabel})`);
    const brief = await generateBrief(marketData, sectorData, breadthData, investorFlow, news, usMarketData, slot);
    console.log(`\n✅ 생성된 시황:\n  "${brief}"`);

    console.log('\n💾 Firestore에 저장 중...');
    const dateKey = await saveBrief(brief, marketData, sectorData, breadthData, slot);
    console.log(`  ai_briefs/latest 및 ai_briefs/${dateKey} 저장 완료!`);
    console.log('\n🎉 앱 홈화면에 바로 반영됩니다.');
    process.exit(0);
  } catch (e) {
    console.error('\n❌ 오류:', e.message);
    if (e.response?.data) console.error('  응답:', JSON.stringify(e.response.data));
    process.exit(1);
  }
})();
