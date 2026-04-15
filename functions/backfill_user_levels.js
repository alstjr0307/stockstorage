/**
 * backfill_user_levels.js
 *
 * 기존 유저 레벨 데이터 백필 스크립트
 * - posts + (isPublic=true 인 trading_journal) 작성 수를 합산해 postCount 계산
 * - users/{uid}.attendanceCount는 기존 값 유지 (없으면 0)
 * - 앱과 동일한 공식으로 level 계산 후 users/{uid}에 반영
 *
 * 실행:
 *   node functions/backfill_user_levels.js --dry-run
 *   node functions/backfill_user_levels.js
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const DRY_RUN = process.argv.includes('--dry-run');

const POST_SCORE = 3;
const COMMENT_SCORE = 1;
const ATTENDANCE_SCORE = 1;
const BATCH_SIZE = 400;
const LEVEL_THRESHOLDS = [
  0, // Lv.1
  10, // Lv.2
  25, // Lv.3
  45, // Lv.4
  70, // Lv.5
  100, // Lv.6
  135, // Lv.7
  175, // Lv.8
  220, // Lv.9
  270, // Lv.10
  325, // Lv.11
  385, // Lv.12
  450, // Lv.13
  520, // Lv.14
  595, // Lv.15
  675, // Lv.16
  760, // Lv.17
  850, // Lv.18
  945, // Lv.19
  1045, // Lv.20
];
const AFTER_TABLE_STEP = 110;

function calculateLevel(postCount, commentCount, attendanceCount) {
  const score =
    (postCount * POST_SCORE) +
    (commentCount * COMMENT_SCORE) +
    (attendanceCount * ATTENDANCE_SCORE);
  let level = 1;
  for (let i = 1; i < LEVEL_THRESHOLDS.length; i++) {
    if (score >= LEVEL_THRESHOLDS[i]) {
      level = i + 1;
    } else {
      return level;
    }
  }
  const extraXp = score - LEVEL_THRESHOLDS[LEVEL_THRESHOLDS.length - 1];
  return level + Math.floor(extraXp / AFTER_TABLE_STEP);
}

async function accumulateCommentCountByUid(map) {
  const allowedRoots = new Set(['stock_picks', 'posts', 'trading_journal']);
  const snap = await db.collectionGroup('comments').select('uid').get();
  let counted = 0;
  for (const doc of snap.docs) {
    const rootCollection = doc.ref.parent.parent?.parent?.id;
    if (!rootCollection || !allowedRoots.has(rootCollection)) continue;
    const uid = doc.get('uid');
    if (!uid || typeof uid !== 'string') continue;
    map.set(uid, (map.get(uid) || 0) + 1);
    counted++;
  }
  return { scanned: snap.size, counted };
}

async function accumulateCountByUid(collectionName, map, options = {}) {
  const { publicOnly = false } = options;
  const snap = await db
    .collection(collectionName)
    .select('uid', ...(publicOnly ? ['isPublic'] : []))
    .get();
  let counted = 0;
  for (const doc of snap.docs) {
    if (publicOnly && doc.get('isPublic') !== true) continue;
    const uid = doc.get('uid');
    if (!uid || typeof uid !== 'string') continue;
    map.set(uid, (map.get(uid) || 0) + 1);
    counted++;
  }
  return { scanned: snap.size, counted };
}

async function main() {
  console.log(DRY_RUN ? '=== DRY RUN (no write) ===' : '=== BACKFILL START ===');

  console.log('\n[1/4] users 로드 중...');
  const usersSnap = await db.collection('users').get();
  const userDataMap = new Map();
  for (const doc of usersSnap.docs) {
    userDataMap.set(doc.id, doc.data() || {});
  }
  console.log(`- users 문서: ${usersSnap.size}개`);

  const publicSnap = await db.collection('user_public').get();
  const publicDataMap = new Map();
  for (const doc of publicSnap.docs) {
    publicDataMap.set(doc.id, doc.data() || {});
  }
  console.log(`- user_public 문서: ${publicSnap.size}개`);

  console.log('\n[2/4] posts/trading_journal 작성 수 집계 중...');
  const postCountMap = new Map();
  const commentCountMap = new Map();
  const postStats = await accumulateCountByUid('posts', postCountMap);
  const journalStats = await accumulateCountByUid('trading_journal', postCountMap, {
    publicOnly: true,
  });
  const commentStats = await accumulateCommentCountByUid(commentCountMap);
  console.log(`- posts 문서 스캔: ${postStats.scanned}개 / 카운트 반영: ${postStats.counted}개`);
  console.log(
    `- trading_journal 문서 스캔: ${journalStats.scanned}개 / 카운트 반영(공유만): ${journalStats.counted}개`
  );
  console.log(
    `- comments 문서 스캔: ${commentStats.scanned}개 / 카운트 반영(추천주/자게/매매일지): ${commentStats.counted}개`
  );
  console.log(`- 작성자 uid 수: ${postCountMap.size}명`);
  console.log(`- 댓글 작성자 uid 수: ${commentCountMap.size}명`);

  console.log('\n[3/4] 업데이트 대상 계산 중...');
  const targetUids = new Set([
    ...userDataMap.keys(),
    ...postCountMap.keys(),
    ...commentCountMap.keys(),
  ]);
  console.log(`- 최종 대상 uid 수: ${targetUids.size}명`);

  console.log('\n[4/4] users 레벨 필드 반영 중...');
  let batch = db.batch();
  let opCount = 0;
  let writeCount = 0;
  let createdUserDocCount = 0;

  const flush = async () => {
    if (opCount === 0 || DRY_RUN) return;
    await batch.commit();
    batch = db.batch();
    opCount = 0;
  };

  for (const uid of targetUids) {
    const current = userDataMap.get(uid) || {};
    const postCount = postCountMap.get(uid) || 0;
    const commentCount = commentCountMap.get(uid) || 0;
    const attendanceCount =
      typeof current.attendanceCount === 'number' ? current.attendanceCount : 0;
    const level = calculateLevel(postCount, commentCount, attendanceCount);
    const existingLevel = typeof current.level === 'number' ? current.level : null;
    const existingPostCount = typeof current.postCount === 'number' ? current.postCount : null;
    const existingCommentCount =
      typeof current.commentCount === 'number' ? current.commentCount : null;
    const hasUserDoc = userDataMap.has(uid);

    // 불필요한 쓰기 최소화
    const currentPublic = publicDataMap.get(uid) || {};
    const existingPublicLevel =
      typeof currentPublic.level === 'number' ? currentPublic.level : null;
    const nickname =
      typeof current.nickname === 'string' && current.nickname.trim().length > 0
        ? current.nickname.trim()
        : null;
    const existingPublicNickname =
      typeof currentPublic.nickname === 'string' ? currentPublic.nickname : null;
    const publicUpToDate =
      existingPublicLevel === level &&
      (nickname == null || existingPublicNickname === nickname);

    if (
      hasUserDoc &&
      existingLevel === level &&
      existingPostCount === postCount &&
      existingCommentCount === commentCount &&
      typeof current.attendanceCount === 'number' &&
      publicUpToDate
    ) {
      continue;
    }

    if (!hasUserDoc) createdUserDocCount++;

    const ref = db.collection('users').doc(uid);
    const publicRef = db.collection('user_public').doc(uid);
    batch.set(
      ref,
      {
        postCount,
        commentCount,
        attendanceCount,
        level,
        levelBackfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    const publicPayload = { level };
    if (nickname != null) publicPayload.nickname = nickname;
    batch.set(publicRef, publicPayload, { merge: true });
    opCount++;
    opCount++;
    writeCount += 2;

    if (opCount >= BATCH_SIZE) {
      await flush();
    }
  }

  await flush();

  console.log('\n=== DONE ===');
  console.log(`- 업데이트 문서 수: ${writeCount}개`);
  console.log(`- 신규 users 문서 생성 수(merge set): ${createdUserDocCount}개`);
  if (DRY_RUN) {
    console.log('- DRY RUN이므로 실제 쓰기는 수행하지 않았습니다.');
  }
}

main().catch((err) => {
  console.error('실패:', err);
  process.exit(1);
});
