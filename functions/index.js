const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { auth } = require('firebase-functions/v1');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');
const { getFirestore, FieldPath } = require('firebase-admin/firestore');
const https = require('https');
const axios = require('axios');
const cheerio = require('cheerio');
const WebSocket = require('ws');

const ANTHROPIC_API_KEY = defineSecret('ANTHROPIC_API_KEY');
const {
  crawlDailyInvestorFlow,
  collectDailyInvestorFlow,
  saveDailyInvestorFlow,
} = require('./investor_flow');

initializeApp();

const PUSH_TEXT = Object.freeze({
  newUserTitle: '\uD83D\uDC64 \uC2E0\uADDC \uAC00\uC785\uC790',
  stockFallback: '\uC885\uBAA9',
  newCommentSuffix: '\uC0C8 \uB313\uAE00',
  someone: '\uB204\uAD70\uAC00',
  myPostCommentTitle:
    '\uD83D\uDCAC \uB0B4 \uAE00\uC5D0 \uB313\uAE00\uC774 \uB2EC\uB838\uC5B4\uC694',
  authorFallback: '\uC791\uC131\uC790',
  newFreePost: '\uC0C8 \uC790\uC720\uAC8C\uC2DC\uAE00',
  newPostSuffix: '\uB2D8\uC758 \uC0C8 \uAE00',
  journalCommentTitle:
    '\uD83D\uDCDD \uB9E4\uB9E4\uC77C\uC9C0\uC5D0 \uB313\uAE00\uC774 \uB2EC\uB838\uC5B4\uC694',
});

async function getTokensByUids(db, uidSet) {
  const uids = Array.from(uidSet).filter(
    (uid) => typeof uid === 'string' && uid.length > 0
  );
  if (uids.length === 0) return [];

  const tokens = new Set();
  for (let i = 0; i < uids.length; i += 30) {
    const chunk = uids.slice(i, i + 30);
    const snap = await db
      .collection('fcm_tokens')
      .where('uid', 'in', chunk)
      .get();
    snap.docs.forEach((d) => {
      const token = d.data().token;
      if (typeof token === 'string' && token.length > 0) tokens.add(token);
    });
  }
  return Array.from(tokens);
}

async function writeNotificationHistoryForUids(db, uidSet, payload) {
  const uids = Array.from(uidSet).filter(
    (uid) => typeof uid === 'string' && uid.length > 0
  );
  if (uids.length === 0) return;

  const sentAt = new Date();
  for (let i = 0; i < uids.length; i += 400) {
    const chunk = uids.slice(i, i + 400);
    const batch = db.batch();
    for (const uid of chunk) {
      const historyRef = db
        .collection('users')
        .doc(uid)
        .collection('notification_history');
      const recentSnap = await historyRef
        .orderBy('sentAt', 'desc')
        .limit(12)
        .get();
      const dedupeSince = sentAt.getTime() - 5 * 60 * 1000;
      const hasDuplicate = recentSnap.docs.some((doc) => {
        const data = doc.data() || {};
        const existingSentAt = data.sentAt?.toDate?.() || data.sentAt;
        if (
          existingSentAt instanceof Date &&
          existingSentAt.getTime() < dedupeSince
        ) {
          return false;
        }
        return (
          String(data.title || '').trim() === String(payload.title || '').trim() &&
          String(data.body || '').trim() === String(payload.body || '').trim()
        );
      });
      if (hasDuplicate) continue;

      const ref = db
        .collection('users')
        .doc(uid)
        .collection('notification_history')
        .doc();
      batch.set(ref, {
        title: payload.title || '',
        body: payload.body || '',
        source: payload.source || 'server_push',
        ...(payload.postId ? { postId: payload.postId } : {}),
        ...(payload.pickId ? { pickId: payload.pickId } : {}),
        ...(payload.journalId ? { journalId: payload.journalId } : {}),
        sentAt,
        updatedAt: sentAt,
      });
    }
    await batch.commit();
  }
}

function isNotificationEnabled(userData, key) {
  const settings = userData?.notificationSettings || {};
  const userTouched = settings?._userTouched === true;
  const legacyAllCoreOff =
    settings?.newPick === false &&
    settings?.pickComment === false &&
    settings?.postComment === false &&
    settings?.journalComment === false;

  // Legacy bug guard:
  // If all core notifications are false but user never explicitly touched settings,
  // treat missing/false as default-on to avoid globally silencing push.
  if (!userTouched && legacyAllCoreOff) {
    if (key === 'journalWriteReminder') return false;
    return true;
  }

  const value = settings?.[key];
  return typeof value === 'boolean' ? value : true;
}

async function filterUsersByGlobalSetting(db, uidSet, key) {
  const uids = Array.from(uidSet).filter(
    (uid) => typeof uid === 'string' && uid.length > 0
  );
  if (uids.length === 0) return new Set();

  const allowed = new Set();
  for (let i = 0; i < uids.length; i += 30) {
    const chunk = uids.slice(i, i + 30);
    const snap = await db
      .collection('users')
      .where(FieldPath.documentId(), 'in', chunk)
      .get();
    snap.docs.forEach((d) => {
      if (isNotificationEnabled(d.data(), key)) allowed.add(d.id);
    });
  }
  return allowed;
}

async function getAllUserUidsByGlobalSetting(db, key, excludeUid) {
  const snap = await db.collection('users').get();
  const allowed = new Set();
  snap.docs.forEach((d) => {
    if (d.id === excludeUid) return;
    if (isNotificationEnabled(d.data(), key)) allowed.add(d.id);
  });
  return allowed;
}

async function getFollowerUids(db, followCollection, targetUid) {
  try {
    const snap = await db
      .collectionGroup(followCollection)
      .where('targetUid', '==', targetUid)
      .where('enabled', '==', true)
      .get();
    const uids = new Set();
    snap.docs.forEach((d) => {
      const uid = d.ref.parent.parent?.id;
      if (uid && uid !== targetUid) uids.add(uid);
    });
    return uids;
  } catch (e) {
    // Safety fallback: keep notifications working even if index/query precondition fails.
    console.warn(`getFollowerUids fallback (${followCollection}):`, e?.message || e);
    const uids = new Set();
    const usersSnap = await db.collection('users').get();
    for (const userDoc of usersSnap.docs) {
      const uid = userDoc.id;
      if (!uid || uid === targetUid) continue;
      const followDoc = await db
        .collection('users')
        .doc(uid)
        .collection(followCollection)
        .doc(targetUid)
        .get();
      if (!followDoc.exists) continue;
      if (followDoc.data()?.enabled === true) uids.add(uid);
    }
    return uids;
  }
}

exports.crawlDailyInvestorFlow = crawlDailyInvestorFlow;
exports.runDailyInvestorFlowNow = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 120 },
  async () => {
    const data = await collectDailyInvestorFlow();
    await saveDailyInvestorFlow(data);
    return {
      ok: true,
      marketDate: data.marketDate,
      kospiForeignCount: data.kospi.foreignTop5.length,
      kospiInstitutionCount: data.kospi.institutionTop5.length,
      kosdaqForeignCount: data.kosdaq.foreignTop5.length,
      kosdaqInstitutionCount: data.kosdaq.institutionTop5.length,
    };
  }
);

// ── 신규 가입자 → 관리자에게 알림 ────────────────────────────────────────────
exports.notifyAdminOnNewUser = auth.user().onCreate(async (user) => {
  const db = getFirestore();

  // config/admin 문서에서 관리자 UID 조회
  const adminSnap = await db.collection('config').doc('admin').get();
  const adminUid = adminSnap.data()?.uid;
  if (!adminUid) return;

  // 관리자 FCM 토큰 조회
  const tokensSnap = await db.collection('fcm_tokens')
    .where('uid', '==', adminUid).get();
  const tokens = tokensSnap.docs
    .map((d) => d.data().token)
    .filter((t) => typeof t === 'string' && t.length > 0);
  if (tokens.length === 0) return;

  const displayName = user.displayName || user.email || '알 수 없음';
  const provider = user.providerData?.[0]?.providerId ?? 'unknown';

  await getMessaging().sendEachForMulticast({
    notification: {
      title: PUSH_TEXT.newUserTitle,
      body: `${displayName} (${provider})`,
    },
    android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
    apns: { payload: { aps: { sound: 'default' } } },
    tokens,
  });
});

// ── 댓글 알림 (새 댓글 → 같은 종목 댓글 작성자들에게 푸시) ──────────────────
exports.sendCommentNotification = onDocumentCreated(
  { document: 'stock_picks/{pickId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { pickId } = event.params;
    const db = getFirestore();

    // 종목 이름 조회
    const pickSnap = await db.collection('stock_picks').doc(pickId).get();
    const pickName = pickSnap.data()?.name ?? PUSH_TEXT.stockFallback;

    // same pick commenters
    const commentsSnap = await db
      .collection('stock_picks').doc(pickId).collection('comments').get();
    const commenterUids = new Set(
      commentsSnap.docs
        .map((d) => d.data().uid)
        .filter((u) => u && u !== commenterUid)
    );

    // 댓글 알림 대상: 해당 추천주에 댓글을 작성한 사용자만 (작성자 제외)
    if (commenterUids.size === 0) return;

    const globalAllowed = await filterUsersByGlobalSetting(
      db,
      commenterUids,
      'pickComment'
    );
    if (globalAllowed.size === 0) return;

    // apply per-pick off
    const recipientUids = new Set();
    for (const uid of globalAllowed) {
      const subDoc = await db
        .collection('users')
        .doc(uid)
        .collection('pick_comment_subscriptions')
        .doc(pickId)
        .get();
      const enabled = subDoc.exists ? (subDoc.data()?.enabled !== false) : true;
      if (enabled) recipientUids.add(uid);
    }
    if (recipientUids.size === 0) return;

    const tokens = await getTokensByUids(db, recipientUids);
    if (tokens.length === 0) return;

    const senderName = nickname || PUSH_TEXT.someone;
    const preview = content?.length > 30 ? content.slice(0, 30) + '…' : content;

    // FCM 발송
    const chunkSize = 500;
    const invalidTokens = [];
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: `\uD83D\uDCAC ${pickName} ${PUSH_TEXT.newCommentSuffix}`,
          body: `${senderName}: ${preview}`,
        },
        data: { pickId },
        android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
        apns: { payload: { aps: { sound: 'default' } } },
        tokens: chunk,
      });
      response.responses.forEach((r, idx) => {
        if (!r.success &&
          (r.error?.code === 'messaging/invalid-registration-token' ||
           r.error?.code === 'messaging/registration-token-not-registered')) {
          invalidTokens.push(chunk[idx]);
        }
      });
    }

    // 만료 토큰 정리
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }

    await writeNotificationHistoryForUids(db, recipientUids, {
      title: `\uD83D\uDCAC ${pickName} ${PUSH_TEXT.newCommentSuffix}`,
      body: `${senderName}: ${preview}`,
      source: 'server_pick_comment',
      pickId,
    });
  }
);

// ── 자유게시판 댓글 알림 (새 댓글 → 게시글 작성자에게 푸시) ──────────────────
exports.sendPostCommentNotification = onDocumentCreated(
  { document: 'posts/{postId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { postId } = event.params;
    const db = getFirestore();

    // 게시글 조회 → 작성자 UID 확인
    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;

    const postData = postSnap.data();
    const authorUid = postData?.uid;

    // 자기 글에 자기가 댓글 → 알림 없음
    if (!authorUid || authorUid === commenterUid) return;

    // per-post off
    const postSubDoc = await db
      .collection('users')
      .doc(authorUid)
      .collection('post_comment_subscriptions')
      .doc(postId)
      .get();
    if ((postSubDoc.data()?.enabled ?? true) === false) return;

    // global off
    const allowedPostUsers = await filterUsersByGlobalSetting(
      db,
      new Set([authorUid]),
      'postComment'
    );
    if (!allowedPostUsers.has(authorUid)) return;

    // author tokens
    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid).get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || PUSH_TEXT.someone;
    const preview = content?.length > 30 ? content.slice(0, 30) + '…' : content;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: PUSH_TEXT.myPostCommentTitle,
          body: `${senderName}: ${preview}`,
        },
        data: { postId },
        android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
        apns: { payload: { aps: { sound: 'default' } } },
        tokens: chunk,
      });
      response.responses.forEach((r, idx) => {
        if (!r.success &&
          (r.error?.code === 'messaging/invalid-registration-token' ||
           r.error?.code === 'messaging/registration-token-not-registered')) {
          invalidTokens.push(chunk[idx]);
        }
      });
    }

    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }

    await writeNotificationHistoryForUids(db, new Set([authorUid]), {
      title: PUSH_TEXT.myPostCommentTitle,
      body: `${senderName}: ${preview}`,
      source: 'server_post_comment',
      postId,
    });
  }
);

exports.notifyPostAuthorFollowers = onDocumentCreated(
  { document: 'posts/{postId}', region: 'asia-northeast3' },
  async (event) => {
    const post = event.data?.data();
    if (!post) return;

    const authorUid = post.uid;
    if (!authorUid) return;

    const db = getFirestore();
    const followerUids = await getFollowerUids(
      db,
      'post_author_follows',
      authorUid
    );
    if (followerUids.size === 0) return;

    const tokens = await getTokensByUids(db, followerUids);
    if (tokens.length === 0) return;

    const title = post.title || PUSH_TEXT.newFreePost;
    const nickname = post.nickname || PUSH_TEXT.authorFallback;
    await getMessaging().sendEachForMulticast({
      notification: {
        title: `${nickname}${PUSH_TEXT.newPostSuffix}`,
        body: title,
      },
      data: { postId: event.params.postId },
      android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
      apns: { payload: { aps: { sound: 'default' } } },
      tokens,
    });

    await writeNotificationHistoryForUids(db, followerUids, {
      title: `${nickname}${PUSH_TEXT.newPostSuffix}`,
      body: title,
      source: 'server_post_author_follow',
      postId: event.params.postId,
    });
  }
);

// Journal comment notification -> journal author
exports.sendJournalCommentNotification = onDocumentCreated(
  { document: 'trading_journal/{journalId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { journalId } = event.params;
    const db = getFirestore();

    const journalSnap = await db.collection('trading_journal').doc(journalId).get();
    if (!journalSnap.exists) return;

    const journalData = journalSnap.data() || {};
    const authorUid = journalData.uid;
    if (!authorUid || authorUid === commenterUid) return;

    const allowedJournalUsers = await filterUsersByGlobalSetting(
      db,
      new Set([authorUid]),
      'journalComment'
    );
    if (!allowedJournalUsers.has(authorUid)) return;

    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid)
      .get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || PUSH_TEXT.someone;
    const previewRaw = typeof content === 'string' ? content : '';
    const preview = previewRaw.length > 30 ? `${previewRaw.slice(0, 30)}...` : previewRaw;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: PUSH_TEXT.journalCommentTitle,
          body: `${senderName}: ${preview}`,
        },
        data: { journalId },
        android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
        apns: { payload: { aps: { sound: 'default' } } },
        tokens: chunk,
      });

      response.responses.forEach((r, idx) => {
        if (!r.success &&
          (r.error?.code === 'messaging/invalid-registration-token' ||
           r.error?.code === 'messaging/registration-token-not-registered')) {
          invalidTokens.push(chunk[idx]);
        }
      });
    }

    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }

    await writeNotificationHistoryForUids(db, new Set([authorUid]), {
      title: PUSH_TEXT.journalCommentTitle,
      body: `${senderName}: ${preview}`,
      source: 'server_journal_comment',
      journalId,
    });
  }
);

// Backfill publishedAt for public journal docs
exports.ensureJournalPublishedAt = onDocumentWritten(
  { document: 'trading_journal/{journalId}', region: 'asia-northeast3' },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;

    const data = after.data() || {};
    if (data.isPublic !== true) return;
    if (data.publishedAt != null) return;

    const fallbackPublishedAt = data.createdAt ?? new Date();
    await after.ref.update({ publishedAt: fallbackPublishedAt });
  }
);

// ── 펨코지수: 30분마다 에펨코리아 주식게시판 글 수 수집 ──────────────────────
exports.crawlFemcoIndex = onSchedule(
  { schedule: 'every 30 minutes', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const cutoff = new Date(now.getTime() - 30 * 60 * 1000); // 30분 전

    try {
      const headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'ko-KR,ko;q=0.9',
        'Referer': 'https://www.fmkorea.com/',
      };

      // 에펨코리아 주식 게시판 1~3페이지 수집
      let count = 0;
      for (let page = 1; page <= 3; page++) {
        const { data } = await axios.get(
          `https://www.fmkorea.com/index.php?mid=stock&listStyle=list&page=${page}`,
          { headers, timeout: 15000 }
        );
        const $ = cheerio.load(data);

        let hitCutoff = false;
        $('ul.list_body li.li').each((_, el) => {
          const timeText = $(el).find('.time, .regdate, span[class*="date"]').text().trim();
          // 시간 파싱: "HH:MM" 형식이면 오늘 날짜로, "MM.DD" 이면 과거
          if (!timeText) return;

          let postDate = null;
          if (/^\d{2}:\d{2}$/.test(timeText)) {
            const [h, m] = timeText.split(':').map(Number);
            postDate = new Date(now);
            postDate.setHours(h, m, 0, 0);
          } else {
            // MM.DD 형식이면 오늘보다 과거
            hitCutoff = true;
            return false;
          }

          if (postDate >= cutoff) {
            count++;
          } else {
            hitCutoff = true;
            return false;
          }
        });

        if (hitCutoff) break;
      }

      // Firestore 저장
      const slotKey = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}_${String(now.getHours()).padStart(2,'0')}:${now.getMinutes() < 30 ? '00' : '30'}`;

      await db.collection('board_index').doc('femco')
        .collection('logs').doc(slotKey).set({
          count,
          timestamp: now,
          slot: slotKey,
        });

      // 최신값 갱신
      await db.collection('board_index').doc('femco').set({
        count,
        updatedAt: now,
        slot: slotKey,
      }, { merge: true });

    } catch (_) {
    }
  }
);

// ── 카카오 인증코드 → Firebase 커스텀 토큰 (웹 admin용) ──────────────────────
exports.kakaoAuthCode = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const { code, redirectUri } = request.data;
    if (!code || !redirectUri) {
      throw new HttpsError('invalid-argument', 'code와 redirectUri가 필요합니다.');
    }

    // 인증코드 → 액세스 토큰
    const tokenRes = await axios.post(
      'https://kauth.kakao.com/oauth/token',
      new URLSearchParams({
        grant_type: 'authorization_code',
        client_id: 'cc0d470794e8b40751586a607e301770',
        redirect_uri: redirectUri,
        code,
      }).toString(),
      { headers: { 'Content-Type': 'application/x-www-form-urlencoded' } }
    );
    const accessToken = tokenRes.data.access_token;

    // 액세스 토큰 → 유저 정보
    const userRes = await axios.get('https://kapi.kakao.com/v2/user/me', {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const kakaoId = String(userRes.data.id);
    const uid = `kakao:${kakaoId}`;

    const customToken = await getAuth().createCustomToken(uid, {
      provider: 'kakao',
      kakaoId,
    });
    return { customToken };
  }
);

// ── 카카오 커스텀 토큰 발급 ────────────────────────────────────────────────
// 클라이언트에서 카카오 액세스 토큰을 보내면 서버에서 검증 후 Firebase 커스텀 토큰 반환
exports.createKakaoCustomToken = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const { accessToken } = request.data;
    if (!accessToken) {
      throw new HttpsError('invalid-argument', 'accessToken이 필요합니다.');
    }

    // 카카오 API로 액세스 토큰 검증
    const kakaoUser = await new Promise((resolve, reject) => {
      const options = {
        hostname: 'kapi.kakao.com',
        path: '/v2/user/me',
        method: 'GET',
        headers: { Authorization: `Bearer ${accessToken}` },
      };
      const req = https.request(options, (res) => {
        let body = '';
        res.on('data', (chunk) => (body += chunk));
        res.on('end', () => {
          if (res.statusCode !== 200) {
            reject(new HttpsError('unauthenticated', '유효하지 않은 카카오 토큰입니다.'));
          } else {
            resolve(JSON.parse(body));
          }
        });
      });
      req.on('error', (e) => reject(new HttpsError('internal', e.message)));
      req.end();
    });

    const kakaoId = String(kakaoUser.id);
    const uid = `kakao:${kakaoId}`;

    // Firebase 커스텀 토큰 생성
    const customToken = await getAuth().createCustomToken(uid, {
      provider: 'kakao',
      kakaoId,
    });

    return { customToken };
  }
);

// ── FCM 푸시 알림 발송 (notification_queue 트리거) ────────────────────────
exports.sendPushOnNotificationQueue = onDocumentCreated(
  { document: 'notification_queue/{docId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { title, body } = data;
    const topic = data.topic || 'stock_alerts';
    if (!title && !body) return;

    const db = getFirestore();

    let recipientUids = new Set();
    let tokens = [];
    if (topic === 'new_pick_alerts') {
      recipientUids = await getAllUserUidsByGlobalSetting(db, 'newPick');
      tokens = await getTokensByUids(db, recipientUids);
    } else {
      const tokensSnap = await db.collection('fcm_tokens').get();
      const tokenSet = new Set();
      tokensSnap.docs.forEach((d) => {
        const token = d.data().token;
        const uid = d.data().uid;
        if (typeof token === 'string' && token.length > 0) tokenSet.add(token);
        if (typeof uid === 'string' && uid.length > 0) recipientUids.add(uid);
      });
      tokens = Array.from(tokenSet);
    }

    if (tokens.length === 0) {
      await writeNotificationHistoryForUids(db, recipientUids, {
        title,
        body,
        source: topic === 'new_pick_alerts' ? 'server_new_pick' : 'server_push',
      });
      await event.data.ref.delete();
      return;
    }

    // FCM 멀티캐스트 발송 (한 번에 최대 500개)
    const chunkSize = 500;
    const invalidTokens = [];

    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: { title, body },
        android: {
          notification: {
            sound: 'default',
            channelId: 'stockstorage_alerts',
          },
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
        tokens: chunk,
      });

      response.responses.forEach((r, idx) => {
        if (
          !r.success &&
          (r.error?.code === 'messaging/invalid-registration-token' ||
            r.error?.code === 'messaging/registration-token-not-registered')
        ) {
          invalidTokens.push(chunk[idx]);
        }
      });
    }

    // 만료된 토큰 정리
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }

    await writeNotificationHistoryForUids(db, recipientUids, {
      title,
      body,
      source: topic === 'new_pick_alerts' ? 'server_new_pick' : 'server_push',
    });

    // 처리 완료된 큐 문서 삭제
    await event.data.ref.delete();
  }
);

// ── KOSPI 200 야간선물 현재가 (KIS API) ──────────────────────────────────────
let _kisToken = null;
let _kisTokenExpiry = null;

async function getKisToken(appKey, appSecret) {
  const now = Date.now();
  if (_kisToken && _kisTokenExpiry && now < _kisTokenExpiry) {
    return _kisToken;
  }
  const res = await axios.post('https://openapi.koreainvestment.com:9443/oauth2/tokenP', {
    grant_type: 'client_credentials',
    appkey: appKey,
    appsecret: appSecret,
  });
  _kisToken = res.data.access_token;
  _kisTokenExpiry = now + (res.data.expires_in - 300) * 1000; // 5분 여유
  return _kisToken;
}

// 해당 연/월의 두 번째 목요일(선물 최종거래일) 날짜 반환
exports.getKisDomesticQuote = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 10 },
  async (request) => {
    const ticker = String(request.data?.ticker || '').replace(/\D/g, '');
    if (!/^\d{6}$/.test(ticker)) {
      throw new HttpsError('invalid-argument', 'Valid 6-digit ticker is required.');
    }

    const db = getFirestore();
    const snap = await db.collection('_admin').doc('kis').get();
    if (!snap.exists) throw new HttpsError('not-found', 'KIS config not found');

    const { appKey, appSecret } = snap.data() || {};
    if (!appKey || !appSecret) {
      throw new HttpsError('failed-precondition', 'KIS appKey/appSecret is missing');
    }

    try {
      const token = await getKisToken(appKey, appSecret);
      const res = await axios.get(
        'https://openapi.koreainvestment.com:9443/uapi/domestic-stock/v1/quotations/inquire-price',
        {
          headers: {
            authorization: `Bearer ${token}`,
            appkey: appKey,
            appsecret: appSecret,
            tr_id: 'FHKST01010100',
            custtype: 'P',
          },
          params: {
            FID_COND_MRKT_DIV_CODE: 'J',
            FID_INPUT_ISCD: ticker,
          },
          timeout: 8000,
        }
      );

      const output = res.data?.output || {};
      const price = Number(String(output.stck_prpr || '').replace(/,/g, ''));
      if (!Number.isFinite(price) || price <= 0) {
        return { hasData: false };
      }

      const rawChange = Number(String(output.prdy_vrss || '0').replace(/,/g, '')) || 0;
      const rawRate = Number(String(output.prdy_ctrt || '0').replace(/,/g, '')) || 0;
      const sign = String(output.prdy_vrss_sign || '');
      const direction = sign === '4' || sign === '5' ? -1 : 1;
      const change = rawChange === 0 ? 0 : Math.abs(rawChange) * direction;
      const changeRate = rawRate === 0 ? 0 : Math.abs(rawRate) * direction;

      return {
        hasData: true,
        ticker,
        price,
        change,
        changeRate,
      };
    } catch (e) {
      console.error('[getKisDomesticQuote] failed:', e.response?.data || e.message);
      return { hasData: false };
    }
  }
);

function getSecondThursday(year, month) {
  const firstDay = new Date(Date.UTC(year, month - 1, 1));
  const dow = firstDay.getUTCDay(); // 0=일, 4=목
  const firstThursday = 1 + (4 - dow + 7) % 7;
  return firstThursday + 7;
}

// KOSPI200 야간선물 단축코드: A0 + (year-2010 2자리) + 월 2자리
// 최종거래일(분기 두 번째 목요일) 이후면 다음 분기물로 전환
function getNightFuturesSymbol() {
  const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth() + 1;
  const day = kst.getUTCDate();

  const qMonths = [3, 6, 9, 12];
  let expiryMonth = qMonths.find(m => m >= month);
  let expiryYear = year;
  if (!expiryMonth) { expiryMonth = 3; expiryYear = year + 1; }

  // 현재 분기월이고, 최종거래일 이후면 다음 분기물 사용
  if (expiryMonth === month && expiryYear === year) {
    const lastTradingDay = getSecondThursday(year, month);
    if (day > lastTradingDay) {
      const idx = qMonths.indexOf(expiryMonth);
      if (idx < qMonths.length - 1) {
        expiryMonth = qMonths[idx + 1];
      } else {
        expiryMonth = 3;
        expiryYear = year + 1;
      }
    }
  }

  return `A0${String(expiryYear - 2010).padStart(2, '0')}${String(expiryMonth).padStart(2, '0')}`;
}

// KIS WebSocket 승인키 발급
async function getKisApprovalKey(appKey, appSecret) {
  const res = await axios.post(
    'https://openapi.koreainvestment.com:9443/oauth2/Approval',
    { grant_type: 'client_credentials', appkey: appKey, secretkey: appSecret }
  );
  return res.data.approval_key;
}

// AES-256-CBC 복호화
function aesDecrypt(encData, key, iv) {
  const crypto = require('crypto');
  const decipher = crypto.createDecipheriv(
    'aes-256-cbc',
    Buffer.from(key, 'utf8'),
    Buffer.from(iv, 'utf8'),
  );
  let dec = decipher.update(encData, 'base64', 'utf8');
  dec += decipher.final('utf8');
  return dec;
}

// KIS WebSocket으로 야간선물 실시간 체결가 1회 수신 (재시도 포함)
function fetchViaWebSocket(approvalKey, symbol, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let aesKey = null;
    let aesIv = null;
    const done = (fn, val) => { if (!settled) { settled = true; clearTimeout(timer); try { ws.terminate(); } catch(_){} fn(val); } };

    const timer = setTimeout(() => done(reject, new Error('timeout')), timeoutMs);

    const ws = new WebSocket('ws://ops.koreainvestment.com:21000');

    ws.on('open', () => {
      console.log('[WS] 연결됨');
      ws.send(JSON.stringify({
        header: { approval_key: approvalKey, custtype: 'P', tr_type: '1', 'content-type': 'utf-8' },
        body: { input: { tr_id: 'H0UPANC0', tr_key: symbol } },
      }));
    });

    ws.on('message', (raw) => {
      const msg = raw.toString();
      if (msg.startsWith('{')) {
        try {
          const json = JSON.parse(msg);
          if (json.header?.tr_id === 'PINGPONG') { ws.send(msg); return; }
          if (json.body?.rt_cd === '9' && json.body?.msg_cd === 'OPSP8996') {
            done(reject, new Error('ALREADY_IN_USE')); return;
          }
          // SUBSCRIBE SUCCESS → AES 키 저장
          if (json.body?.msg1 === 'SUBSCRIBE SUCCESS') {
            aesKey = json.body?.output?.key;
            aesIv  = json.body?.output?.iv;
            console.log('[WS] 구독 성공, 암호화키 수신:', !!aesKey);
          }
        } catch (_) {}
        return;
      }

      const parts = msg.split('|');
      console.log('[WS] 파이프메시지:', parts[0], parts[1], parts[2], parts[3]?.slice(0, 60));
      if (parts.length < 4 || parts[1] !== 'H0UPANC0') return;

      let dataStr = parts[3];

      // 암호화된 경우 복호화
      if (parts[0] === '1') {
        if (!aesKey || !aesIv) {
          console.warn('[WS] 암호화 데이터인데 키 없음');
          return;
        }
        try {
          dataStr = aesDecrypt(dataStr, aesKey, aesIv);
        } catch (e) {
          console.error('[WS] 복호화 실패:', e.message);
          return;
        }
      }

      // 데이터 건수(parts[2])만큼 레코드가 있을 수 있음 → 첫 번째만 사용
      const firstRecord = dataStr.split('^' + symbol).shift() || dataStr;
      const fields = firstRecord.split('^');
      console.log('[WS] fields[0..9]:', fields.slice(0, 10).join(', '));

      // H0UPANC0 필드: 0:단축코드 1:영업일자 2:체결시각 3:현재가 4:전일대비 5:등락률
      const price = parseFloat(fields[3]);
      const change = parseFloat(fields[4]);
      const changeRate = parseFloat(fields[5]);
      if (!price || price <= 0) {
        console.warn('[WS] 가격 파싱 실패, fields:', fields.slice(0, 8).join(', '));
        return;
      }

      console.log('[WS] 체결가 수신:', price, change, changeRate);
      done(resolve, { price, change, changeRate });
    });

    ws.on('error', (e) => { console.error('[WS] 에러:', e.message); done(reject, e); });
  });
}

// approvalKey 재발급 후 재시도 포함 fetchViaWebSocket
async function fetchWithRetry(appKey, appSecret, symbol) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const approvalKey = await getKisApprovalKey(appKey, appSecret);
      const data = await fetchViaWebSocket(approvalKey, symbol, 20000); // 20초
      return data;
    } catch (e) {
      console.error(`[WS] 시도 ${attempt} 실패:`, e.message);
      if (attempt < 2) {
        await new Promise(r => setTimeout(r, 1000));
      } else {
        throw e;
      }
    }
  }
}

// ── 야간선물 가격 5분마다 Firestore에 기록 (히스토리 축적) ──────────────────
exports.recordNightFuturesPrice = onSchedule(
  { schedule: 'every 1 minutes', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
    const kstHour = kst.getUTCHours();
    if (kstHour >= 5 && kstHour < 18) return; // 낮 시간 스킵

    const db = getFirestore();
    const snap = await db.collection('_admin').doc('kis').get();
    if (!snap.exists) return;

    const { appKey, appSecret } = snap.data();
    const symbol = getNightFuturesSymbol();

    try {
      const data = await fetchWithRetry(appKey, appSecret, symbol);

      const tsKey = kst.toISOString().slice(0, 16).replace('T', '_');
      await db.collection('night_futures_prices').doc(tsKey).set({
        price: data.price,
        change: data.change,
        changeRate: data.changeRate,
        timestamp: kst,
        symbol,
      });

      // 7일 이상 된 데이터 정리 (최대 2000개 유지)
      const old = await db.collection('night_futures_prices')
        .orderBy('timestamp', 'desc').offset(2000).limit(100).get();
      if (!old.empty) {
        const batch = db.batch();
        old.docs.forEach(d => batch.delete(d.ref));
        await batch.commit();
      }
    } catch (_) {}
  }
);

// ── 야간선물 설정 반환 (approval_key + symbol + 히스토리) ──────────────────
exports.getKisNightFuturesConfig = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 15 },
  async () => {
    const db = getFirestore();
    const snap = await db.collection('_admin').doc('kis').get();
    if (!snap.exists) throw new HttpsError('not-found', 'KIS 설정 없음');

    const { appKey, appSecret } = snap.data();
    const symbol = getNightFuturesSymbol();
    const approvalKey = await getKisApprovalKey(appKey, appSecret);

    // 최근 300개 (5분봉 기준 약 25시간)
    const histSnap = await db.collection('night_futures_prices')
      .orderBy('timestamp', 'desc').limit(300).get();

    const history = histSnap.docs.reverse().map(d => ({
      time: d.data().timestamp.toMillis(),
      price: d.data().price,
    }));

    return { approvalKey, symbol, history };
  }
);

// getKospiNightFutures: WebSocket 없이 Firestore 최신 데이터만 반환
// (WebSocket은 recordNightFuturesPrice 스케줄러만 사용 — appkey 충돌 방지)
exports.getKospiNightFutures = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 10 },
  async () => {
    const db = getFirestore();
    const symbol = getNightFuturesSymbol();

    const histSnap = await db.collection('night_futures_prices')
      .orderBy('timestamp', 'desc').limit(1).get();

    if (histSnap.empty) {
      console.warn('[getKospiNightFutures] night_futures_prices 컬렉션 비어 있음');
      return { hasData: false };
    }

    const d = histSnap.docs[0].data();
    return {
      hasData: true,
      name: `KOSPI200 야간선물 (${symbol})`,
      price: d.price,
      change: d.change,
      changeRate: d.changeRate,
      prevClose: d.price - d.change,
      volume: 0,
      sign: d.change >= 0 ? '2' : '4',
    };
  }
);

// ── 펨코 주갤 크롤링 공통 로직 ──────────────────────────────────────────────
async function _scrapeFmkoreaIndex() {
  const db = getFirestore();
  const now = new Date();
  const today = new Date(now.getTime() + 9 * 60 * 60 * 1000); // KST
  const fmt = (d) => {
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const dd = String(d.getUTCDate()).padStart(2, '0');
    return `${y}.${m}.${dd}`;
  };
  const todayKey = fmt(today);
  const counts = {};
  const headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'ko-KR,ko;q=0.9',
  };

  for (let page = 1; page <= 30; page++) {
    let html;
    try {
      const res = await axios.get(`https://www.fmkorea.com/stock?page=${page}`, {
        headers,
        timeout: 10000,
      });
      html = res.data;
    } catch (_) {
      break;
    }

    const $ = cheerio.load(html);
    let hitOld = false;

    $('td.time').each((_, el) => {
      const t = $(el).text().trim();
      let key = null;

      if (/^\d{2}:\d{2}$/.test(t)) {
        key = todayKey;
      } else if (/^\d{2}\.\d{2}$/.test(t)) {
        const parts = t.split('.');
        const mm = parseInt(parts[0]);
        const dd = parseInt(parts[1]);
        const d = new Date(Date.UTC(today.getUTCFullYear(), mm - 1, dd));
        const diffDays = Math.floor((today - d) / 86400000);
        if (diffDays > 7) { hitOld = true; return false; }
        key = fmt(d);
      } else if (/^\d{4}\.\d{2}\.\d{2}$/.test(t)) {
        const parts = t.split('.');
        const d = new Date(Date.UTC(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2])));
        const diffDays = Math.floor((today - d) / 86400000);
        if (diffDays > 7) { hitOld = true; return false; }
        key = t;
      }

      if (key) counts[key] = (counts[key] || 0) + 1;
    });

    if (hitOld) break;
  }

  const batch = db.batch();
  for (const [dateKey, count] of Object.entries(counts)) {
    const ref = db.collection('fmkorea_index').doc(dateKey);
    batch.set(ref, { count, updatedAt: new Date() }, { merge: true });
  }
  await batch.commit();
  return counts;
}

// ── 펨코 주갤 일자별 게시글 수 집계 (1시간마다) ──────────────────────────────
exports.fetchFmkoreaIndex = onSchedule(
  { schedule: 'every 60 minutes', region: 'asia-northeast3', timeoutSeconds: 120 },
  async () => { await _scrapeFmkoreaIndex(); }
);

// ── 펨코 주갤 수동 트리거 (최초 1회 실행용) ──────────────────────────────────
exports.fetchFmkoreaIndexNow = onRequest(
  { region: 'asia-northeast3', timeoutSeconds: 120 },
  async (req, res) => {
    try {
      const testRes = await axios.get('https://www.fmkorea.com/stock?page=1', {
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept-Language': 'ko-KR,ko;q=0.9',
        },
        timeout: 10000,
      });
      const cheerio = require('cheerio');
      const $ = cheerio.load(testRes.data);
      const times = [];
      $('td.time').each((_, el) => times.push($(el).text().trim()));
      res.json({ status: testRes.status, timesFound: times.length, sample: times.slice(0, 5), htmlSnippet: testRes.data.substring(0, 500) });
    } catch(e) {
      res.json({ error: e.message, code: e.response?.status });
    }
  }
);

// ── AI 한 줄 시황 공통 로직 ──────────────────────────────────────────────────

const NAVER_MOBILE_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  'Referer': 'https://m.finance.naver.com/',
  'Accept': 'application/json',
};

const NAVER_PC_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Referer': 'https://finance.naver.com/',
  'Accept-Language': 'ko-KR,ko;q=0.9',
};

/** 네이버 금융 모바일 API에서 KOSPI / KOSDAQ 지수 가져오기 */
async function fetchMarketData() {
  const [kospiRes, kosdaqRes] = await Promise.all([
    axios.get('https://m.stock.naver.com/api/index/KOSPI/basic', { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }),
    axios.get('https://m.stock.naver.com/api/index/KOSDAQ/basic', { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }),
  ]);

  const parse = (d) => ({
    price: Number(d.closePrice?.replace(/,/g, '') || 0),
    change: Number(d.compareToPreviousClosePrice?.replace(/,/g, '') || 0),
    changeRate: Number(d.fluctuationsRatio || 0),
    isUp: d.compareToPreviousPrice?.code === '2' || Number(d.fluctuationsRatio || 0) >= 0,
    marketStatus: d.marketStatus || null,
    tradedDate: d.localTradedAt ? String(d.localTradedAt).slice(0, 10) : null,
  });

  return { kospi: parse(kospiRes.data), kosdaq: parse(kosdaqRes.data) };
}

const SECTOR_NAME_MAP = {
  '도로와철도운송': '운송',
  '항공화물운송서비스': '항공·물류',
  '생물공학': '바이오',
  '건강관리업체및서비스': '헬스케어',
  '판매업체': '유통',
  '음식료·담배': '음식료',
  '섬유·의류': '섬유의류',
  '의약품': '제약',
  '의료장비': '의료기기',
  '전기·전자': '전기전자',
  '디스플레이패널': '디스플레이',
  'IT하드웨어': 'IT하드웨어',
  '미디어·교육': '미디어·교육',
  '소매업체': '소매유통',
  '다각화된금융서비스': '금융서비스',
  '특수소매업': '특수소매',
  '복합유틸리티': '유틸리티',
  '가스유틸리티': '가스',
  '전기유틸리티': '전기',
};
const normSector = (name) => SECTOR_NAME_MAP[name] || name;

/** 네이버 금융 업종별 시세 스크래핑 (KOSPI/KOSDAQ 각각 상승/하락 top 3) */
async function fetchSectorData() {
  try {
    const [kospiRes, kosdaqRes] = await Promise.all([
      axios.get('https://finance.naver.com/sise/sise_group.nhn?type=upjong', {
        headers: NAVER_PC_HEADERS, responseType: 'arraybuffer', timeout: 8000,
      }),
      axios.get('https://finance.naver.com/sise/sise_group.nhn?type=upjong&sosok=1', {
        headers: NAVER_PC_HEADERS, responseType: 'arraybuffer', timeout: 8000,
      }),
    ]);

    const decoder = new TextDecoder('euc-kr');
    const parseSectors = (buffer) => {
      const $ = cheerio.load(decoder.decode(buffer));
      const sectors = [];
      $('table.type_1 tbody tr').each((_, row) => {
        const cells = $(row).find('td');
        if (cells.length < 3) return;
        const name = $(cells[0]).find('a').text().trim();
        if (!name) return;
        // cells[1] = 등락률(%), cells[2]=종목수, cells[3]=상승, cells[4]=보합, cells[5]=하락
        const rateText = $(cells[1]).text().trim().replace(/\s+/g, '');
        const rate = parseFloat(rateText.replace('%', '').replace(',', ''));
        if (!isNaN(rate)) sectors.push({ name: normSector(name), rate });
      });
      return sectors;
    };

    const kospiSectors = parseSectors(kospiRes.data);
    const kosdaqSectors = parseSectors(kosdaqRes.data);
    return {
      kospi: {
        up: kospiSectors.filter(s => s.rate > 0).sort((a, b) => b.rate - a.rate).slice(0, 3),
        down: kospiSectors.filter(s => s.rate < 0).sort((a, b) => a.rate - b.rate).slice(0, 3),
      },
      kosdaq: {
        up: kosdaqSectors.filter(s => s.rate > 0).sort((a, b) => b.rate - a.rate).slice(0, 3),
        down: kosdaqSectors.filter(s => s.rate < 0).sort((a, b) => a.rate - b.rate).slice(0, 3),
      },
    };
  } catch (e) {
    console.warn('[AiBrief] 업종 데이터 실패:', e.message);
    return null;
  }
}

/** 네이버 금융 모바일 API에서 코스피/코스닥 상승·하락·보합 종목수 */
async function fetchMarketBreadth() {
  try {
    const [kospiRes, kosdaqRes] = await Promise.all([
      axios.get('https://m.stock.naver.com/api/index/KOSPI/integration', { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }),
      axios.get('https://m.stock.naver.com/api/index/KOSDAQ/integration', { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }),
    ]);
    const parse = (d) => ({
      up: Number(d.risingCount || d.advancingCount || 0),
      down: Number(d.fallingCount || d.decliningCount || 0),
      flat: Number(d.steadyCount || d.unchangedCount || 0),
    });
    return { kospi: parse(kospiRes.data), kosdaq: parse(kosdaqRes.data) };
  } catch (_) { return null; }
}

/** Google News RSS에서 한국 증시 주요 뉴스 헤드라인 수집 */
async function fetchMarketNews() {
  const queries = [
    '코스피 증시 주식',
    '한국 경제 금융',
    '미국 증시 나스닥 S&P500',
  ];
  try {
    const results = await Promise.allSettled(queries.map(q =>
      axios.get(`https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=ko&gl=KR&ceid=KR:ko`, {
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
        timeout: 8000,
      })
    ));

    const seen = new Set();
    const items = [];
    for (const r of results) {
      if (r.status !== 'fulfilled') continue;
      const $ = cheerio.load(r.value.data, { xmlMode: true });
      $('item').each((_, el) => {
        if (items.length >= 12) return;
        const title = $(el).find('title').text().replace(/\s*-\s*[^-]+$/, '').trim();
        const pubDate = $(el).find('pubDate').text().trim();
        if (title && !seen.has(title)) {
          seen.add(title);
          items.push({ title, pubDate });
        }
      });
    }
    return items.slice(0, 10);
  } catch (_) { return []; }
}

/** 전일 미국장 주요 지수 */
async function fetchUsMarketData() {
  const symbols = [
    ['S&P 500', '^GSPC'],
    ['NASDAQ', '^IXIC'],
    ['Dow', '^DJI'],
  ];
  const expectedUsMarketDate = () => {
    const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
      timeZone: 'America/New_York',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      weekday: 'short',
      hour: '2-digit',
      hour12: false,
    }).formatToParts(new Date()).map(p => [p.type, p.value]));
    const date = new Date(Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)));
    const hour = Number(parts.hour === '24' ? '0' : parts.hour);
    const weekday = date.getUTCDay();
    if (hour < 16 || weekday === 0 || weekday === 6) date.setUTCDate(date.getUTCDate() - 1);
    while (date.getUTCDay() === 0 || date.getUTCDay() === 6) date.setUTCDate(date.getUTCDate() - 1);
    return date.toISOString().slice(0, 10);
  };

  try {
    const results = await Promise.allSettled(symbols.map(([name, symbol]) =>
      axios.get(`https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=5d&interval=1d`, {
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
        timeout: 8000,
      }).then((res) => {
        const result = res.data?.chart?.result?.[0];
        const quote = result?.indicators?.quote?.[0];
        const timestamps = result?.timestamp || [];
        const closes = quote?.close || [];
        const lastIndex = closes.map((v, i) => ({ v, i })).filter(x => Number.isFinite(x.v)).at(-1)?.i;
        if (lastIndex == null) return null;

        const close = closes[lastIndex];
        const prevClose = closes.slice(0, lastIndex).filter(Number.isFinite).at(-1);
        const changeRate = prevClose ? ((close - prevClose) / prevClose) * 100 : null;
        return {
          name,
          close,
          changeRate,
          date: timestamps[lastIndex] ? new Date(timestamps[lastIndex] * 1000).toISOString().slice(0, 10) : null,
        };
      })
    ));

    const indices = results
      .filter(r => r.status === 'fulfilled' && r.value)
      .map(r => r.value);
    if (!indices.length) return null;

    const latestDate = indices.map(i => i.date).filter(Boolean).sort().at(-1) || null;
    const expectedDate = expectedUsMarketDate();
    return { indices, latestDate, expectedDate, isHolidayOrStale: !!latestDate && latestDate !== expectedDate };
  } catch (_) { return null; }
}

function getAiBriefSlotMeta(slot) {
  if (slot === '09') {
    return {
      label: '장 오픈(09:00)',
      timeLabel: '09:00',
      focus: `오전 9시 장 오픈 브리핑입니다. 전일 미국장(S&P 500·NASDAQ·Dow)의 등락과 핵심 이슈가 국내장 출발에 주는 영향을 가장 먼저 설명하세요. 단, 미국장이 휴장으로 보이거나 미국장 데이터가 없으면 미국 지수 흐름을 억지로 쓰지 말고 주요 이슈와 국내장 출발 분위기 위주로 작성하세요.`,
    };
  }
  if (slot === '12') {
    return {
      label: '장중 점검(12:00)',
      timeLabel: '12:00',
      focus: '낮 12시 장중 브리핑입니다. 국장이 오전장을 지나며 어떤 흐름인지 코스피·코스닥 현재 등락, 시장 폭, 업종 등락, 수급을 중심으로 설명하세요. 미국장은 배경으로만 짧게 다루고 국내 장중 흐름을 우선하세요.',
    };
  }
  return {
    label: '장 마감(15:30)',
    timeLabel: '15:30',
    focus: '오후 3시 30분 장 마감 브리핑입니다. 장이 어떻게 마무리됐는지 최종 지수 흐름, 두드러진 업종, 수급·시장 폭을 종합해 마무리 멘트 느낌으로 정리하세요. 장중이라는 표현은 피하고 종가 기준의 정리 톤을 사용하세요.',
  };
}

function getKstDateInfo(date = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
  }).formatToParts(date).map(p => [p.type, p.value]));
  const dateKey = `${parts.year}-${parts.month}-${parts.day}`;
  return { dateKey, isWeekend: parts.weekday === 'Sat' || parts.weekday === 'Sun' };
}

function getMarketClosedInfo(marketData = null) {
  const { dateKey, isWeekend } = getKstDateInfo();
  if (isWeekend) return { reason: 'weekend', dateKey };

  const tradedDates = [marketData?.kospi?.tradedDate, marketData?.kosdaq?.tradedDate].filter(Boolean);
  const statuses = [marketData?.kospi?.marketStatus, marketData?.kosdaq?.marketStatus].filter(Boolean);
  const hasTodayTrade = tradedDates.includes(dateKey);
  const isOpenNow = statuses.some(status => status === 'OPEN');
  if (tradedDates.length > 0 && !hasTodayTrade && !isOpenNow) {
    return { reason: 'holiday', dateKey };
  }
  return null;
}

function getMarketClosedBrief(reason) {
  if (reason === 'weekend') {
    return '주말이라 한국 주식시장이 열리지 않습니다. 장이 열리는 다음 거래일에 AI 시황 브리핑이 업데이트됩니다.';
  }
  return '국내 증시 휴장일이라 장이 열리지 않습니다. 장이 열리는 다음 거래일에 AI 시황 브리핑이 업데이트됩니다.';
}

/** Firestore investor_flow에서 오늘 매매동향 가져오기 */
async function fetchInvestorFlowSummary(db) {
  try {
    const formatter = new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
    });
    const snap = await db.collection('investor_flow').doc(formatter.format(new Date())).get();
    return snap.exists ? snap.data() : null;
  } catch (_) { return null; }
}

async function generateBriefWithClaude(apiKey, marketData, sectorData, breadthData, investorFlow, news, usMarketData, slot) {
  const Anthropic = require('@anthropic-ai/sdk');
  const client = new Anthropic({ apiKey });

  const { kospi, kosdaq } = marketData;
  const slotMeta = getAiBriefSlotMeta(slot);

  let investorContext = '';
  if (investorFlow) {
    const fi = investorFlow;
    const fKospi = fi.kospi?.foreignNet != null ? (fi.kospi.foreignNet / 1e8).toFixed(0) + '억원' : null;
    const iKospi = fi.kospi?.institutionNet != null ? (fi.kospi.institutionNet / 1e8).toFixed(0) + '억원' : null;
    const fKosdaq = fi.kosdaq?.foreignNet != null ? (fi.kosdaq.foreignNet / 1e8).toFixed(0) + '억원' : null;
    if (fKospi || iKospi || fKosdaq) {
      investorContext = '\n\n[매매동향]';
      if (fKospi) investorContext += `\n- KOSPI 외국인 순매수: ${fKospi}`;
      if (iKospi) investorContext += `\n- KOSPI 기관 순매수: ${iKospi}`;
      if (fKosdaq) investorContext += `\n- KOSDAQ 외국인 순매수: ${fKosdaq}`;
    }
  }

  let sectorContext = '';
  if (sectorData) {
    const fmt = (list) => list.map(s => `${s.name}(${s.rate > 0 ? '+' : ''}${s.rate.toFixed(1)}%)`).join(', ');
    const parts = [];
    if (sectorData.kospi?.up?.length) parts.push(`KOSPI 상승: ${fmt(sectorData.kospi.up)}`);
    if (sectorData.kospi?.down?.length) parts.push(`KOSPI 하락: ${fmt(sectorData.kospi.down)}`);
    if (sectorData.kosdaq?.up?.length) parts.push(`KOSDAQ 상승: ${fmt(sectorData.kosdaq.up)}`);
    if (sectorData.kosdaq?.down?.length) parts.push(`KOSDAQ 하락: ${fmt(sectorData.kosdaq.down)}`);
    if (parts.length) sectorContext = '\n\n[업종 등락]\n- ' + parts.join('\n- ');
  }

  let breadthContext = '';
  if (breadthData) {
    const b = breadthData;
    if (b.kospi?.up || b.kospi?.down) {
      breadthContext += `\n\n[시장 폭]\n- KOSPI 상승:${b.kospi.up}개 / 하락:${b.kospi.down}개 / 보합:${b.kospi.flat}개`;
    }
    if (b.kosdaq?.up || b.kosdaq?.down) {
      breadthContext += `\n- KOSDAQ 상승:${b.kosdaq.up}개 / 하락:${b.kosdaq.down}개 / 보합:${b.kosdaq.flat}개`;
    }
  }

  let newsContext = '';
  if (news && news.length > 0) {
    newsContext = '\n\n[최신 뉴스 헤드라인]\n' + news.map((n, i) => `${i + 1}. ${n.title}`).join('\n');
  }

  let usContext = '';
  if (usMarketData?.indices?.length) {
    const fmt = usMarketData.indices
      .map(i => `${i.name}: ${i.changeRate == null ? i.close.toFixed(2) : `${i.changeRate >= 0 ? '+' : ''}${i.changeRate.toFixed(2)}%`}`)
      .join(', ');
    const staleNote = usMarketData.isHolidayOrStale ? ' (최근 거래일 데이터가 오래되어 휴장 가능성이 있습니다)' : '';
    usContext = `\n\n[전일 미국장]\n- 기준일: ${usMarketData.latestDate || '확인 불가'}${staleNote}\n- ${fmt}`;
  }

  const prompt = `지금은 한국 주식시장 ${slotMeta.label}입니다. 아래 데이터와 뉴스 헤드라인을 바탕으로 투자자를 위한 시황 브리핑을 작성해주세요.

[시간대별 작성 관점]
${slotMeta.focus}

[지수]
- 코스피: ${kospi.price.toLocaleString('ko-KR')}pt (${kospi.isUp ? '▲' : '▼'}${Math.abs(kospi.changeRate).toFixed(2)}%, ${kospi.change >= 0 ? '+' : ''}${kospi.change.toFixed(2)}pt)
- 코스닥: ${kosdaq.price.toLocaleString('ko-KR')}pt (${kosdaq.isUp ? '▲' : '▼'}${Math.abs(kosdaq.changeRate).toFixed(2)}%, ${kosdaq.change >= 0 ? '+' : ''}${kosdaq.change.toFixed(2)}pt)${usContext}${sectorContext}${breadthContext}${investorContext}${newsContext}

[작성 형식 — 반드시 아래 3개 문단을 빈 줄로 구분해서 출력]

문단1 (핵심 흐름): 시간대별 작성 관점을 반영해 가장 중요한 흐름부터 서술. 09시는 전일 미국장과 국내장 출발 연결, 12시는 국내 장중 흐름, 15:30은 장 마감 결과를 우선하세요.

문단2 (업종): 가장 두드러진 상승·하락 업종을 등락률 숫자와 함께 구체적으로 서술. 가능하면 상승 업종 1~2개와 하락 업종 1~2개를 모두 언급하고, "얼마나 올랐는지/내렸는지"가 보이게 작성. 업종 간 대조 포함. (제공된 데이터에 없는 업종명 절대 사용 금지)

문단3 (정리): 09시는 개장 초 체크할 이슈, 12시는 오후장으로 이어질 장중 포인트, 15:30은 하루를 마무리하는 정리 멘트로 작성. 뉴스가 있으면 핵심 뉴스 헤드라인의 구체 키워드(예: 미국증시, S&P500, 환율, 금리, 실적 등)를 포함하되, "투자심리에 우호적/부정적", "작용했습니다"처럼 딱딱하거나 단정적인 표현은 피하세요. "미국증시 강세 전망도 함께 거론됐습니다", "S&P500 목표치 상향 소식도 눈에 띄었습니다"처럼 자연스럽게 연결하고, 단순 헤드라인 나열은 하지 마세요.

[공통 규칙]
- 각 문단은 2~3문장
- 반드시 높임말(~습니다/~네요/~보입니다) 사용
- 사실 기반 서술만, 투자 권유·예측 금지
- 마침표로 끝낼 것
- "오늘은", "현재" 등으로 시작하지 말 것

3개 문단만 출력 (제목·번호·다른 설명 없이, 문단 사이 빈 줄 하나):`;

  const message = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 900,
    messages: [{ role: 'user', content: prompt }],
  });
  return message.content[0].text.trim();
}

async function runAiBriefGeneration(apiKey, slot) {
  const db = getFirestore();
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit',
  });
  const dateKey = formatter.format(new Date());

  const saveMarketClosedBrief = async (closedInfo, marketData = null) => {
    const slotLabel = getAiBriefSlotMeta(slot).timeLabel;
    const payload = {
      brief: getMarketClosedBrief(closedInfo.reason),
      slot,
      slotLabel,
      date: closedInfo.dateKey,
      isMarketClosed: true,
      closedReason: closedInfo.reason,
      kospi: marketData?.kospi ?? null,
      kosdaq: marketData?.kosdaq ?? null,
      sectors: null,
      generatedAt: new Date(),
    };
    const batch = db.batch();
    batch.set(db.collection('ai_briefs').doc('latest'), payload);
    batch.set(
      db.collection('ai_briefs').doc(closedInfo.dateKey),
      { [slot]: payload, updatedAt: new Date() },
      { merge: true }
    );
    await batch.commit();
    console.log(`[AiBrief] ${closedInfo.dateKey} ${slotLabel} 휴장 안내 저장 완료: ${payload.brief}`);
    return payload.brief;
  };

  const weekendClosed = getMarketClosedInfo();
  if (weekendClosed) return saveMarketClosedBrief(weekendClosed);

  let marketData;
  try {
    marketData = await fetchMarketData();
  } catch (e) {
    console.error('[AiBrief] fetchMarketData 실패 — 시황 생성 중단:', e.message);
    throw e;
  }
  const [sectorData, breadthData, investorFlow, news, usMarketData] = await Promise.all([
    fetchSectorData(),
    fetchMarketBreadth(),
    fetchInvestorFlowSummary(db),
    fetchMarketNews(),
    fetchUsMarketData(),
  ]);

  const marketClosed = getMarketClosedInfo(marketData);
  if (marketClosed) return saveMarketClosedBrief(marketClosed, marketData);

  const brief = await generateBriefWithClaude(apiKey, marketData, sectorData, breadthData, investorFlow, news, usMarketData, slot);

  const slotLabel = getAiBriefSlotMeta(slot).timeLabel;
  const payload = {
    brief, slot, slotLabel, date: dateKey,
    kospi: marketData.kospi, kosdaq: marketData.kosdaq,
    sectors: sectorData ?? null,
    generatedAt: new Date(),
  };

  const batch = db.batch();
  batch.set(db.collection('ai_briefs').doc('latest'), payload);
  batch.set(
    db.collection('ai_briefs').doc(dateKey),
    { [slot]: payload, updatedAt: new Date() },
    { merge: true }
  );
  await batch.commit();

  console.log(`[AiBrief] ${dateKey} ${slotLabel} 저장 완료: ${brief}`);
  return brief;
}

// ── AI 시황 스케줄 (평일 09:00 KST) ─────────────────────────────────────────
exports.generateAiBriefMorning = onSchedule(
  { schedule: '0 9 * * 1-5', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 120, secrets: [ANTHROPIC_API_KEY] },
  async () => { await runAiBriefGeneration(ANTHROPIC_API_KEY.value(), '09'); }
);

// ── AI 시황 스케줄 (평일 12:00 KST) ─────────────────────────────────────────
exports.generateAiBriefMidday = onSchedule(
  { schedule: '0 12 * * 1-5', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 120, secrets: [ANTHROPIC_API_KEY] },
  async () => { await runAiBriefGeneration(ANTHROPIC_API_KEY.value(), '12'); }
);

// ── AI 시황 스케줄 (평일 15:30 KST) ─────────────────────────────────────────
exports.generateAiBriefAfternoon = onSchedule(
  { schedule: '30 15 * * 1-5', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 120, secrets: [ANTHROPIC_API_KEY] },
  async () => { await runAiBriefGeneration(ANTHROPIC_API_KEY.value(), '15'); }
);

// ── AI 시황 수동 트리거 (테스트용, 관리자만) ─────────────────────────────────
exports.generateAiBriefNow = onRequest(
  { region: 'asia-northeast3', timeoutSeconds: 120, secrets: [ANTHROPIC_API_KEY] },
  async (req, res) => {
    try {
      const db = getFirestore();
      const adminSnap = await db.collection('config').doc('admin').get();
      const adminUids = adminSnap.exists ? (adminSnap.data().uids || []) : [];
      const authHeader = req.headers.authorization || '';
      const idToken = authHeader.replace('Bearer ', '');
      if (!idToken) return res.status(401).json({ error: '인증 토큰이 필요합니다.' });
      const decoded = await getAuth().verifyIdToken(idToken);
      if (!adminUids.includes(decoded.uid)) return res.status(403).json({ error: '관리자만 실행 가능합니다.' });

      const now = new Date();
      const kstHour = Number(new Intl.DateTimeFormat('en', {
        timeZone: 'Asia/Seoul', hour: 'numeric', hour12: false,
      }).format(now));
      const slot = kstHour < 11 ? '09' : kstHour < 14 ? '12' : '15';

      const brief = await runAiBriefGeneration(ANTHROPIC_API_KEY.value(), slot);
      res.json({ ok: true, brief, slot });
    } catch (e) {
      console.error('[generateAiBriefNow]', e);
      res.status(500).json({ error: e.message });
    }
  }
);
