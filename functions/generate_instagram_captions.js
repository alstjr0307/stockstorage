/**
 * 주식저장소 — 인스타그램 캡션 자동 생성기
 *
 * 사용법:
 *   node generate_instagram_captions.js              → 활성 추천주 캡션 생성
 *   node generate_instagram_captions.js --completed  → 수익 실현 완료 종목 캡션 생성
 *   node generate_instagram_captions.js --all        → 전체 종목 캡션 생성
 *
 * 결과물: captions_YYYY-MM-DD.txt 파일로 저장
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ─────────────────────────────────────────
// 설정
// ─────────────────────────────────────────
const CONFIG = {
  // 인스타그램 계정 이름 (캡션 하단에 들어감)
  accountTag: '@주식저장소',

  // 앱 다운로드 링크 (바이오 링크로 안내)
  appLink: '링크는 바이오 참고 👆',

  // 해시태그 세트
  hashtags: {
    // 활성 추천주용
    active: `#주식저장소 #주식추천 #오늘의추천주 #추천주 #주식투자
#국내주식 #KOSPI #KOSDAQ #주식공부 #주린이
#재테크 #투자공부 #종목추천 #주식정보 #개인투자자`,

    // 단기 종목 추가 태그
    short: `#단기주식 #단기매매 #스윙매매`,

    // 장기 종목 추가 태그
    long: `#장기투자 #가치투자 #장기보유`,

    // 수익 실현 완료용
    completed: `#주식저장소 #수익실현 #추천주결과 #주식성과 #투자수익
#국내주식 #재테크 #주식투자 #종목추천 #투자결과
#주린이 #주식공부 #개인투자자 #수익인증 #성공투자`,
  },
};

// ─────────────────────────────────────────
// 숫자 포맷 유틸
// ─────────────────────────────────────────
function formatPrice(price) {
  if (!price && price !== 0) return '-';
  if (price >= 100000000) return `${(price / 100000000).toFixed(1)}억원`;
  if (price >= 10000) return `${Math.round(price / 10000).toLocaleString()}만원`;
  return `${price.toLocaleString()}원`;
}

function formatRate(from, to) {
  if (!from || !to) return null;
  const rate = ((to - from) / from) * 100;
  const sign = rate >= 0 ? '+' : '';
  return `${sign}${rate.toFixed(1)}%`;
}

function formatDate(ts) {
  if (!ts) return '';
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, '0')}.${String(d.getDate()).padStart(2, '0')}`;
}

function marketLabel(market) {
  if (!market) return '';
  const m = market.toUpperCase();
  if (m === 'KS' || m === 'KOSPI') return 'KOSPI';
  if (m === 'KQ' || m === 'KOSDAQ') return 'KOSDAQ';
  return market.toUpperCase();
}

// ─────────────────────────────────────────
// 캡션 생성 — 활성 추천주 (현재 진행 중)
// ─────────────────────────────────────────
function buildActiveCaption(pick) {
  const rate = pick.currentPrice
    ? formatRate(pick.buyPrice, pick.currentPrice)
    : null;

  const categoryEmoji = pick.category === '장기' ? '📈' : '⚡';
  const premiumBadge = pick.isPremium ? '⭐ 프리미엄 종목\n' : '';

  const lines = [
    `${categoryEmoji} [${pick.category || '추천'} 종목] ${pick.name} (${marketLabel(pick.market)})`,
    ``,
    `${premiumBadge}`,
    `💡 추천 이유`,
    `${pick.reason || ''}`,
    ``,
    `📊 현황`,
    `• 매수가   ${formatPrice(pick.buyPrice)}`,
    `• 목표가   ${formatPrice(pick.targetPrice)}`,
    rate
      ? `• 현재가   ${formatPrice(pick.currentPrice)}  (${rate})`
      : `• 목표 수익률  ${formatRate(pick.buyPrice, pick.targetPrice) || '-'}`,
    ``,
    `📅 추천일  ${formatDate(pick.createdAt)}`,
    ``,
    `더 많은 추천주는 주식저장소 앱에서 👇`,
    `${CONFIG.appLink}`,
    ``,
    CONFIG.hashtags.active,
    pick.category === '단기' ? CONFIG.hashtags.short : CONFIG.hashtags.long,
  ];

  return lines.filter((l) => l !== null).join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

// ─────────────────────────────────────────
// 캡션 생성 — 수익 실현 완료 종목
// ─────────────────────────────────────────
function buildCompletedCaption(pick) {
  const totalRate = formatRate(pick.buyPrice, pick.closedPrice);
  const targetRate = formatRate(pick.buyPrice, pick.targetPrice);
  const exceeded = pick.closedPrice > pick.targetPrice;

  const resultEmoji = exceeded ? '🚀' : '✅';
  const exceedNote = exceeded
    ? `목표가 초과 달성! (목표 ${targetRate})`
    : '목표가 달성 완료';

  const holdingDays = (() => {
    if (!pick.createdAt || !pick.closedAt) return null;
    const from = pick.createdAt.toDate ? pick.createdAt.toDate() : new Date(pick.createdAt);
    const to = pick.closedAt.toDate ? pick.closedAt.toDate() : new Date(pick.closedAt);
    return Math.round((to - from) / (1000 * 60 * 60 * 24));
  })();

  const lines = [
    `${resultEmoji} 수익 실현 완료 — ${pick.name} (${marketLabel(pick.market)})`,
    ``,
    `💰 ${totalRate} 수익  |  ${exceedNote}`,
    ``,
    `📊 결과 요약`,
    `• 추천가   ${formatPrice(pick.buyPrice)}`,
    `• 목표가   ${formatPrice(pick.targetPrice)}  (${targetRate})`,
    `• 실현가   ${formatPrice(pick.closedPrice)}  (${totalRate})`,
    holdingDays ? `• 보유기간  ${holdingDays}일` : '',
    ``,
    `📌 추천 근거`,
    `${pick.reason || ''}`,
    ``,
    `추천일  ${formatDate(pick.createdAt)}  →  실현일  ${formatDate(pick.closedAt)}`,
    ``,
    `다음 추천주도 주식저장소 앱에서 👇`,
    `${CONFIG.appLink}`,
    ``,
    CONFIG.hashtags.completed,
  ];

  return lines.filter((l) => l !== '').join('\n').replace(/\n{3,}/g, '\n\n').trim();
}

// ─────────────────────────────────────────
// 메인
// ─────────────────────────────────────────
async function main() {
  const args = process.argv.slice(2);
  const showAll = args.includes('--all');
  const showCompleted = args.includes('--completed') || showAll;
  const showActive = !args.includes('--completed') || showAll;

  console.log('🔍 Firestore에서 추천주 데이터 불러오는 중...\n');

  const snapshot = await db.collection('stock_picks').orderBy('createdAt', 'desc').get();

  if (snapshot.empty) {
    console.log('❌ stock_picks 컬렉션에 데이터가 없습니다.');
    process.exit(0);
  }

  const picks = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
  console.log(`총 ${picks.length}개 종목 로드 완료\n`);

  const activePicks = picks.filter((p) => p.status === 'active' || p.status === 'open');
  const completedPicks = picks.filter((p) => p.status === 'completed');

  console.log(`✅ 진행 중: ${activePicks.length}개  |  완료: ${completedPicks.length}개\n`);
  console.log('─'.repeat(60));

  const outputLines = [];
  const today = new Date().toISOString().slice(0, 10);
  outputLines.push(`주식저장소 인스타그램 캡션  (생성일: ${today})`);
  outputLines.push('='.repeat(60));

  // ── 활성 추천주 ──
  if (showActive && activePicks.length > 0) {
    outputLines.push('\n[ 📈 현재 진행 중인 추천주 ]\n');
    activePicks.forEach((pick, i) => {
      const caption = buildActiveCaption(pick);
      outputLines.push(`─── 종목 ${i + 1}: ${pick.name} (${pick.ticker}) ───`);
      outputLines.push(caption);
      outputLines.push('');
      console.log(`📌 ${pick.name} (${pick.ticker})  |  ${pick.category}  |  매수가 ${formatPrice(pick.buyPrice)}  →  목표 ${formatPrice(pick.targetPrice)}`);
    });
  }

  // ── 완료 종목 ──
  if (showCompleted && completedPicks.length > 0) {
    outputLines.push('\n[ 🏆 수익 실현 완료 종목 ]\n');
    completedPicks.forEach((pick, i) => {
      const caption = buildCompletedCaption(pick);
      const rate = formatRate(pick.buyPrice, pick.closedPrice);
      outputLines.push(`─── 완료 ${i + 1}: ${pick.name} (${pick.ticker}) ───`);
      outputLines.push(caption);
      outputLines.push('');
      console.log(`🏆 ${pick.name}  |  ${formatPrice(pick.buyPrice)} → ${formatPrice(pick.closedPrice)}  (${rate})`);
    });
  }

  // ── 파일 저장 ──
  const filename = `captions_${today}.txt`;
  const outPath = path.join(__dirname, filename);
  fs.writeFileSync(outPath, outputLines.join('\n'), 'utf8');

  console.log('\n' + '─'.repeat(60));
  console.log(`\n✅ 완료! 캡션 파일 저장됨: ${filename}`);
  console.log(`📂 경로: ${outPath}\n`);

  process.exit(0);
}

main().catch((err) => {
  console.error('❌ 오류:', err.message);
  process.exit(1);
});
