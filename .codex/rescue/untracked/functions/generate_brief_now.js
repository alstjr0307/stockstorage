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
  });
  return { kospi: parse(kospiRes.data), kosdaq: parse(kosdaqRes.data) };
}

// ── 네이버 금융 업종별 시세 스크래핑 ─────────────────────────────────────────
async function fetchSectorData() {
  try {
    // KOSPI 업종 + KOSDAQ 업종 동시 요청
    const [kospiRes, kosdaqRes] = await Promise.all([
      axios.get('https://finance.naver.com/sise/sise_group.nhn?type=upjong', {
        headers: NAVER_PC_HEADERS,
        responseType: 'arraybuffer',
        timeout: 8000,
      }),
      axios.get('https://finance.naver.com/sise/sise_group.nhn?type=upjong&sosok=1', {
        headers: NAVER_PC_HEADERS,
        responseType: 'arraybuffer',
        timeout: 8000,
      }),
    ]);

    const decoder = new TextDecoder('euc-kr');

    const parseSectors = (buffer) => {
      const html = decoder.decode(buffer);
      const $ = cheerio.load(html);
      const sectors = [];
      $('table.type_1 tbody tr').each((_, row) => {
        const cells = $(row).find('td');
        if (cells.length < 5) return;
        const name = $(cells[0]).find('a').text().trim();
        const rateText = $(cells[4]).text().trim().replace('%', '').replace(',', '');
        const rate = parseFloat(rateText);
        if (name && !isNaN(rate)) sectors.push({ name, rate });
      });
      return sectors;
    };

    const kospiSectors = parseSectors(kospiRes.data);
    const kosdaqSectors = parseSectors(kosdaqRes.data);
    const all = [...kospiSectors, ...kosdaqSectors];

    const up = all.filter(s => s.rate > 0).sort((a, b) => b.rate - a.rate).slice(0, 4);
    const down = all.filter(s => s.rate < 0).sort((a, b) => a.rate - b.rate).slice(0, 4);

    return { up, down, total: all.length };
  } catch (e) {
    console.warn('  ⚠️ 업종 데이터 실패:', e.message);
    return null;
  }
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

// ── Claude로 한 줄 시황 생성 ─────────────────────────────────────────────────
async function generateBrief(marketData, sectorData, investorFlow, slot) {
  const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY });
  const { kospi, kosdaq } = marketData;
  const slotLabel = slot === '09' ? '장 시작 직후' : slot === '12' ? '점심 무렵' : '장 마감 직전';

  // 매매동향
  let investorContext = '';
  if (investorFlow) {
    investorContext = `
- KOSPI 외국인 순매수: ${investorFlow.kospi?.foreignNet ? (investorFlow.kospi.foreignNet / 1e8).toFixed(0) + '억원' : '데이터 없음'}
- KOSPI 기관 순매수: ${investorFlow.kospi?.institutionNet ? (investorFlow.kospi.institutionNet / 1e8).toFixed(0) + '억원' : '데이터 없음'}
- KOSDAQ 외국인 순매수: ${investorFlow.kosdaq?.foreignNet ? (investorFlow.kosdaq.foreignNet / 1e8).toFixed(0) + '억원' : '데이터 없음'}`;
  }

  // 업종 데이터
  let sectorContext = '';
  if (sectorData && (sectorData.up.length > 0 || sectorData.down.length > 0)) {
    const upStr = sectorData.up.map(s => `${s.name}(+${s.rate.toFixed(1)}%)`).join(', ');
    const downStr = sectorData.down.map(s => `${s.name}(${s.rate.toFixed(1)}%)`).join(', ');
    sectorContext = `
- 상승 업종 TOP: ${upStr || '없음'}
- 하락 업종 TOP: ${downStr || '없음'}`;
  }

  const prompt = `지금은 한국 주식시장 ${slotLabel}입니다. 다음 시장 데이터를 바탕으로 투자자가 한눈에 파악할 수 있는 시황을 작성해주세요.

[현재 시장 데이터]
- 코스피: ${kospi.price.toLocaleString('ko-KR')}pt (${kospi.isUp ? '상승' : '하락'} ${Math.abs(kospi.changeRate).toFixed(2)}%, ${kospi.change >= 0 ? '+' : ''}${kospi.change.toFixed(2)}pt)
- 코스닥: ${kosdaq.price.toLocaleString('ko-KR')}pt (${kosdaq.isUp ? '상승' : '하락'} ${Math.abs(kosdaq.changeRate).toFixed(2)}%, ${kosdaq.change >= 0 ? '+' : ''}${kosdaq.change.toFixed(2)}pt)${investorContext}${sectorContext}

[작성 규칙]
- 2~3문장, 총 60자 이상 120자 이하
- 첫 문장: 지수 전체 흐름 요약
- 둘째 문장: 두드러진 상승/하락 업종 언급 (데이터에 있는 실제 업종명 사용)
- 셋째 문장(선택): 매수 주체 흐름이 뚜렷할 때만 추가
- 투자 권유·예측 금지, 사실 기반 서술만
- 구어체로 친근하게, 마침표로 끝낼 것
- "오늘은", "현재" 등 군더더기 없이 바로 시황 내용으로 시작

시황만 출력하세요 (다른 설명 없이):`;

  const message = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 300,
    messages: [{ role: 'user', content: prompt }],
  });
  return message.content[0].text.trim();
}

// ── Firestore 저장 ───────────────────────────────────────────────────────────
async function saveBrief(brief, marketData, sectorData, slot) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
  });
  const dateKey = formatter.format(new Date());
  const slotLabel = slot === '09' ? '09:00' : slot === '12' ? '12:00' : '15:00';
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

// ── 메인 ─────────────────────────────────────────────────────────────────────
(async () => {
  try {
    // 현재 KST 시간으로 슬롯 결정
    const kstHour = Number(new Intl.DateTimeFormat('en', {
      timeZone: 'Asia/Seoul', hour: 'numeric', hour12: false,
    }).format(new Date()));
    const slot = kstHour < 11 ? '09' : kstHour < 14 ? '12' : '15';

    console.log('📡 네이버 금융에서 지수 데이터 가져오는 중...');
    const marketData = await fetchMarketData();
    console.log(`  코스피 ${marketData.kospi.price.toLocaleString()}pt (${marketData.kospi.changeRate >= 0 ? '+' : ''}${marketData.kospi.changeRate.toFixed(2)}%)`);
    console.log(`  코스닥 ${marketData.kosdaq.price.toLocaleString()}pt (${marketData.kosdaq.changeRate >= 0 ? '+' : ''}${marketData.kosdaq.changeRate.toFixed(2)}%)`);

    console.log('\n📈 업종별 시세 가져오는 중...');
    const sectorData = await fetchSectorData();
    if (sectorData) {
      console.log(`  상승 업종: ${sectorData.up.map(s => s.name).join(', ')}`);
      console.log(`  하락 업종: ${sectorData.down.map(s => s.name).join(', ')}`);
    }

    console.log('\n📊 Firestore investor_flow 데이터 조회 중...');
    const investorFlow = await fetchInvestorFlow();
    console.log(investorFlow ? '  매매동향 데이터 있음' : '  매매동향 데이터 없음 (지수만 사용)');

    console.log(`\n🤖 Claude Haiku로 시황 생성 중... (슬롯: ${slot}:00)`);
    const brief = await generateBrief(marketData, sectorData, investorFlow, slot);
    console.log(`\n✅ 생성된 시황:\n  "${brief}"`);

    console.log('\n💾 Firestore에 저장 중...');
    const dateKey = await saveBrief(brief, marketData, sectorData, slot);
    console.log(`  ai_briefs/latest 및 ai_briefs/${dateKey} 저장 완료!`);
    console.log('\n🎉 앱 홈화면에 바로 반영됩니다.');
    process.exit(0);
  } catch (e) {
    console.error('\n❌ 오류:', e.message);
    if (e.response?.data) console.error('  응답:', JSON.stringify(e.response.data));
    process.exit(1);
  }
})();
