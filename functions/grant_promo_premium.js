/**
 * 광고 시청 후 분석 미작동 보상 — 활성 유저에게 RevenueCat 프리미엄 권한을
 * 3일간 프로모션으로 부여한다.
 *
 * 앱 업데이트 없이 작동:
 *   1. RevenueCat에 promo entitlement 부여
 *   2. 앱이 다음 실행 시 Purchases.getCustomerInfo()로 프리미엄 감지
 *   3. AdService.setPremium(true) → 광고 스킵, AI 분석 일3회 무료
 *   4. 3일 후 자동 만료
 *
 * 사용법:
 *   node grant_promo_premium.js --dry-run                          # 대상 수만 확인
 *   RC_KEY=sk_xxx node grant_promo_premium.js                      # 실제 실행 (env var)
 *   node grant_promo_premium.js --key sk_xxx                       # 실제 실행 (인자)
 *   node grant_promo_premium.js --limit 5 --key sk_xxx             # 처음 5명만 (테스트)
 *
 * 필요한 파일:
 *   functions/serviceAccountKey.json (Firebase Admin SDK 키)
 *
 * RevenueCat 시크릿 키:
 *   환경변수 RC_KEY 또는 CLI 인자 --key 로 전달.
 *   (Secret Manager는 로컬 서비스계정에 권한이 없을 수 있어 직접 입력 방식)
 */

const path = require('path');
const https = require('https');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const keyPath = path.join(__dirname, 'serviceAccountKey.json');
const serviceAccount = require(keyPath);

initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const ENTITLEMENT = 'premium';
const DURATION = 'three_day';

// CLI 옵션 파싱
const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const limitIdx = args.indexOf('--limit');
const LIMIT = limitIdx >= 0 && args[limitIdx + 1] ? Number(args[limitIdx + 1]) : 0;
const keyIdx = args.indexOf('--key');
const CLI_KEY = keyIdx >= 0 && args[keyIdx + 1] ? args[keyIdx + 1] : '';
const RC_KEY = (CLI_KEY || process.env.RC_KEY || '').trim();

// RevenueCat API — subscriber 자동 생성 (GET) + promo entitlement 부여 (POST)
function rcRequest(method, path, apiKey, body) {
  return new Promise((resolve, reject) => {
    const headers = {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    };
    if (body) headers['Content-Length'] = Buffer.byteLength(body);
    const req = https.request(
      {
        hostname: 'api.revenuecat.com',
        path,
        method,
        headers,
        timeout: 15000,
      },
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
  // 그 다음 promotional grant.
  const body = JSON.stringify({ duration: DURATION });
  return rcRequest(
    'POST',
    `/v1/subscribers/${encodeURIComponent(uid)}/entitlements/${ENTITLEMENT}/promotional`,
    apiKey,
    body
  );
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Mode:        ${DRY_RUN ? 'DRY RUN (no API calls)' : 'LIVE'}`);
  console.log(`Entitlement: ${ENTITLEMENT}`);
  console.log(`Duration:    ${DURATION}`);
  if (LIMIT) console.log(`Limit:       처음 ${LIMIT}명만`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  let apiKey = '';
  if (!DRY_RUN) {
    apiKey = RC_KEY;
    if (!apiKey) {
      console.error('ERROR: RevenueCat secret key 미제공.');
      console.error('  사용법: RC_KEY=sk_xxx node grant_promo_premium.js');
      console.error('     또는: node grant_promo_premium.js --key sk_xxx');
      process.exit(1);
    }
    if (!apiKey.startsWith('sk_')) {
      console.error('ERROR: RevenueCat secret key는 sk_ 로 시작해야 합니다.');
      process.exit(1);
    }
    console.log(`Key loaded (${apiKey.slice(0, 6)}...${apiKey.slice(-4)})`);
  }

  console.log('\nFetching users from Firestore...');
  const snap = await db.collection('users').get();
  let uids = snap.docs.map((d) => d.id);
  console.log(`Total users: ${uids.length}`);

  if (LIMIT) uids = uids.slice(0, LIMIT);

  if (DRY_RUN) {
    console.log(`\nDRY RUN — would grant ${ENTITLEMENT} (${DURATION}) to ${uids.length} uids`);
    console.log(`Sample first 5: ${uids.slice(0, 5).join(', ')}`);
    console.log(`Sample last 5:  ${uids.slice(-5).join(', ')}`);
    console.log('\nDry run complete. Re-run without --dry-run to actually grant.');
    return;
  }

  console.log(`\nGranting ${ENTITLEMENT} (${DURATION}) to ${uids.length} users...`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  let success = 0;
  let failed = 0;
  const errors = [];
  const startMs = Date.now();

  for (let i = 0; i < uids.length; i++) {
    const uid = uids[i];
    try {
      const result = await ensureSubscriberAndGrant(uid, apiKey);
      if (result.status >= 200 && result.status < 300) {
        // 아바타 왕관 즉시 반영용 공개 프로필 미러링
        await db.collection('user_public').doc(uid).set({ isPremium: true }, { merge: true });
        success++;
      } else {
        failed++;
        errors.push({ uid, status: result.status, body: result.body.slice(0, 200) });
      }
    } catch (e) {
      failed++;
      errors.push({ uid, error: e.message });
    }

    if ((i + 1) % 50 === 0 || i + 1 === uids.length) {
      const elapsed = ((Date.now() - startMs) / 1000).toFixed(1);
      const rate = ((i + 1) / Number(elapsed)).toFixed(1);
      console.log(
        `Progress: ${i + 1}/${uids.length} ` +
        `(success: ${success}, failed: ${failed}, ` +
        `${rate}/s, ${elapsed}s elapsed)`
      );
    }

    // GET + POST 두 번이라 throttle 더 보수적으로. 250ms = 4/s = 240/min.
    await sleep(250);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Done. Success: ${success}, Failed: ${failed}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  if (errors.length) {
    console.log(`\nFirst ${Math.min(20, errors.length)} errors:`);
    errors.slice(0, 20).forEach((e) => console.log('  ', JSON.stringify(e)));
  }
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
