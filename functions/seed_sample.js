const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const journals = [
  {
    uid: 'seed_user_1', nickname: '파랑새',
    stockName: '삼성전자', ticker: '005930', market: 'KS',
    action: '매수', price: 56800, quantity: 50,
    tradeDate: admin.firestore.Timestamp.fromDate(new Date('2025-03-19')),
    note: '3차 분할 진입 완료. 평단 낮아져서 마음은 편한데 언제 오르나 ㅠ 그냥 배당 받으면서 기다리는 수밖에',
    isPublic: true, likes: 4,
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2025-03-19T10:05:00')),
    buyPrice: 0, linkedBuyId: '',
  },
  {
    uid: 'seed_user_2', nickname: 'NVDA홀더',
    stockName: 'NVIDIA', ticker: 'NVDA', market: 'US',
    action: '매수', price: 138.5, quantity: 20,
    tradeDate: admin.firestore.Timestamp.fromDate(new Date('2025-03-17')),
    note: 'Blackwell 출하 본격화되는 시점. 조정마다 모으는 중. 목표가는 따로 없고 그냥 계속 들고갈 생각.',
    isPublic: true, likes: 11,
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2025-03-17T22:10:00')),
    buyPrice: 0, linkedBuyId: '',
  },
  {
    uid: 'seed_user_3', nickname: '방산투자자',
    stockName: '한화에어로스페이스', ticker: '012450', market: 'KS',
    action: '매수', price: 312000, quantity: 8,
    tradeDate: admin.firestore.Timestamp.fromDate(new Date('2025-03-15')),
    note: '폴란드 2차 계약 소식 나오면 더 오를 것 같음. 유럽 방산 예산 계속 늘어나는 추세라 장기로 가져갈 생각.',
    isPublic: true, likes: 7,
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2025-03-15T10:30:00')),
    buyPrice: 0, linkedBuyId: '',
  },
];

const posts = [
  {
    uid: 'seed_user_1', nickname: '파랑새',
    title: '삼성전자 지금 들어가도 될까요?',
    content: '56,000원대에서 분할 매수 중인데 더 내려갈 것 같기도 하고... 다들 어떻게 보세요? HBM 수주 소식은 언제 나올지 모르겠고 반도체 업황 자체가 너무 눈치게임인 것 같아서요. 그냥 배당 받으면서 장기 보유 전략으로 가야 할지 고민 중입니다.',
    likes: 3,
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2025-03-19T11:00:00')),
  },
  {
    uid: 'seed_user_2', nickname: 'NVDA홀더',
    title: '미국주식 양도세 계산 어떻게 하세요?',
    content: '해외주식 250만원 공제 넘어가면 신고해야 하는데 매번 헷갈려서요. 키움이나 미래에셋에서 자동으로 계산해주는 기능 있나요? 아니면 직접 엑셀로 정리하시는 분들 있으신가요? 환율 기준일도 매도일 기준이라 환차손 계산이 번거롭더라고요.',
    likes: 8,
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2025-03-18T15:30:00')),
  },
  {
    uid: 'seed_user_3', nickname: '방산투자자',
    title: '방산주 지금이 버블일까요?',
    content: '한화에어로 들고 있는데 올해 너무 많이 올랐나 싶기도 하고. 유럽 재무장 테마가 계속 이어질 거라고 보는 분들 많으신가요? 아니면 이미 주가에 다 반영된 건지... 목표주가 상향 리포트는 계속 나오는데 실제로 이 가격에 사는 게 맞는지 모르겠어요.',
    likes: 5,
    createdAt: admin.firestore.Timestamp.fromDate(new Date('2025-03-17T09:20:00')),
  },
];

async function seed() {
  const batch = db.batch();

  for (const j of journals) {
    const ref = db.collection('trading_journal').doc();
    batch.set(ref, j);
  }
  for (const p of posts) {
    const ref = db.collection('posts').doc();
    batch.set(ref, p);
  }

  await batch.commit();
  console.log(`✅ 매매일지 ${journals.length}개, 게시글 ${posts.length}개 업로드 완료`);
  process.exit(0);
}

seed().catch(e => { console.error(e); process.exit(1); });
