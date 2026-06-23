/**
 * 오늘 (KST) 모든 유저의 AI 분석 쿼터 초기화.
 *
 * users/{uid}/ai_quota/{YYYY-MM-DD} 문서의 count를 0으로 (또는 삭제).
 * 서버 quota check가 `used >= limit` 비교라서, count=0이면 다시 한도 가득
 * 새로 쓸 수 있게 됨.
 *
 * 사용법:
 *   node reset_ai_quota_today.js --dry-run    # 대상 수만 확인
 *   node reset_ai_quota_today.js              # 실제 실행
 */

const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const sa = require(path.join(__dirname, 'serviceAccountKey.json'));
initializeApp({ credential: cert(sa) });
const db = getFirestore();

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');

// 서버 seoulDateKey()와 동일 — UTC+9 기준 오늘 날짜
function seoulDateKey() {
  const seoul = new Date(Date.now() + 9 * 3600 * 1000);
  const y = seoul.getUTCFullYear();
  const m = String(seoul.getUTCMonth() + 1).padStart(2, '0');
  const d = String(seoul.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const dateKey = seoulDateKey();
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Mode:    ${DRY_RUN ? 'DRY RUN' : 'LIVE'}`);
  console.log(`Date:    ${dateKey} (KST)`);
  console.log(`Target:  users/{uid}/ai_quota/${dateKey}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // collectionGroup으로 모든 유저의 오늘 quota 문서 한 번에 가져오기.
  // doc id가 dateKey와 같은 것만 필터.
  console.log('Scanning ai_quota collectionGroup...');
  const snap = await db.collectionGroup('ai_quota').get();
  const todayDocs = snap.docs.filter((d) => d.id === dateKey);
  console.log(`Total ai_quota docs:  ${snap.size}`);
  console.log(`Today (${dateKey}):   ${todayDocs.length}`);

  if (DRY_RUN) {
    console.log('\nDRY RUN — would set count=0 on these docs');
    if (todayDocs.length > 0) {
      console.log('Sample first 3:');
      todayDocs.slice(0, 3).forEach((d) => {
        const data = d.data();
        console.log(`  ${d.ref.path}: count=${data.count}`);
      });
    }
    return;
  }

  if (todayDocs.length === 0) {
    console.log('\nNothing to reset.');
    return;
  }

  console.log(`\nResetting ${todayDocs.length} docs to count=0...`);
  const startMs = Date.now();
  let success = 0;
  let failed = 0;
  const errors = [];

  // batched writes (500 max per batch)
  for (let i = 0; i < todayDocs.length; i += 400) {
    const chunk = todayDocs.slice(i, i + 400);
    const batch = db.batch();
    chunk.forEach((d) => {
      batch.set(
        d.ref,
        { count: 0, updatedAt: new Date(), lastAccess: 'reset_compensation' },
        { merge: true }
      );
    });
    try {
      await batch.commit();
      success += chunk.length;
    } catch (e) {
      failed += chunk.length;
      errors.push({ start: i, error: e.message });
    }
    const elapsed = ((Date.now() - startMs) / 1000).toFixed(1);
    console.log(
      `Progress: ${success + failed}/${todayDocs.length} ` +
      `(success: ${success}, failed: ${failed}, ${elapsed}s)`
    );
    await sleep(100);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Done. Success: ${success}, Failed: ${failed}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  if (errors.length) {
    console.log('First errors:', errors.slice(0, 5));
  }
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
