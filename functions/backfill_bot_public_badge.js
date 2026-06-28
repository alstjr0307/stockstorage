/**
 * 특정 봇 닉네임으로 작성된 자유게시판 댓글들의 가짜 uid에 대해
 * user_public/{uid} 공개 배지 문서(level)를 만들어 둔다.
 *
 * 봇 댓글은 댓글마다 고유한 가짜 uid를 쓰는데, user_public 문서가 없으면
 * authorLevel override를 모르는 구버전 앱이 아바타를 레벨 1로 표시한다.
 * 이 스크립트가 그 문서를 소급 생성해 구버전에서도 올바른 레벨을 보이게 한다.
 *
 * 사용법:
 *   node backfill_bot_public_badge.js --nick 커뮤폐인 --level 6 --dry-run
 *   node backfill_bot_public_badge.js --nick 커뮤폐인 --level 6
 *
 * 옵션:
 *   --nick  <닉네임>  (필수) 대상 봇 닉네임
 *   --level <정수>    (필수) 부여할 레벨 (bot_profiles.dart의 해당 닉네임 레벨)
 *   --dry-run         대상 uid만 출력하고 쓰지 않음
 *
 * 필요한 파일: functions/serviceAccountKey.json
 * 범위: posts/{postId}/comments 만 (봇 댓글 기능이 쓰는 곳)
 */

const path = require('path');
const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

const serviceAccount = require(path.join(__dirname, 'serviceAccountKey.json'));
initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore();

const args = process.argv.slice(2);
const getArg = (flag, def = '') => {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};
const NICK = getArg('--nick');
const LEVEL = parseInt(getArg('--level', ''), 10);
const DRY_RUN = args.includes('--dry-run');

async function main() {
  if (!NICK) {
    console.error('ERROR: --nick <닉네임> 필요');
    process.exit(1);
  }
  if (!Number.isInteger(LEVEL) || LEVEL < 1) {
    console.error('ERROR: --level <정수> 필요');
    process.exit(1);
  }

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Mode:     ${DRY_RUN ? 'DRY RUN (no writes)' : 'LIVE'}`);
  console.log(`Nickname: ${NICK}`);
  console.log(`Level:    ${LEVEL}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  const postsSnap = await db.collection('posts').get();
  console.log(`\nScanning ${postsSnap.size} posts...`);

  const uids = new Set();
  let commentMatches = 0;
  for (const post of postsSnap.docs) {
    const cSnap = await post.ref
      .collection('comments')
      .where('nickname', '==', NICK)
      .get();
    for (const c of cSnap.docs) {
      const uid = c.data().uid;
      if (uid) {
        uids.add(uid);
        commentMatches++;
      }
    }
  }

  console.log(`\nMatched ${commentMatches} comment(s) → ${uids.size} unique uid(s).`);
  if (uids.size === 0) {
    console.log('Nothing to backfill.');
    return;
  }

  if (DRY_RUN) {
    [...uids].forEach((u) => console.log('  ', u));
    console.log('\nDry run complete. Re-run without --dry-run to write.');
    return;
  }

  // user_public 문서가 이미 있으면(실유저 등) level 덮어쓰기 방지: 없을 때만 생성
  let created = 0;
  let skipped = 0;
  const batchUids = [...uids];
  for (const uid of batchUids) {
    const ref = db.collection('user_public').doc(uid);
    const existing = await ref.get();
    if (existing.exists && existing.data() && existing.data().level != null) {
      skipped++;
      continue;
    }
    await ref.set(
      { level: LEVEL, isPremium: false, isBot: true },
      { merge: true }
    );
    created++;
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`Done. Created/updated: ${created}, Skipped(existing): ${skipped}`);
  console.log('구버전 앱도 봇 아바타 레벨이 올바르게 표시됨.');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
