const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const journals = [
  {
    uid: 'seed_user_1', nickname: '파랑새',
    stockName: '삼성전자', ticker: '005930', market: 'KS',
    action: '매수', price: 71200, quantity: 30,
    tradeDate: new Date('2025-01-08'),
    note: 'hbm 기대감에 들어감. 일단 지켜보는 중',
    isPublic: true, likes: 4, createdAt: new Date('2025-01-08T09:35:00'),
  },
  {
    uid: 'seed_user_2', nickname: '현규',
    stockName: 'SK하이닉스', ticker: '000660', market: 'KS',
    action: '매수', price: 198000, quantity: 10,
    tradeDate: new Date('2025-01-10'),
    note: '엔비디아 실적 앞두고 선취매. 근데 너무 비싸게 들어간 것 같기도 하고... 물타기 각 보는 중',
    isPublic: true, likes: 11, createdAt: new Date('2025-01-10T10:12:00'),
  },
  {
    uid: 'seed_user_3', nickname: '강남아재',
    stockName: '카카오', ticker: '035720', market: 'KS',
    action: '매수', price: 34500, quantity: 50,
    tradeDate: new Date('2025-01-14'),
    note: '34000 밑으로 내려오면 추가 매수 예정',
    isPublic: true, likes: 2, createdAt: new Date('2025-01-14T14:20:00'),
  },
  {
    uid: 'seed_user_4', nickname: 'NVDA홀더',
    stockName: 'NVIDIA', ticker: 'NVDA', market: 'US',
    action: '매수', price: 138.5, quantity: 20,
    tradeDate: new Date('2025-01-16'),
    note: 'Blackwell 출하 본격화되는 시점. 조정마다 모으는 중. 목표가는 따로 없고 그냥 계속 들고갈 생각.',
    isPublic: true, likes: 18, createdAt: new Date('2025-01-16T22:10:00'),
  },
  {
    uid: 'seed_user_5', nickname: '배당러',
    stockName: '삼성전자우', ticker: '005935', market: 'KS',
    action: '매수', price: 52800, quantity: 40,
    tradeDate: new Date('2025-01-20'),
    note: '',
    isPublic: true, likes: 1, createdAt: new Date('2025-01-20T09:50:00'),
  },
  {
    uid: 'seed_user_1', nickname: '파랑새',
    stockName: '현대차', ticker: '005380', market: 'KS',
    action: '매도', price: 215000, quantity: 15,
    tradeDate: new Date('2025-01-22'),
    note: '+12% 먹고 나옴. 관세 터지기 전에 잘 팔았다고 생각',
    isPublic: true, likes: 6, createdAt: new Date('2025-01-22T13:45:00'),
  },
  {
    uid: 'seed_user_6', nickname: '방산투자자',
    stockName: '한화에어로스페이스', ticker: '012450', market: 'KS',
    action: '매수', price: 312000, quantity: 8,
    tradeDate: new Date('2025-01-24'),
    note: '폴란드 2차 계약 소식 나오면 더 오를 것 같음. 유럽 방산 예산 계속 늘어나는 추세라 장기로 가져갈 생각.',
    isPublic: true, likes: 9, createdAt: new Date('2025-01-24T10:30:00'),
  },
  {
    uid: 'seed_user_7', nickname: 'US주식만',
    stockName: 'Apple', ticker: 'AAPL', market: 'US',
    action: '매수', price: 224.5, quantity: 15,
    tradeDate: new Date('2025-01-27'),
    note: '그냥 쌀 때 모으는 거임',
    isPublic: true, likes: 7, createdAt: new Date('2025-01-27T21:00:00'),
  },
  {
    uid: 'seed_user_2', nickname: '현규',
    stockName: 'LG에너지솔루션', ticker: '373220', market: 'KS',
    action: '매수', price: 315000, quantity: 5,
    tradeDate: new Date('2025-01-29'),
    note: '전기차 둔화 너무 과하게 반영된 것 같아서. 근데 생각보다 더 빠지네 ㅠ',
    isPublic: true, likes: 3, createdAt: new Date('2025-01-29T11:00:00'),
  },
  {
    uid: 'seed_user_8', nickname: '기술적분석충',
    stockName: '셀트리온', ticker: '068270', market: 'KS',
    action: '매도', price: 158000, quantity: 20,
    tradeDate: new Date('2025-02-03'),
    note: '200일선 저항 못 뚫고 내려오길래 일단 반절 매도. 나머지는 조금 더 지켜볼 예정',
    isPublic: true, likes: 4, createdAt: new Date('2025-02-03T14:55:00'),
  },
  {
    uid: 'seed_user_3', nickname: '강남아재',
    stockName: 'TSMC', ticker: 'TSM', market: 'US',
    action: '매수', price: 195.2, quantity: 12,
    tradeDate: new Date('2025-02-05'),
    note: '미국 공장 가동 시작. TSMC 없으면 AI 반도체도 없음. 장기 적립식.',
    isPublic: true, likes: 14, createdAt: new Date('2025-02-05T20:30:00'),
  },
  {
    uid: 'seed_user_9', nickname: 'ETF만해',
    stockName: '코덱스 200', ticker: '069500', market: 'KS',
    action: '매수', price: 31500, quantity: 100,
    tradeDate: new Date('2025-02-07'),
    note: '매달 정기 매수. 특별한 이유 없음',
    isPublic: true, likes: 5, createdAt: new Date('2025-02-07T09:05:00'),
  },
  {
    uid: 'seed_user_4', nickname: 'NVDA홀더',
    stockName: 'Meta', ticker: 'META', market: 'US',
    action: '매수', price: 652.0, quantity: 5,
    tradeDate: new Date('2025-02-10'),
    note: '인스타 릴스 광고 매출이 생각보다 훨씬 잘 나오고 있음. AI 투자 비용 걱정했는데 수익으로 충분히 커버되는 구조라 오히려 좋게 보임.',
    isPublic: true, likes: 12, createdAt: new Date('2025-02-10T22:45:00'),
  },
  {
    uid: 'seed_user_5', nickname: '배당러',
    stockName: 'KB금융', ticker: '105560', market: 'KS',
    action: '매수', price: 79800, quantity: 25,
    tradeDate: new Date('2025-02-12'),
    note: '배당+자사주 합치면 수익률 7%는 됨. 예금이랑 비교해도 매력적',
    isPublic: true, likes: 8, createdAt: new Date('2025-02-12T10:20:00'),
  },
  {
    uid: 'seed_user_6', nickname: '방산투자자',
    stockName: '두산로보틱스', ticker: '454910', market: 'KQ',
    action: '매도', price: 52000, quantity: 30,
    tradeDate: new Date('2025-02-14'),
    note: '',
    isPublic: true, likes: 1, createdAt: new Date('2025-02-14T15:10:00'),
  },
  {
    uid: 'seed_user_10', nickname: '존버러',
    stockName: 'Microsoft', ticker: 'MSFT', market: 'US',
    action: '매수', price: 415.0, quantity: 8,
    tradeDate: new Date('2025-02-18'),
    note: 'Azure 성장률 다시 올라오는 중. 코파일럿 구독자도 빠르게 늘고 있고. 어닝 서프라이즈 기대.',
    isPublic: true, likes: 16, createdAt: new Date('2025-02-18T21:15:00'),
  },
  {
    uid: 'seed_user_7', nickname: 'US주식만',
    stockName: 'Tesla', ticker: 'TSLA', market: 'US',
    action: '매수', price: 312.0, quantity: 10,
    tradeDate: new Date('2025-02-20'),
    note: '논란이 많긴 한데 FSD는 진짜인 것 같음. 사이버캡 나오면 게임체인저 될 수도. 리스크 감수하고 진입.',
    isPublic: true, likes: 22, createdAt: new Date('2025-02-20T23:00:00'),
  },
  {
    uid: 'seed_user_8', nickname: '기술적분석충',
    stockName: '삼성바이오로직스', ticker: '207940', market: 'KS',
    action: '매수', price: 985000, quantity: 2,
    tradeDate: new Date('2025-02-24'),
    note: '100만원 돌파 직전 눌림. 5공장 수주 모멘텀 아직 안 끝났다고 봄',
    isPublic: true, likes: 6, createdAt: new Date('2025-02-24T09:40:00'),
  },
  {
    uid: 'seed_user_9', nickname: 'ETF만해',
    stockName: 'Amazon', ticker: 'AMZN', market: 'US',
    action: '매수', price: 225.8, quantity: 10,
    tradeDate: new Date('2025-02-26'),
    note: 'AWS + 광고 투 트랙 성장. 클라우드 중에선 제일 잘 모르겠는 회사인데 실적은 계속 좋음',
    isPublic: true, likes: 9, createdAt: new Date('2025-02-26T20:50:00'),
  },
  {
    uid: 'seed_user_1', nickname: '파랑새',
    stockName: '기아', ticker: '000270', market: 'KS',
    action: '매수', price: 88500, quantity: 20,
    tradeDate: new Date('2025-03-04'),
    note: 'PER 5배 너무하지 않냐. EV 판매 잘 되고 있고 자사주 소각도 하는데',
    isPublic: true, likes: 7, createdAt: new Date('2025-03-04T10:00:00'),
  },
  {
    uid: 'seed_user_2', nickname: '현규',
    stockName: '네이버', ticker: '035420', market: 'KS',
    action: '매도', price: 195500, quantity: 10,
    tradeDate: new Date('2025-03-06'),
    note: '+18% 나옴. 라인야후 이슈가 어느 정도 마무리되면서 오른 것 같은데 추가 상승 모멘텀은 잘 모르겠어서 일단 팜',
    isPublic: true, likes: 3, createdAt: new Date('2025-03-06T14:00:00'),
  },
  {
    uid: 'seed_user_10', nickname: '존버러',
    stockName: 'Alphabet', ticker: 'GOOGL', market: 'US',
    action: '매수', price: 188.5, quantity: 15,
    tradeDate: new Date('2025-03-10'),
    note: '빅테크 중에 제일 싼 편. 제미나이 2.0 생각보다 좋더라고. 유튜브도 여전히 잘 나오고',
    isPublic: true, likes: 13, createdAt: new Date('2025-03-10T21:30:00'),
  },
  {
    uid: 'seed_user_3', nickname: '강남아재',
    stockName: 'HD현대일렉트릭', ticker: '267260', market: 'KS',
    action: '매수', price: 285000, quantity: 7,
    tradeDate: new Date('2025-03-11'),
    note: '미국 전력망 노후화 교체 수요 진짜 엄청난 것 같음. 변압기 납기가 몇 년씩 밀린다는 게 말이 되나. 더 갈 것 같음',
    isPublic: true, likes: 17, createdAt: new Date('2025-03-11T09:55:00'),
  },
  {
    uid: 'seed_user_6', nickname: '방산투자자',
    stockName: '펄어비스', ticker: '263750', market: 'KQ',
    action: '매수', price: 38500, quantity: 25,
    tradeDate: new Date('2025-03-13'),
    note: '붉은사막 올해는 나오겠지...',
    isPublic: true, likes: 5, createdAt: new Date('2025-03-13T11:20:00'),
  },
  {
    uid: 'seed_user_5', nickname: '배당러',
    stockName: '신한지주', ticker: '055550', market: 'KS',
    action: '매수', price: 52300, quantity: 30,
    tradeDate: new Date('2025-03-14'),
    note: '배당 5%대에 자사주까지. 은행주 밸류업 아직 덜 된 것 같아서 추가 매수.',
    isPublic: true, likes: 8, createdAt: new Date('2025-03-14T10:10:00'),
  },
  {
    uid: 'seed_user_4', nickname: 'NVDA홀더',
    stockName: 'NVIDIA', ticker: 'NVDA', market: 'US',
    action: '매도', price: 128.0, quantity: 10,
    tradeDate: new Date('2025-03-15'),
    note: '딥시크 이후 반등 구간에서 일부 익절. 나머지 절반은 계속 들고감. 전체 포지션 너무 컸음',
    isPublic: true, likes: 25, createdAt: new Date('2025-03-15T22:20:00'),
  },
  {
    uid: 'seed_user_7', nickname: 'US주식만',
    stockName: 'Palantir', ticker: 'PLTR', market: 'US',
    action: '매수', price: 78.4, quantity: 30,
    tradeDate: new Date('2025-03-17'),
    note: '국방부 계약 계속 들어오고 있음. 밸류 비싼 건 알겠는데 이 회사는 그냥 비싸게 거래되는 게 맞는 것 같기도 하고. 소량만 들고감',
    isPublic: true, likes: 11, createdAt: new Date('2025-03-17T21:45:00'),
  },
  {
    uid: 'seed_user_8', nickname: '기술적분석충',
    stockName: '포스코홀딩스', ticker: '005490', market: 'KS',
    action: '매수', price: 298000, quantity: 10,
    tradeDate: new Date('2025-03-18'),
    note: 'PBR 0.4배. 본업 철강도 바닥인데 리튬까지 포기하고 파는 건 너무한 것 같아서',
    isPublic: true, likes: 4, createdAt: new Date('2025-03-18T09:30:00'),
  },
  {
    uid: 'seed_user_9', nickname: 'ETF만해',
    stockName: 'SPY', ticker: 'SPY', market: 'US',
    action: '매수', price: 558.0, quantity: 5,
    tradeDate: new Date('2025-03-18'),
    note: '',
    isPublic: true, likes: 3, createdAt: new Date('2025-03-18T20:00:00'),
  },
  {
    uid: 'seed_user_10', nickname: '존버러',
    stockName: '삼성전자', ticker: '005930', market: 'KS',
    action: '매수', price: 56800, quantity: 50,
    tradeDate: new Date('2025-03-19'),
    note: '3차 분할 진입 완료. 평단 낮아져서 마음은 편한데 언제 오르나 ㅠ 그냥 배당 받으면서 기다리는 수밖에',
    isPublic: true, likes: 19, createdAt: new Date('2025-03-19T10:05:00'),
  },
];

async function deleteOldSeeds() {
  const snap = await db.collection('trading_journal')
    .where('uid', '>=', 'seed_user_')
    .where('uid', '<=', 'seed_user_~')
    .get();
  const batch = db.batch();
  snap.docs.forEach(d => batch.delete(d.ref));
  await batch.commit();
  console.log(`🗑️  기존 시드 데이터 ${snap.size}개 삭제`);
}

async function seed() {
  await deleteOldSeeds();
  const batch = db.batch();
  for (const j of journals) {
    const ref = db.collection('trading_journal').doc();
    batch.set(ref, {
      ...j,
      tradeDate: admin.firestore.Timestamp.fromDate(j.tradeDate),
      createdAt: admin.firestore.Timestamp.fromDate(j.createdAt),
    });
  }
  await batch.commit();
  console.log(`✅ ${journals.length}개 매매일지 업로드 완료`);
  process.exit(0);
}

seed().catch(e => { console.error(e); process.exit(1); });
