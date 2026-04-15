/**
 * backfill_journal_published_at.js
 *
 * 기존 공개 매매일지(trading_journal, isPublic=true) 중 publishedAt이 없는 문서에
 * publishedAt을 채우는 일회성 백필 스크립트.
 *
 * 규칙:
 * - createdAt이 있으면 publishedAt = createdAt
 * - createdAt이 없으면 publishedAt = now
 *
 * 실행:
 *   node functions/backfill_journal_published_at.js --dry-run
 *   node functions/backfill_journal_published_at.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const DRY_RUN = process.argv.includes('--dry-run');
const BATCH_SIZE = 450;

async function main() {
  console.log(DRY_RUN ? '=== DRY RUN (no write) ===' : '=== BACKFILL START ===');
  const snap = await db
    .collection('trading_journal')
    .where('isPublic', '==', true)
    .select('createdAt', 'publishedAt')
    .get();

  console.log(`- 공개 매매일지 스캔: ${snap.size}개`);

  let batch = db.batch();
  let opCount = 0;
  let updateCount = 0;
  let usedCreatedAtCount = 0;
  let usedNowCount = 0;

  const flush = async () => {
    if (opCount === 0 || DRY_RUN) return;
    await batch.commit();
    batch = db.batch();
    opCount = 0;
  };

  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (data.publishedAt != null) continue;

    const createdAt = data.createdAt;
    const publishedAt = createdAt ?? admin.firestore.Timestamp.fromDate(new Date());
    if (createdAt != null) {
      usedCreatedAtCount++;
    } else {
      usedNowCount++;
    }

    batch.update(doc.ref, { publishedAt });
    opCount++;
    updateCount++;

    if (opCount >= BATCH_SIZE) {
      await flush();
    }
  }

  await flush();

  console.log('\n=== DONE ===');
  console.log(`- publishedAt 추가 대상: ${updateCount}개`);
  console.log(`- createdAt 사용: ${usedCreatedAtCount}개`);
  console.log(`- now 사용(createdAt 없음): ${usedNowCount}개`);
  if (DRY_RUN) {
    console.log('- DRY RUN이므로 실제 쓰기는 수행하지 않았습니다.');
  }
}

main().catch((err) => {
  console.error('실패:', err);
  process.exit(1);
});

