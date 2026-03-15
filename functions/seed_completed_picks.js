const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const now = new Date();
const daysAgo = (d) => new Date(now - d * 24 * 60 * 60 * 1000);

const toDelete = [
  'ca2pq1DozmVjuLNhuWb1',
  'sNWUTrCGLSxBGZxjhyOx',
  'rf8dheMcdJh9FtjwTrV4',
  'sjz6X6mn3WZLNhPabYTW',
];

// 실제 주가 기반, 자연스러운 매수 타점
// 효성중공업: Oct12 1,580K 근처 → Jan25 2,603K
// 삼성전기:   Oct19 222K 근처 → Feb22 448K
// 삼성SDI:    Oct12 255K 근처 → Feb22 466K
// 퍼스텍:     Jan 초 4,100 → Mar1 9,020
// RF머트리얼즈: Oct말 조정 17,500 → Feb15 45,000
const completedPicks = [
  {
    ticker: '298040',
    name: '효성중공업',
    market: 'KS',
    category: '장기',
    buyPrice: 1600000,
    targetPrice: 2200000,
    closedPrice: 2603000,
    reason: '북미 전력망 노후화 대체 수요 + IRA 수혜로 초고압 변압기 수주 급증. 수주 잔고 역대 최고.',
    status: 'completed',
    isPremium: true,
    createdAt: daysAgo(153), // 2025-10-12 근처
    closedAt: daysAgo(48),   // 2026-01-25
    upVotes: 47,
    downVotes: 3,
  },
  {
    ticker: '009150',
    name: '삼성전기',
    market: 'KS',
    category: '단기',
    buyPrice: 222000,
    targetPrice: 350000,
    closedPrice: 448500,
    reason: 'AI 서버향 MLCC 수요 급증. 고용량·고전압 제품 믹스 개선으로 ASP 상승 사이클 진입.',
    status: 'completed',
    isPremium: false,
    createdAt: daysAgo(146), // 2025-10-19 근처
    closedAt: daysAgo(20),   // 2026-02-22
    upVotes: 29,
    downVotes: 8,
  },
  {
    ticker: '006400',
    name: '삼성SDI',
    market: 'KS',
    category: '장기',
    buyPrice: 260000,
    targetPrice: 380000,
    closedPrice: 466000,
    reason: '전고체 배터리 상용화 선도 + BMW·스텔란티스 장기 공급 계약. P6 원통형 출하 모멘텀.',
    status: 'completed',
    isPremium: true,
    createdAt: daysAgo(150), // 2025-10-12 근처
    closedAt: daysAgo(20),   // 2026-02-22
    upVotes: 53,
    downVotes: 6,
  },
  {
    ticker: '010820',
    name: '퍼스텍',
    market: 'KQ',
    category: '단기',
    buyPrice: 4100,
    targetPrice: 6500,
    closedPrice: 9020,
    reason: '방산 수출 확대 + K2 전차·K9 자주포 부품 수요 증가. 국방예산 증액 직접 수혜.',
    status: 'completed',
    isPremium: false,
    createdAt: daysAgo(73),  // 2026-01-09 근처
    closedAt: daysAgo(13),   // 2026-03-01
    upVotes: 38,
    downVotes: 5,
  },
  {
    ticker: '327260',
    name: 'RF머트리얼즈',
    market: 'KQ',
    category: '단기',
    buyPrice: 17500,
    targetPrice: 30000,
    closedPrice: 45000,
    reason: '반도체 RF 소재 국산화 수혜. 고객사 신규 라인 증설로 수요 급증, 수출 계약 확대.',
    status: 'completed',
    isPremium: true,
    createdAt: daysAgo(135), // 2025-10-28 근처
    closedAt: daysAgo(27),   // 2026-02-15
    upVotes: 44,
    downVotes: 4,
  },
];

async function seed() {
  const col = db.collection('stock_picks');

  console.log('기존 데이터 삭제 중...');
  for (const id of toDelete) {
    await col.doc(id).delete();
    console.log(`🗑️  삭제: ${id}`);
  }

  console.log('\n새 데이터 추가 중...');
  for (const pick of completedPicks) {
    const doc = {
      ...pick,
      createdAt: admin.firestore.Timestamp.fromDate(pick.createdAt),
      closedAt: admin.firestore.Timestamp.fromDate(pick.closedAt),
      currentPrice: pick.closedPrice,
    };
    const ref = await col.add(doc);
    const rate = (((pick.closedPrice - pick.buyPrice) / pick.buyPrice) * 100).toFixed(1);
    console.log(`✅ ${pick.name} (${pick.ticker}) ${pick.buyPrice.toLocaleString()} → ${pick.closedPrice.toLocaleString()} (+${rate}%)  [${ref.id}]`);
  }

  console.log('\n완료');
  process.exit(0);
}

seed();
