/**
 * 닉네임으로 특정 유저를 찾아 RevenueCat 'premium' entitlement를 프로모션으로 부여한다.
 * (전체 유저 대상은 grant_promo_premium.js 참고)
 *
 * 앱 업데이트 없이 작동:
 *   1. 닉네임으로 users 컬렉션에서 uid 조회
 *   2. RevenueCat에 promotional entitlement 부여
 *   3. 유저가 다음 앱 실행 시 Purchases.getCustomerInfo()로 프리미엄 감지
 *
 * 사용법:
 *   RC_KEY=sk_xxx node grant_premium_by_nickname.js --nick 아리스
 *   RC_KEY=sk_xxx node grant_premium_by_nickname.js --nick 111 --duration monthly
 *   node grant_premium_by_nickname.js --nick 아리스 --key sk_xxx --dry-run
 *
 * 옵션:
 *   --nick <닉네임>       (필수) 대상 유저 닉네임
 *   --duration <기간>     (선택, 기본 three_day) RevenueCat promotional duration
 *                         daily | three_day | weekly | monthly | two_month |
 *                         three_month | six_month | yearly | lifetime
 *   --key <sk_...>        RevenueCat secret key (또는 환경변수 RC_KEY)
 *   --dry-run             대상 uid만 확인하고 부여는 하지 않음
 *
 * 필요한 파일:
 *   functions/serviceAccountKey.json (Firebase Admin SDK 키)
 *
 * 주의: 동일 닉네임 유저가 여러 명이면 전원에게 부여한다.
 */

const path = require('path');
const https = require('https');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const serviceAccount = require(path.join(__dirname, 'serviceAccountKey.json'));
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const ENTITLEMENT = 'premium';
const VALID_DURATIONS = [
  'daily', 'three_day', 'weekly', 'monthly', 'two_month',
  'three_month', 'six_month', 'yearly', 'lifetime',
];

const args = process.argv.slice(2);
const getArg = (flag, def = '') => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};
const NICK = getArg('--nick');
const DURATION = getArg('--duration', 'three_day');
const DRY_RUN = args.includes('--dry-run');
const RC_KEY = (getArg('--key') || process.env.RC_KEY || '').trim();

function rcRequest(method, p, apiKey, body) {
  return new Promise((resolve, reject) => {
    const headers = {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    };
    if (body) headers['Content-Length'] = Buffer.byteLength(body);
    const req = https.request(
      { hostname: 'api.revenuecat.com', path: p, method, headers, timeout: 15000 },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => resolve({ status: res.statusCode, body: data }));
      }
    );
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    if (body) req.write(body);
    req.end();
  });
}

async function ensureSubscriberAndGrant(uid, apiKey) {
  // GET으로 subscriber가 없으면 자동 생성. 응답 무시.
  await rcRequest('GET', `/v1/subscribers/${encodeURIComponent(uid)}`, apiKey);
  return rcRequest(
    'POST',
    `/v1/subscribers/${encodeURIComponent(uid)}/entitlements/${ENTITLEMENT}/promotional`,
    apiKey,
    JSON.stringify({ duration: DURATION })
  );
}

async function main() {
  if (!NICK) {
    console.error('ERROR: --nick <닉네임> 필요');
    process.exit(1);
  }
  if (!VALID_DURATIONS.includes(DURATION)) {
    console.error(`ERROR: 잘못된 --duration "${DURATION}". 가능: ${VALID_DURATIONS.join(', ')}`);
    process.exit(1);
  }
  if (!DRY_RUN && (!RC_KEY || !RC_KEY.startsWith('sk_'))) {
    console.error('ERROR: RevenueCat secret key(sk_...) 필요. RC_KEY=sk_xxx 또는 --key sk_xxx');
    process.exit(1);
  }

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Mode:        ${DRY_RUN ? 'DRY RUN (no API calls)' : 'LIVE'}`);
  console.log(`Nickname:    ${NICK}`);
  console.log(`Entitlement: ${ENTITLEMENT}`);
  console.log(`Duration:    ${DURATION}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const snap = await db.collection('users').where('nickname', '==', NICK).get();
  if (snap.empty) {
    console.error(`\nNo user with nickname "${NICK}"`);
    process.exit(1);
  }
  console.log(`\nMatched ${snap.size} user(s):`);
  snap.docs.forEach((d) => console.log('  ', d.id, JSON.stringify({ email: d.data().email || null })));

  if (DRY_RUN) {
    console.log('\nDry run complete. Re-run without --dry-run to actually grant.');
    return;
  }

  let success = 0;
  let failed = 0;
  for (const doc of snap.docs) {
    const uid = doc.id;
    try {
      const res = await ensureSubscriberAndGrant(uid, RC_KEY);
      const ok = res.status >= 200 && res.status < 300;
      console.log(`\n[${uid}] status=${res.status} ${ok ? '✅' : '❌'}`);
      console.log('  ', res.body.slice(0, 300));
      if (ok) {
        // 아바타 왕관 즉시 반영용 공개 프로필 미러링
        await db.collection('user_public').doc(uid).set({ isPremium: true }, { merge: true });
      }
      ok ? success++ : failed++;
    } catch (e) {
      failed++;
      console.log(`\n[${uid}] ERROR: ${e.message}`);
    }
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Done. Success: ${success}, Failed: ${failed}`);
  console.log('유저가 앱 재실행 시 프리미엄 적용됨.');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  if (failed) process.exit(1);
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
