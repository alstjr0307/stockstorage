/**
 * migrate_nicknames.js
 *
 * 기존 users/{uid}.nickname → nicknames/{nickname} 컬렉션으로 마이그레이션
 * - 닉네임 없는 유저: 스킵
 * - 닉네임 중복 시: Firebase Auth 계정 생성 시간 기준 선착순 유지
 *   → 늦은 유저는 닉네임 뒤에 숫자 자동 부여 (예: 익명2, 익명3)
 *   → users/{uid}.nickname 도 함께 업데이트
 *
 * 실행: node functions/migrate_nicknames.js
 * --dry-run 플래그로 실제 쓰기 없이 미리 확인 가능
 */

const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const auth = admin.auth();

const DRY_RUN = process.argv.includes('--dry-run');

async function main() {
  console.log(DRY_RUN ? '=== DRY RUN 모드 (실제 쓰기 없음) ===' : '=== 실제 마이그레이션 시작 ===');

  // 1. users 컬렉션 전체 읽기
  console.log('\n[1/4] users 컬렉션 읽는 중...');
  const usersSnap = await db.collection('users').get();
  const INVALID_DOC_IDS = new Set(['.', '..']);
  const usersWithNickname = usersSnap.docs
    .filter(doc => {
      const nick = doc.data().nickname;
      if (!nick) return false;
      if (INVALID_DOC_IDS.has(nick) || nick.includes('/')) {
        console.log(`  스킵 (유효하지 않은 닉네임): uid=${doc.id} | "${nick}"`);
        return false;
      }
      return true;
    })
    .map(doc => ({ uid: doc.id, nickname: doc.data().nickname }));

  console.log(`  전체 유저: ${usersSnap.size}명, 닉네임 있는 유저: ${usersWithNickname.length}명`);

  // 2. Firebase Auth에서 계정 생성 시간 조회 (선착순 기준)
  console.log('\n[2/4] Auth 계정 생성 시간 조회 중...');
  const createdAtMap = {};
  let nextPageToken;
  do {
    const listResult = await auth.listUsers(1000, nextPageToken);
    for (const user of listResult.users) {
      createdAtMap[user.uid] = new Date(user.metadata.creationTime).getTime();
    }
    nextPageToken = listResult.pageToken;
  } while (nextPageToken);

  console.log(`  Auth 유저 수: ${Object.keys(createdAtMap).length}명`);

  // 3. 닉네임 기준으로 그룹핑 후 중복 처리
  console.log('\n[3/4] 중복 닉네임 분석 중...');
  const nicknameGroups = {};
  for (const user of usersWithNickname) {
    const nick = user.nickname;
    if (!nicknameGroups[nick]) nicknameGroups[nick] = [];
    nicknameGroups[nick].push(user);
  }

  const duplicates = Object.entries(nicknameGroups).filter(([, users]) => users.length > 1);
  if (duplicates.length === 0) {
    console.log('  중복 닉네임 없음!');
  } else {
    console.log(`  중복 닉네임 ${duplicates.length}개 발견:`);
    for (const [nick, users] of duplicates) {
      console.log(`  - "${nick}": ${users.length}명`);
    }
  }

  // 선착순 정렬: createdAt 오름차순 (없으면 uid 알파벳순)
  for (const users of Object.values(nicknameGroups)) {
    users.sort((a, b) => {
      const ca = createdAtMap[a.uid] ?? Infinity;
      const cb = createdAtMap[b.uid] ?? Infinity;
      if (ca !== cb) return ca - cb;
      return a.uid.localeCompare(b.uid);
    });
  }

  // 최종 닉네임 결정 (중복 시 뒤에 숫자 부여)
  // 이미 사용 확정된 닉네임 셋 (숫자 붙인 것 포함 충돌 방지)
  const finalNicknameMap = {}; // uid → 최종닉네임
  const assignedNicknames = new Set();

  for (const [, users] of Object.entries(nicknameGroups)) {
    for (let i = 0; i < users.length; i++) {
      const { uid, nickname } = users[i];
      if (i === 0) {
        // 선착순 1등: 원래 닉네임 유지
        finalNicknameMap[uid] = nickname;
        assignedNicknames.add(nickname);
      } else {
        // 후순위: 숫자 붙이기 (충돌 없을 때까지)
        let suffix = 2;
        let candidate = `${nickname}${suffix}`;
        while (assignedNicknames.has(candidate)) {
          suffix++;
          candidate = `${nickname}${suffix}`;
        }
        finalNicknameMap[uid] = candidate;
        assignedNicknames.add(candidate);
        console.log(`  → 닉네임 변경: uid=${uid} | "${nickname}" → "${candidate}"`);
      }
    }
  }

  // 4. Firestore 쓰기
  console.log('\n[4/4] Firestore 업데이트 중...');
  const BATCH_SIZE = 400; // Firestore 배치 최대 500 (nicknames + users 각 1개씩이라 400 안전)
  let batch = db.batch();
  let opCount = 0;
  let totalNicknamesWritten = 0;
  let totalUsersUpdated = 0;

  const flush = async () => {
    if (opCount > 0 && !DRY_RUN) {
      await batch.commit();
      batch = db.batch();
      opCount = 0;
    }
  };

  for (const { uid, nickname: originalNickname } of usersWithNickname) {
    const finalNickname = finalNicknameMap[uid];

    // nicknames/{finalNickname} 생성
    const nicknameRef = db.collection('nicknames').doc(finalNickname);
    if (!DRY_RUN) batch.set(nicknameRef, { uid });
    opCount++;
    totalNicknamesWritten++;

    // 닉네임이 변경된 경우 users/{uid} 업데이트
    if (finalNickname !== originalNickname) {
      const userRef = db.collection('users').doc(uid);
      if (!DRY_RUN) batch.update(userRef, { nickname: finalNickname });
      opCount++;
      totalUsersUpdated++;
    }

    if (opCount >= BATCH_SIZE) await flush();
  }
  await flush();

  console.log(`\n=== 완료 ===`);
  console.log(`  nicknames 컬렉션 문서 생성: ${totalNicknamesWritten}개`);
  console.log(`  중복으로 닉네임 변경된 유저: ${totalUsersUpdated}명`);
  if (DRY_RUN) console.log('\n  (DRY RUN — 실제 적용하려면 --dry-run 없이 실행)');
}

main().catch(err => {
  console.error('오류 발생:', err);
  process.exit(1);
});
