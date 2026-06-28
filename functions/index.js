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
const AdmZip = require('adm-zip');
const eucKrDecoder = new TextDecoder('euc-kr');

const OPENAI_API_KEY = defineSecret('OPENAI_API_KEY');
const DART_API_KEY = defineSecret('DART_API_KEY');
const REVENUECAT_SECRET_API_KEY = defineSecret('REVENUECAT_SECRET_API_KEY');
const FINNHUB_API_KEY = defineSecret('FINNHUB_API_KEY');
const FRED_API_KEY = defineSecret('FRED_API_KEY');
const {
  crawlDailyInvestorFlow,
  collectDailyInvestorFlow,
  saveDailyInvestorFlow,
} = require('./investor_flow');
const { runCalendarSync, notifyTodayEvents } = require('./market_calendar');

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
      // Only token holders can receive pushes, so use fcm_tokens as the
      // candidate set and then filter by the user's notification setting.
      // Avoids scanning the entire users collection on every push.
      const tokensSnap = await db.collection('fcm_tokens').get();
      const tokensByUid = new Map();
      tokensSnap.docs.forEach((d) => {
        const data = d.data();
        const uid = data.uid;
        const token = data.token;
        if (typeof uid !== 'string' || !uid) return;
        if (typeof token !== 'string' || !token) return;
        if (!tokensByUid.has(uid)) tokensByUid.set(uid, []);
        tokensByUid.get(uid).push(token);
      });

      recipientUids = await filterUsersByGlobalSetting(
        db,
        new Set(tokensByUid.keys()),
        'newPick'
      );

      const tokenSet = new Set();
      recipientUids.forEach((uid) => {
        (tokensByUid.get(uid) || []).forEach((t) => tokenSet.add(t));
      });
      tokens = Array.from(tokenSet);
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
let _dartCorpCodeByStockCode = null;
let _dartCorpCodeFetchedAt = 0;
const NAVER_RESEARCH_LOOKBACK_DAYS = 90;
const NAVER_RESEARCH_LOOKBACK_LABEL = '최근 3개월';

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

function numOrNull(value) {
  const n = Number(String(value ?? '').replace(/,/g, ''));
  return Number.isFinite(n) ? n : null;
}

function signedNumOrNull(value) {
  const n = Number(String(value ?? '').replace(/[^\d.+-]/g, ''));
  return Number.isFinite(n) ? n : null;
}

async function getKisConfig() {
  const db = getFirestore();
  const snap = await db.collection('_admin').doc('kis').get();
  if (!snap.exists) return null;
  const { appKey, appSecret } = snap.data() || {};
  if (!appKey || !appSecret) return null;
  return { appKey, appSecret };
}

async function fetchKisDomesticSnapshot(ticker) {
  if (!/^\d{6}$/.test(String(ticker || ''))) return null;
  const config = await getKisConfig();
  if (!config) return null;
  try {
    const token = await getKisToken(config.appKey, config.appSecret);
    const res = await axios.get(
      'https://openapi.koreainvestment.com:9443/uapi/domestic-stock/v1/quotations/inquire-price',
      {
        headers: {
          authorization: `Bearer ${token}`,
          appkey: config.appKey,
          appsecret: config.appSecret,
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
    const o = res.data?.output || {};
    return {
      price: numOrNull(o.stck_prpr),
      change: numOrNull(o.prdy_vrss),
      changeRate: numOrNull(o.prdy_ctrt),
      volume: numOrNull(o.acml_vol),
      tradingValue: numOrNull(o.acml_tr_pbmn),
      marketCap: numOrNull(o.hts_avls),
      per: numOrNull(o.per),
      pbr: numOrNull(o.pbr),
      eps: numOrNull(o.eps),
      bps: numOrNull(o.bps),
      high52w: numOrNull(o.w52_hgpr),
      low52w: numOrNull(o.w52_lwpr),
      rawName: clampStockAnalysisInput(o.hts_kor_isnm, 80),
      source: 'KIS inquire-price',
    };
  } catch (e) {
    console.warn('[fetchKisDomesticSnapshot] failed:', e.response?.data || e.message);
    return null;
  }
}

function parseNaverNumeric(value) {
  const match = String(value ?? '').replace(/,/g, '').match(/-?\d+(?:\.\d+)?/);
  if (!match) return null;
  const n = Number(match[0]);
  return Number.isFinite(n) ? n : null;
}

async function fetchNaverMobileIntegration(ticker) {
  const res = await axios.get(
    `https://m.stock.naver.com/api/stock/${encodeURIComponent(ticker)}/integration`,
    {
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://m.stock.naver.com',
        'Accept': 'application/json',
      },
      timeout: 8000,
    }
  );
  return res.data && typeof res.data === 'object' ? res.data : null;
}

function naverTotalInfoValue(data, code) {
  const totalInfos = Array.isArray(data?.totalInfos) ? data.totalInfos : [];
  const item = totalInfos.find((v) => v?.code === code);
  return parseNaverNumeric(item?.value);
}

function parseNaverResearchDate(value) {
  const digits = String(value || '').replace(/\D/g, '');
  if (digits.length !== 8) return null;
  const year = Number(digits.slice(0, 4));
  const month = Number(digits.slice(4, 6));
  const day = Number(digits.slice(6, 8));
  const date = new Date(Date.UTC(year, month - 1, day));
  return Number.isFinite(date.getTime()) ? date : null;
}

async function fetchNaverPeerValuation(ticker) {
  try {
    const data = await fetchNaverMobileIntegration(ticker);
    return {
      per: naverTotalInfoValue(data, 'cnsPer') || naverTotalInfoValue(data, 'per'),
      pbr: naverTotalInfoValue(data, 'pbr'),
    };
  } catch (_) {
    return null;
  }
}

async function fetchNaverDomesticValuation(ticker) {
  if (!/^\d{6}$/.test(String(ticker || ''))) return null;
  try {
    const data = await fetchNaverMobileIntegration(ticker);
    const peers = Array.isArray(data?.industryCompareInfo)
      ? data.industryCompareInfo
      : [];
    const peerCodes = peers
      .map((p) => String(p?.itemCode || '').trim())
      .filter((code) => /^\d{6}$/.test(code))
      .slice(0, 6);
    const peerValuations = await Promise.all(peerCodes.map(fetchNaverPeerValuation));
    const perValues = peerValuations
      .map((v) => v?.per)
      .filter((v) => Number.isFinite(v) && v > 0);
    const sectorAveragePer = perValues.length
      ? perValues.reduce((a, b) => a + b, 0) / perValues.length
      : null;
    const peerComparison = peers.slice(0, 5).map((p, index) => {
      const v = peerValuations[index] || {};
      return {
        name: clampStockAnalysisInput(p?.stockName, 60),
        ticker: clampStockAnalysisInput(p?.itemCode, 12),
        per: Number.isFinite(v.per) && v.per > 0 ? v.per : null,
        pbr: Number.isFinite(v.pbr) && v.pbr > 0 ? v.pbr : null,
      };
    }).filter((p) => p.name);
    const now = Date.now();
    const recentResearches = (Array.isArray(data?.researches) ? data.researches : [])
      .map((r) => ({ ...r, parsedDate: parseNaverResearchDate(r?.wdt) }))
      .filter((r) =>
        r.parsedDate &&
        now - r.parsedDate.getTime() <= NAVER_RESEARCH_LOOKBACK_DAYS * 24 * 60 * 60 * 1000
      )
      .slice(0, 5);
    const reports = (await Promise.all(recentResearches.map(async (r) => {
      try {
        const res = await axios.get(
          `https://m.stock.naver.com/api/research/company/${encodeURIComponent(r.id)}`,
          {
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://m.stock.naver.com',
              'Accept': 'application/json',
            },
            timeout: 8000,
          }
        );
        const content = res.data?.researchContent || {};
        return {
          title: clampStockAnalysisInput(content.title || r.tit, 160),
          broker: clampStockAnalysisInput(content.brokerName || r.bnm, 80),
          date: clampStockAnalysisInput(content.writeDate || String(r.wdt || ''), 20),
          opinion: clampStockAnalysisInput(content.opinion, 40),
          targetPrice: parseNaverNumeric(content.goalPrice),
          previousTargetPrice: parseNaverNumeric(content.prevGoalPrice),
          priceAtWriteDate: parseNaverNumeric(content.priceAtWriteDate),
          url: clampStockAnalysisInput(content.attachUrl, 500),
        };
      } catch (_) {
        return {
          title: clampStockAnalysisInput(r.tit, 160),
          broker: clampStockAnalysisInput(r.bnm, 80),
          date: clampStockAnalysisInput(String(r.wdt || ''), 20),
          opinion: '',
          targetPrice: null,
          previousTargetPrice: null,
          priceAtWriteDate: null,
          url: r.id ? `https://m.stock.naver.com/investment/research/company/${encodeURIComponent(r.id)}` : '',
        };
      }
    }))).filter((r) => r.title);

    return {
      per: naverTotalInfoValue(data, 'per'),
      pbr: naverTotalInfoValue(data, 'pbr'),
      bps: naverTotalInfoValue(data, 'bps'),
      forwardPer: naverTotalInfoValue(data, 'cnsPer'),
      forwardEps: naverTotalInfoValue(data, 'cnsEps'),
      sectorAveragePer,
      peerComparison,
      reports,
    };
  } catch (e) {
    console.warn('[fetchNaverDomesticValuation] failed:', e.response?.data || e.message);
    return null;
  }
}

function parseNaverFinanceTimelineShape(data) {
  if (!data || typeof data !== 'object') return null;
  const financeInfo = data.financeInfo && typeof data.financeInfo === 'object'
    ? data.financeInfo
    : null;
  if (financeInfo && Array.isArray(financeInfo.trTitleList) && Array.isArray(financeInfo.rowList)) {
    const epsRow = financeInfo.rowList.find(
      (r) => String(r?.title || '').toUpperCase() === 'EPS',
    );
    const perRow = financeInfo.rowList.find(
      (r) => String(r?.title || '').toUpperCase() === 'PER',
    );
    if (epsRow && epsRow.columns && typeof epsRow.columns === 'object') {
      const parsed = financeInfo.trTitleList
        .map((col) => {
          const key = String(col?.key || '');
          const epsCell = epsRow.columns[key];
          const eps = parseNaverNumeric(epsCell?.value);
          if (!key || eps == null) return null;
          const period = String(col?.title || key).replace(/\.$/, '').trim();
          const estimate = String(col?.isConsensus || '').toUpperCase() === 'Y';
          const perCell = perRow?.columns?.[key];
          const per = parseNaverNumeric(perCell?.value);
          return { period, eps, per: Number.isFinite(per) ? per : null, estimate };
        })
        .filter(Boolean);
      if (parsed.length) return parsed;
    }
  }
  const items = Array.isArray(data.items)
    ? data.items
    : Array.isArray(data.financialList)
      ? data.financialList
      : Array.isArray(data.data)
        ? data.data
        : null;
  if (items && items.length && items.some((it) => it && typeof it === 'object')) {
    const parsed = items
      .map((item) => {
        const eps = parseNaverNumeric(
          item?.eps ?? item?.epsValue ?? item?.epsConsolidated ?? item?.epsCon ?? null,
        );
        const periodRaw = item?.yearMonth || item?.period || item?.bizYm || item?.term || '';
        if (eps == null || !periodRaw) return null;
        const period = String(periodRaw).trim();
        const estimate = Boolean(
          item?.estimateFlag ||
            item?.isEstimate ||
            item?.estimate ||
            period.includes('(E)') ||
            period.includes('E)'),
        );
        const per = parseNaverNumeric(item?.per ?? item?.perValue ?? null);
        return {
          period: period.replace(/\s*\(E\)\s*$/i, '').trim(),
          eps,
          per: Number.isFinite(per) ? per : null,
          estimate,
        };
      })
      .filter(Boolean);
    if (parsed.length) return parsed;
  }
  if (Array.isArray(data.rowHd) && Array.isArray(data.columnHd) && Array.isArray(data.tableData)) {
    const epsRowIndex = data.rowHd.findIndex((row) =>
      String(row?.title || row?.label || row?.name || '').toUpperCase().includes('EPS'),
    );
    if (epsRowIndex >= 0) {
      const epsRow = data.tableData[epsRowIndex];
      if (Array.isArray(epsRow)) {
        const parsed = data.columnHd
          .map((col, i) => {
            const eps = parseNaverNumeric(epsRow[i]);
            if (eps == null) return null;
            const label = String(col?.title || col?.label || col?.name || '').trim();
            const estimate = label.includes('(E)');
            return {
              period: label.replace(/\(E\)/g, '').trim(),
              eps,
              per: null,
              estimate,
            };
          })
          .filter(Boolean);
        if (parsed.length) return parsed;
      }
    }
  }
  return null;
}

async function fetchNaverEpsTimeline(ticker) {
  if (!/^\d{6}$/.test(String(ticker || ''))) return null;
  const headers = {
    'User-Agent': 'Mozilla/5.0',
    'Referer': 'https://m.stock.naver.com',
    'Accept': 'application/json',
  };
  const candidates = [
    `https://m.stock.naver.com/api/stock/${encodeURIComponent(ticker)}/finance/annual`,
    `https://api.stock.naver.com/stock/${encodeURIComponent(ticker)}/finance/annual`,
    `https://m.stock.naver.com/api/stock/${encodeURIComponent(ticker)}/finance-summary/annual`,
  ];
  for (const url of candidates) {
    try {
      const res = await axios.get(url, { headers, timeout: 8000 });
      const parsed = parseNaverFinanceTimelineShape(res.data);
      if (parsed && parsed.length) {
        return parsed.slice(-8);
      }
    } catch (_) {
      // try next
    }
  }
  return null;
}

async function getDartCorpCodeMap(apiKey) {
  const now = Date.now();
  if (_dartCorpCodeByStockCode && now - _dartCorpCodeFetchedAt < 24 * 60 * 60 * 1000) {
    return _dartCorpCodeByStockCode;
  }
  const res = await axios.get('https://opendart.fss.or.kr/api/corpCode.xml', {
    params: { crtfc_key: apiKey },
    responseType: 'arraybuffer',
    timeout: 15000,
  });
  const zip = new AdmZip(Buffer.from(res.data));
  const entry = zip.getEntries().find((e) => !e.isDirectory);
  if (!entry) throw new Error('DART corpCode zip is empty');
  const xml = entry.getData().toString('utf8');
  const map = new Map();
  const blocks = xml.match(/<list>[\s\S]*?<\/list>/g) || [];
  for (const block of blocks) {
    const corpCode = (block.match(/<corp_code>([\s\S]*?)<\/corp_code>/)?.[1] || '').trim();
    const corpName = (block.match(/<corp_name>([\s\S]*?)<\/corp_name>/)?.[1] || '').trim();
    const stockCode = (block.match(/<stock_code>([\s\S]*?)<\/stock_code>/)?.[1] || '').trim();
    if (/^\d{6}$/.test(stockCode) && corpCode) {
      map.set(stockCode, { corpCode, corpName, stockCode });
    }
  }
  _dartCorpCodeByStockCode = map;
  _dartCorpCodeFetchedAt = now;
  return map;
}

function dartReportCodeForQuarter(date = new Date()) {
  const month = date.getUTCMonth() + 1;
  if (month >= 11) return '11014'; // 3분기
  if (month >= 8) return '11012'; // 반기
  if (month >= 5) return '11013'; // 1분기
  return '11011'; // 사업보고서
}

async function fetchDartContext(ticker, apiKey) {
  if (!apiKey || !/^\d{6}$/.test(String(ticker || ''))) return null;
  try {
    const map = await getDartCorpCodeMap(apiKey);
    const corp = map.get(ticker);
    if (!corp) return { hasData: false, reason: 'DART corp_code 매칭 실패' };

    const now = new Date();
    const end = now.toISOString().slice(0, 10).replace(/-/g, '');
    const beginDate = new Date(now.getTime() - 180 * 24 * 60 * 60 * 1000);
    const begin = beginDate.toISOString().slice(0, 10).replace(/-/g, '');

    const disclosurePromise = axios.get('https://opendart.fss.or.kr/api/list.json', {
      params: {
        crtfc_key: apiKey,
        corp_code: corp.corpCode,
        bgn_de: begin,
        end_de: end,
        page_count: 10,
      },
      timeout: 12000,
    }).catch((e) => ({ error: e }));

    const currentYear = now.getUTCFullYear();
    const reportCandidates = [
      { year: currentYear, code: dartReportCodeForQuarter(now) },
      { year: currentYear - 1, code: '11011' },
    ];
    const financialResults = [];
    for (const candidate of reportCandidates) {
      try {
        const res = await axios.get('https://opendart.fss.or.kr/api/fnlttSinglAcnt.json', {
          params: {
            crtfc_key: apiKey,
            corp_code: corp.corpCode,
            bsns_year: String(candidate.year),
            reprt_code: candidate.code,
          },
          timeout: 12000,
        });
        const list = Array.isArray(res.data?.list) ? res.data.list : [];
        if (list.length) {
          financialResults.push({ year: candidate.year, reportCode: candidate.code, list });
          break;
        }
      } catch (_) {}
    }

    const disclosureRes = await disclosurePromise;
    const disclosures = Array.isArray(disclosureRes.data?.list)
      ? disclosureRes.data.list.slice(0, 10).map((d) => ({
          date: d.rcept_dt,
          title: clampStockAnalysisInput(d.report_nm, 160),
          receiptNo: d.rcept_no,
          submitter: clampStockAnalysisInput(d.flr_nm, 80),
        }))
      : [];
    const reportStory = await fetchDartReportStory(corp, disclosures, apiKey);

    const financial = financialResults[0];
    const financials = financial
      ? Array.from(
          financial.list
            .map((row) => ({ ...row, accountGroup: dartAccountGroup(row.account_nm) }))
            .filter((row) => row.accountGroup)
            .reduce((map, row) => {
              const prev = map.get(row.accountGroup);
              const rowIsConsolidated = String(row.sj_nm || '').includes('연결');
              const prevIsConsolidated = String(prev?.sj_nm || '').includes('연결');
              if (!prev || (rowIsConsolidated && !prevIsConsolidated)) {
                map.set(row.accountGroup, row);
              }
              return map;
            }, new Map())
            .values(),
        ).map((row) => ({
          account: row.accountGroup,
          current: row.thstrm_amount,
          previous: row.frmtrm_amount,
          statement: row.sj_nm,
        }))
      : [];

    return {
      hasData: true,
      corpCode: corp.corpCode,
      corpName: corp.corpName,
      disclosures,
      financials,
      reportStory,
      financialReport: financial ? `${financial.year}/${financial.reportCode}` : null,
      source: 'OpenDART',
    };
  } catch (e) {
    console.warn('[fetchDartContext] failed:', e.response?.data || e.message);
    return { hasData: false, reason: e.message || 'DART 조회 실패' };
  }
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

// KOSPI200 정규 선물 근월물 단축코드: A01 + 연(끝1자리) + 월(2자리)
// (KIS 마스터파일 fo_idx_code_mts.mst 기준. A01=KOSPI200, A06=KOSDAQ150)
// 분기물(3/6/9/12) 중 최종거래일(둘째 목요일) 안 지난 가장 가까운 월물.
// 예: getNightFuturesSymbol('A01') = A01609, getNightFuturesSymbol('A06') = A06609
function getNightFuturesSymbol(prefix = 'A01') {
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

  return `${prefix}${expiryYear % 10}${String(expiryMonth).padStart(2, '0')}`;
}

// KIS 실시간 WebSocket 승인키 (12시간 캐시, 웜 인스턴스에서 재사용)
let _kisApprovalKey = null;
let _kisApprovalExp = 0;
async function getKisApprovalKey(appKey, appSecret) {
  if (_kisApprovalKey && Date.now() < _kisApprovalExp) return _kisApprovalKey;
  const r = await axios.post(
    'https://openapi.koreainvestment.com:9443/oauth2/Approval',
    { grant_type: 'client_credentials', appkey: appKey, secretkey: appSecret }
  );
  _kisApprovalKey = r.data.approval_key;
  _kisApprovalExp = Date.now() + 12 * 60 * 60 * 1000;
  return _kisApprovalKey;
}

// KIS 실시간 WebSocket(H0MFCNT0 KRX야간선물체결)으로 라이브 체결 1건 수신.
// REST(inquire-price)는 야간세션을 추적 못 하고 주간 종가에서 freeze되므로 WS 사용.
// (서버에서는 실시간 푸시 정상 수신 — 2026-06-22 검증)
function fetchNightFuturesQuote(appKey, appSecret, symbol, timeoutMs = 12000) {
  return new Promise((resolve, reject) => {
    const WebSocket = require('ws');
    let settled = false;
    let ws;
    const done = (fn, v) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try { ws.terminate(); } catch (_) {}
      fn(v);
    };
    const timer = setTimeout(() => done(reject, new Error('ws timeout')), timeoutMs);

    getKisApprovalKey(appKey, appSecret).then((approval) => {
      ws = new WebSocket('ws://ops.koreainvestment.com:21000');
      ws.on('open', () => {
        ws.send(JSON.stringify({
          header: { approval_key: approval, custtype: 'P', tr_type: '1', 'content-type': 'utf-8' },
          body: { input: { tr_id: 'H0MFCNT0', tr_key: symbol } },
        }));
      });
      ws.on('message', (raw) => {
        const m = raw.toString();
        if (m[0] === '{') {
          try {
            const j = JSON.parse(m);
            if (j.header?.tr_id === 'PINGPONG') ws.send(m);
          } catch (_) {}
          return;
        }
        const p = m.split('|');
        if (p[1] !== 'H0MFCNT0' || !p[3]) return;
        // 필드: 0 단축코드 1 시각 2 전일대비 3 부호 4 등락률 5 현재가 ... 10 누적거래량
        const f = p[3].split('^');
        const price = parseFloat(f[5]);
        if (!price || price <= 0) return;
        const rawChange = parseFloat(f[2]) || 0;
        const rawRate = parseFloat(f[4]) || 0;
        const sign = f[3];
        const dir = sign === '4' || sign === '5' ? -1 : 1; // 4:하락 5:하한
        done(resolve, {
          price,
          change: rawChange === 0 ? 0 : Math.abs(rawChange) * dir,
          changeRate: rawRate === 0 ? 0 : Math.abs(rawRate) * dir,
          volume: parseInt(f[10]) || 0,
        });
      });
      ws.on('error', (e) => done(reject, e));
    }).catch((e) => done(reject, e));
  });
}

// 야간선물 시세 1건을 받아 지정 컬렉션에 기록 (매분 호출)
async function recordNightFuturesTo(db, collection, kst, appKey, appSecret, symbol) {
  const q = await fetchNightFuturesQuote(appKey, appSecret, symbol);
  if (!q) return;

  // 매분 기록 (한산해서 시세가 안 움직여도 연속된 차트가 그려지도록).
  const tsKey = kst.toISOString().slice(0, 16).replace('T', '_');
  await db.collection(collection).doc(tsKey).set({
    price: q.price,
    change: q.change,
    changeRate: q.changeRate,
    volume: q.volume,
    timestamp: new Date(), // 실제 UTC 시각 (기기 시간대 변환 정확)
    symbol,
  });

  // 오래된 데이터 정리 (최대 2000개 유지)
  const old = await db.collection(collection)
    .orderBy('timestamp', 'desc').offset(2000).limit(100).get();
  if (!old.empty) {
    const batch = db.batch();
    old.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
  }
}

// ── 야간선물 가격 1분마다 Firestore에 기록 (KOSPI200 + KOSDAQ150) ────────────
exports.recordNightFuturesPrice = onSchedule(
  // 야간세션(18:00~04:59 KST)에만 매분 실행 — 주간 시간대 불필요 호출 제거.
  { schedule: '* 18-23,0-4 * * *', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 40 },
  async () => {
    const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
    const kstHour = kst.getUTCHours();
    if (kstHour >= 5 && kstHour < 18) return; // 안전장치: 야간세션(18:00~05:00 KST)만 기록

    const config = await getKisConfig();
    if (!config) return;
    const db = getFirestore();

    const targets = [
      { collection: 'night_futures_prices', symbol: getNightFuturesSymbol('A01') }, // KOSPI200
      { collection: 'night_futures_prices_kosdaq', symbol: getNightFuturesSymbol('A06') }, // KOSDAQ150
    ];
    // WS 세션은 appkey당 1개라 순차 처리. 하나 실패해도 다른 하나는 진행.
    for (const t of targets) {
      try {
        await recordNightFuturesTo(db, t.collection, kst, config.appKey, config.appSecret, t.symbol);
      } catch (e) {
        console.warn(`[recordNightFuturesPrice:${t.collection}]`, e.response?.data || e.message);
      }
    }
  }
);

// getKospiNightFutures: Firestore에 쌓인 최신 야간선물 데이터 1건 반환
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

// 서버 시각(ms) 반환 — 기기 시계가 틀려도 마켓 시계를 실제 KST로 맞추기 위함
exports.getServerTime = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 5 },
  async () => ({ ms: Date.now() }),
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

function isPlainListedStock(item) {
  const endType = String(item.stockEndType || '').toLowerCase();
  const name = String(item.stockName || '').trim().toUpperCase();
  if (endType && endType !== 'stock') return false;
  if (!name) return false;
  return !/^(KODEX|TIGER|ACE|SOL|KBSTAR|ARIRANG|HANARO|KOSEF|TIMEFOLIO|PLUS|RISE|히어로즈|마이티|TREX|FOCUS|BNK|UNICORN|WOORI|파워|SMART|QV|TRUE)\s?/.test(name) &&
    !name.includes(' ETF') &&
    !name.includes(' ETN') &&
    !name.includes('인버스') &&
    !name.includes('레버리지');
}

async function fetchMarketStockList(market) {
  const pageSize = 100;
  const first = await axios.get(
    `https://m.stock.naver.com/api/stocks/marketValue/${market}?page=1&pageSize=${pageSize}`,
    { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }
  );
  const totalCount = Number(first.data?.totalCount || first.data?.stocks?.length || 0);
  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize));
  const pages = [first.data];
  if (totalPages > 1) {
    const rest = await Promise.all(
      Array.from({ length: totalPages - 1 }, (_, i) =>
        axios.get(
          `https://m.stock.naver.com/api/stocks/marketValue/${market}?page=${i + 2}&pageSize=${pageSize}`,
          { headers: NAVER_MOBILE_HEADERS, timeout: 8000 }
        ).then(res => res.data)
      )
    );
    pages.push(...rest);
  }
  return pages.flatMap(page => page?.stocks || []);
}

function countBreadthFromStocks(stocks) {
  return stocks.filter(isPlainListedStock).reduce((acc, item) => {
    const rate = Number(item.fluctuationsRatio || 0);
    const code = String(item.compareToPreviousPrice?.code || '');
    const name = String(item.compareToPreviousPrice?.name || '');
    if (rate > 0 || code === '2' || name === 'RISING') acc.up += 1;
    else if (rate < 0 || code === '5' || name === 'FALLING') acc.down += 1;
    else acc.flat += 1;
    return acc;
  }, { up: 0, down: 0, flat: 0, excludes: 'ETF/ETN 제외' });
}

/** 네이버 금융 모바일 API에서 코스피/코스닥 상승·하락·보합 종목수(ETF/ETN 제외) */
async function fetchMarketBreadth() {
  try {
    const [kospiStocks, kosdaqStocks] = await Promise.all([
      fetchMarketStockList('KOSPI'),
      fetchMarketStockList('KOSDAQ'),
    ]);
    return {
      kospi: countBreadthFromStocks(kospiStocks),
      kosdaq: countBreadthFromStocks(kosdaqStocks),
    };
  } catch (e) {
    console.warn('[AiBrief] ETF 제외 시장 폭 데이터 실패:', e.message);
    return null;
  }
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

// 실시간 원/달러 환율 (Yahoo KRW=X) — AI 시황이 검증된 환율 숫자를 쓰도록
async function fetchUsdKrw() {
  try {
    const res = await axios.get(
      'https://query1.finance.yahoo.com/v8/finance/chart/KRW=X?range=5d&interval=1d',
      {
        headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' },
        timeout: 8000,
      }
    );
    const result = res.data?.chart?.result?.[0];
    const meta = result?.meta || {};
    const closes = (result?.indicators?.quote?.[0]?.close || []).filter(Number.isFinite);
    const price = Number.isFinite(meta.regularMarketPrice)
      ? meta.regularMarketPrice
      : closes.at(-1);
    if (!Number.isFinite(price) || price <= 0) return null;
    const prevClose = Number.isFinite(meta.chartPreviousClose)
      ? meta.chartPreviousClose
      : (closes.length >= 2 ? closes.at(-2) : null);
    const change = Number.isFinite(prevClose) ? price - prevClose : null;
    const changeRate = Number.isFinite(prevClose) && prevClose
      ? (change / prevClose) * 100
      : null;
    return { price, change, changeRate };
  } catch (_) {
    return null;
  }
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

function buildAiBriefPrompt(marketData, sectorData, breadthData, investorFlow, news, usMarketData, fxData, slot) {
  const { kospi, kosdaq } = marketData;
  const slotMeta = getAiBriefSlotMeta(slot);

  let investorContext = '';
  if (investorFlow) {
    const fi = investorFlow;
    const fKospi = fi.kospi?.foreignNet != null ? (fi.kospi.foreignNet / 1e8).toFixed(0) + '억원' : null;
    const iKospi = fi.kospi?.institutionNet != null ? (fi.kospi.institutionNet / 1e8).toFixed(0) + '억원' : null;
    const rKospi = fi.kospi?.retailNet != null ? (fi.kospi.retailNet / 1e8).toFixed(0) + '억원' : null;
    const fKosdaq = fi.kosdaq?.foreignNet != null ? (fi.kosdaq.foreignNet / 1e8).toFixed(0) + '억원' : null;
    const iKosdaq = fi.kosdaq?.institutionNet != null ? (fi.kosdaq.institutionNet / 1e8).toFixed(0) + '억원' : null;
    if (fKospi || iKospi || fKosdaq || iKosdaq || rKospi) {
      investorContext = '\n\n[매매동향]';
      if (fKospi) investorContext += `\n- KOSPI 외국인 순매수: ${fKospi}`;
      if (iKospi) investorContext += `\n- KOSPI 기관 순매수: ${iKospi}`;
      if (rKospi) investorContext += `\n- KOSPI 개인 순매수: ${rKospi}`;
      if (fKosdaq) investorContext += `\n- KOSDAQ 외국인 순매수: ${fKosdaq}`;
      if (iKosdaq) investorContext += `\n- KOSDAQ 기관 순매수: ${iKosdaq}`;
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
  if (breadthData && slot !== '09') {
    const b = breadthData;
    if (b.kospi?.up || b.kospi?.down) {
      breadthContext += `\n\n[시장 폭: ETF/ETN 제외]\n- KOSPI 상승:${b.kospi.up}개 / 하락:${b.kospi.down}개 / 보합:${b.kospi.flat}개`;
    }
    if (b.kosdaq?.up || b.kosdaq?.down) {
      breadthContext += `\n- KOSDAQ 상승:${b.kosdaq.up}개 / 하락:${b.kosdaq.down}개 / 보합:${b.kosdaq.flat}개`;
    }
  }

  let newsContext = '';
  if (news && news.length > 0) {
    newsContext = '\n\n[최신 뉴스 헤드라인]\n' + news.map((n, i) => `${i + 1}. ${n.title}`).join('\n');
  }

  let fxContext = '';
  if (fxData?.price) {
    const rateStr = fxData.changeRate == null
      ? ''
      : ` (${fxData.changeRate >= 0 ? '▲' : '▼'}${Math.abs(fxData.changeRate).toFixed(2)}%, 전일대비 ${fxData.change >= 0 ? '+' : ''}${fxData.change.toFixed(2)}원)`;
    fxContext = `\n\n[환율 — 실시간 검증값]\n- 원/달러: ${fxData.price.toFixed(2)}원${rateStr}\n- 환율을 언급할 때는 반드시 이 숫자만 사용하고, 뉴스 헤드라인에 다른 환율 숫자가 있어도 무시하세요.`;
  }

  let usContext = '';
  if (usMarketData?.indices?.length) {
    const fmt = usMarketData.indices
      .map(i => `${i.name}: ${i.changeRate == null ? i.close.toFixed(2) : `${i.changeRate >= 0 ? '+' : ''}${i.changeRate.toFixed(2)}%`}`)
      .join(', ');
    const staleNote = usMarketData.isHolidayOrStale ? ' (최근 거래일 데이터가 오래되어 휴장 가능성이 있습니다)' : '';
    usContext = `\n\n[전일 미국장]\n- 기준일: ${usMarketData.latestDate || '확인 불가'}${staleNote}\n- ${fmt}`;
  }

  return `지금은 한국 주식시장 ${slotMeta.label}입니다. 아래 데이터와 뉴스 헤드라인을 바탕으로, 투자자가 읽었을 때 "오늘 장이 왜 이렇게 움직였는지" 머릿속에 그림이 그려질 만큼 자세하고 구체적인 시황 브리핑을 작성하세요.

[시간대별 작성 관점]
${slotMeta.focus}

[지수]
- 코스피: ${kospi.price.toLocaleString('ko-KR')}pt (${kospi.isUp ? '▲' : '▼'}${Math.abs(kospi.changeRate).toFixed(2)}%, ${kospi.change >= 0 ? '+' : ''}${kospi.change.toFixed(2)}pt)
- 코스닥: ${kosdaq.price.toLocaleString('ko-KR')}pt (${kosdaq.isUp ? '▲' : '▼'}${Math.abs(kosdaq.changeRate).toFixed(2)}%, ${kosdaq.change >= 0 ? '+' : ''}${kosdaq.change.toFixed(2)}pt)${fxContext}${usContext}${sectorContext}${breadthContext}${investorContext}${newsContext}

[출력 형식 — 아래 JSON 객체 하나만 출력. 코드펜스(\`\`\`)나 설명 문구 없이 순수 JSON만]
{
  "summary": "오늘 장 분위기를 한 문장으로 압축 (40자 이내, ~습니다 체)",
  "news": [
    { "headline": "핵심 뉴스·이슈 제목 (간결하게, 20자 내외)", "detail": "왜 중요한지와 시장 영향 1~2문장" }
  ],
  "index": "지수 시황: 코스피·코스닥의 종가/현재가와 등락률·등락폭 숫자를 인용하며 시간대 관점에 맞춰 상승·하락 배경을 3~4문장으로. 09시는 전일 미국장(S&P500·NASDAQ·Dow) 연결, 12시는 오전 흐름, 15:30은 마감 결과와 장중 변동성.",
  "sector": "업종별 분석: [업종 등락] 데이터의 상승 업종 2개·하락 업종 2개를 등락률 숫자와 함께 짚고 강약 이유를 뉴스/매크로와 엮어 3~4문장. 데이터에 있는 업종명만 사용.",
  "flow": "수급·시장 폭: [매매동향]의 외국인·기관(가능하면 개인) 순매수 금액(억원)과, 있으면 [시장 폭]의 상승/하락 종목 수를 인용해 2~3문장. 09시이고 데이터가 없으면 환율·금리·전일 미국장 톤 등 거시 배경으로 대체.",
  "checkpoint": "체크포인트: 시간대에 맞춘 마무리와 다음에 봐야 할 포인트 2~3문장."
}

[news 작성 규칙]
- [최신 뉴스 헤드라인]에서 가장 중요한 3~4개를 골라 headline+detail로 정리하세요.
- 헤드라인이 제공되지 않았으면 news는 빈 배열 []로 두세요. 뉴스를 지어내지 마세요.

[공통 규칙]
- 등락률·등락폭·수급 금액·종목 수 등 제공된 숫자는 반드시 본문에 등장시킬 것 (인용 부호 없이 자연스럽게)
- 반드시 높임말(~습니다/~네요/~보입니다) 사용, 각 문장은 마침표로 끝낼 것
- 사실 기반 서술만, 투자 권유·매수/매도 추천·미래 단정 예측 금지
- 제공된 데이터에 없는 종목명·업종명·지표는 만들어내지 말 것
- "투자심리에 우호적/부정적", "작용했습니다"처럼 단정적 표현 대신 "거론됐습니다", "눈에 띄었습니다", "관전 포인트로 꼽힙니다"처럼 부드럽게
- "오늘은", "현재" 같은 막연한 도입부 금지
- 각 필드 값은 본문만 작성하고, "업종별 분석:", "지수 시황:", "수급:", "체크포인트:" 같은 카테고리명·소제목을 값 앞에 절대 붙이지 말 것

위 JSON 객체 하나만 출력하세요:`;
}

async function generateBriefWithOpenAi(apiKey, marketData, sectorData, breadthData, investorFlow, news, usMarketData, fxData, slot) {
  const prompt = buildAiBriefPrompt(marketData, sectorData, breadthData, investorFlow, news, usMarketData, fxData, slot);

  // 시크릿 값에 BOM/제로폭 문자가 섞여 있으면 헤더 변환이 깨지므로 정제
  const cleanKey = String(apiKey).replace(/[﻿​\r\n\t]/g, '').trim();

  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${cleanKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-5-mini',
      input: prompt,
      max_output_tokens: 2800,
      reasoning: { effort: 'low' },
      text: { verbosity: 'medium' },
    }),
  });

  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const detail = body?.error?.message || response.statusText || 'OpenAI API request failed';
    throw new Error(`[AiBrief] OpenAI 호출 실패: ${detail}`);
  }

  const text = (body?.output_text || (body?.output || [])
    .flatMap((item) => item?.content || [])
    .map((part) => part?.text || '')
    .filter(Boolean)
    .join('\n'))
    .trim();

  if (!text) throw new Error('[AiBrief] OpenAI 응답이 비어 있습니다.');

  // JSON 카테고리 파싱 (실패 시 전체를 지수시황 텍스트로 폴백)
  let sections;
  try {
    const obj = extractJsonObject(text);
    const news = Array.isArray(obj.news)
      ? obj.news
          .map((n) => ({
            headline: String(n?.headline || '').trim(),
            detail: String(n?.detail || '').trim(),
          }))
          .filter((n) => n.headline)
          .slice(0, 5)
      : [];
    sections = {
      summary: stripLeadingLabel(obj.summary),
      news,
      index: stripLeadingLabel(obj.index),
      sector: stripLeadingLabel(obj.sector),
      flow: stripLeadingLabel(obj.flow),
      checkpoint: stripLeadingLabel(obj.checkpoint),
    };
  } catch (e) {
    console.warn('[AiBrief] JSON 파싱 실패, 텍스트 폴백:', e.message);
    sections = { summary: '', news: [], index: text, sector: '', flow: '', checkpoint: '' };
  }

  return { sections, brief: sectionsToBrief(sections) };
}

// 각 섹션 본문 앞에 모델이 붙인 카테고리 소제목("업종별 분석:" 등) 제거
function stripLeadingLabel(value) {
  let t = String(value || '').trim();
  const labels = [
    '주요뉴스', '지수 시황', '지수시황', '업종별 분석', '업종 분석', '업종별분석',
    '수급·시장 폭', '수급 시장 폭', '수급·시장폭', '수급', '시장 폭', '체크포인트', '요약',
  ];
  for (const l of labels) {
    const re = new RegExp('^' + l.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*[:：]\\s*');
    if (re.test(t)) { t = t.replace(re, ''); break; }
  }
  return t.trim();
}

// 카테고리 → 단일 텍스트 (하위호환 brief 필드용)
function sectionsToBrief(s) {
  const parts = [];
  if (s.summary) parts.push(s.summary);
  if (Array.isArray(s.news) && s.news.length) {
    parts.push('[주요뉴스]\n' + s.news.map((n) => `· ${n.headline}: ${n.detail}`).join('\n'));
  }
  if (s.index) parts.push('[지수 시황]\n' + s.index);
  if (s.sector) parts.push('[업종별 분석]\n' + s.sector);
  if (s.flow) parts.push('[수급]\n' + s.flow);
  if (s.checkpoint) parts.push('[체크포인트]\n' + s.checkpoint);
  return parts.join('\n\n');
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
  const [sectorData, breadthData, investorFlow, news, usMarketData, fxData] = await Promise.all([
    fetchSectorData(),
    fetchMarketBreadth(),
    fetchInvestorFlowSummary(db),
    fetchMarketNews(),
    fetchUsMarketData(),
    fetchUsdKrw(),
  ]);

  const marketClosed = getMarketClosedInfo(marketData);
  if (marketClosed) return saveMarketClosedBrief(marketClosed, marketData);

  const { sections, brief } = await generateBriefWithOpenAi(apiKey, marketData, sectorData, breadthData, investorFlow, news, usMarketData, fxData, slot);

  const slotLabel = getAiBriefSlotMeta(slot).timeLabel;
  const payload = {
    brief, sections, slot, slotLabel, date: dateKey,
    kospi: marketData.kospi, kosdaq: marketData.kosdaq,
    sectors: sectorData ?? null,
    fx: fxData ?? null,
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
  { schedule: '0 9 * * 1-5', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 180, secrets: [OPENAI_API_KEY] },
  async () => { await runAiBriefGeneration(OPENAI_API_KEY.value(), '09'); }
);

// ── AI 시황 스케줄 (평일 12:00 KST) ─────────────────────────────────────────
exports.generateAiBriefMidday = onSchedule(
  { schedule: '0 12 * * 1-5', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 180, secrets: [OPENAI_API_KEY] },
  async () => { await runAiBriefGeneration(OPENAI_API_KEY.value(), '12'); }
);

// ── AI 시황 스케줄 (평일 15:30 KST) ─────────────────────────────────────────
exports.generateAiBriefAfternoon = onSchedule(
  { schedule: '30 15 * * 1-5', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 180, secrets: [OPENAI_API_KEY] },
  async () => { await runAiBriefGeneration(OPENAI_API_KEY.value(), '15'); }
);

// ── AI 시황 수동 트리거 (테스트용, 관리자만) ─────────────────────────────────
exports.generateAiBriefNow = onRequest(
  { region: 'asia-northeast3', timeoutSeconds: 180, secrets: [OPENAI_API_KEY] },
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

      const brief = await runAiBriefGeneration(OPENAI_API_KEY.value(), slot);
      res.json({ ok: true, brief, slot });
    } catch (e) {
      console.error('[generateAiBriefNow]', e);
      res.status(500).json({ error: e.message });
    }
  }
);

function clampStockAnalysisInput(value, maxLength = 5000) {
  return String(value ?? '').slice(0, maxLength);
}

function extractJsonObject(text) {
  const raw = String(text || '').trim();
  const fenced = raw.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fenced?.[1]) {
    try {
      return JSON.parse(fenced[1].trim());
    } catch (_) {}
  }
  try {
    return JSON.parse(raw);
  } catch (_) {
    const match = raw.match(/\{[\s\S]*\}/);
    if (!match) throw new Error('AI 응답에서 JSON을 찾지 못했습니다.');
    return JSON.parse(match[0]);
  }
}

function fallbackStockAnalysisPayload(text) {
  const loose = parseLooseStockAnalysisText(text);
  if (loose) return normalizeStockAnalysisPayload(loose);
  return normalizeStockAnalysisPayload({
    summary: 'AI 응답 형식이 예상과 달라 이번 분석을 항목별로 정리하지 못했습니다. 다시 분석을 실행하면 정상 형식으로 생성될 수 있습니다.',
    score: null,
    scoreLabel: '형식 보정 필요',
    theme: '',
    sector: '',
    todayReason: '',
    fundamentals: '',
    technical: '',
    news: '',
    momentum: '',
    risks: ['AI 응답이 구조화된 JSON 형식으로 오지 않아 세부 항목을 분리하지 못했습니다.'],
    sections: [],
  });
}

function parseLooseStockAnalysisText(text) {
  const raw = String(text || '').trim();
  if (!raw) return null;
  const keys = [
    'summary',
    'scoreLabel',
    'theme',
    'sector',
    'todayReason',
    'fundamentals',
    'technical',
    'news',
    'momentum',
  ];
  const out = {};
  const keyPattern = new RegExp(`"?(${keys.join('|')}|score|risks|sections)"?\\s*:`, 'gi');
  const matches = Array.from(raw.matchAll(keyPattern))
    .map((m) => ({ key: m[1], start: m.index ?? 0, valueStart: (m.index ?? 0) + m[0].length }))
    .sort((a, b) => a.start - b.start);

  const firstUsefulKey = matches.find((m) => keys.includes(m.key));
  if (firstUsefulKey && firstUsefulKey.start > 0 && !matches.some((m) => m.key === 'summary')) {
    const prefix = cleanLooseValue(raw.slice(0, firstUsefulKey.start));
    if (prefix) out.summary = prefix;
  }

  for (let i = 0; i < matches.length; i += 1) {
    const current = matches[i];
    const end = matches[i + 1]?.start ?? raw.length;
    if (current.key === 'score') {
      const scoreMatch = raw.slice(current.valueStart, end).match(/[0-9]{1,3}/);
      if (scoreMatch) out.score = Number(scoreMatch[0]);
      continue;
    }
    if (!keys.includes(current.key)) continue;
    const value = cleanLooseValue(raw.slice(current.valueStart, end));
    if (value) out[current.key] = value;
  }
  const scoreMatch = raw.match(/"?score"?\s*:\s*([0-9]{1,3})/i);
  if (scoreMatch) out.score = Number(scoreMatch[1]);
  return Object.keys(out).length > 0 ? out : null;
}

function cleanLooseValue(value) {
  return String(value || '')
    .replace(/^[\s"'`{:,]+|[\s"'`,}]+$/g, '')
    .replace(/\\n/g, '\n')
    .replace(/\\"/g, '"')
    .trim();
}

function normalizeStockAnalysisPayload(parsed) {
  const sections = Array.isArray(parsed.sections) ? parsed.sections : [];
  const catalysts = Array.isArray(parsed.catalysts) ? parsed.catalysts : [];
  const risksDetailed = Array.isArray(parsed.risksDetailed) ? parsed.risksDetailed : [];
  const valuation = parsed.valuation && typeof parsed.valuation === 'object' ? parsed.valuation : null;
  const technicalDetail = parsed.technicalDetail && typeof parsed.technicalDetail === 'object' ? parsed.technicalDetail : null;
  const scenarios = parsed.scenarios && typeof parsed.scenarios === 'object' ? parsed.scenarios : null;
  const timing = parsed.timing && typeof parsed.timing === 'object' ? parsed.timing : null;
  return {
    companyOverview: clampStockAnalysisInput(parsed.companyOverview, 600),
    summary: clampStockAnalysisInput(parsed.summary, 1200),
    subScores: parsed.subScores && typeof parsed.subScores === 'object'
      ? {
          priceTrend: clampSubScore(parsed.subScores.priceTrend),
          newsImpact: clampSubScore(parsed.subScores.newsImpact),
          fundamentals: clampSubScore(parsed.subScores.fundamentals),
          momentumFlow: clampSubScore(parsed.subScores.momentumFlow),
          riskLevel: clampSubScore(parsed.subScores.riskLevel),
        }
      : null,
    score: Number.isFinite(Number(parsed.score)) ? Math.max(0, Math.min(100, Number(parsed.score))) : null,
    scoreLabel: clampStockAnalysisInput(parsed.scoreLabel, 80),
    theme: clampStockAnalysisInput(parsed.theme, 600),
    sector: clampStockAnalysisInput(parsed.sector, 300),
    todayReason: clampStockAnalysisInput(parsed.todayReason, 1000),
    fundamentals: clampStockAnalysisInput(parsed.fundamentals, 1000),
    technical: clampStockAnalysisInput(parsed.technical, 1200),
    news: clampStockAnalysisInput(parsed.news, 1200),
    momentum: clampStockAnalysisInput(parsed.momentum, 1000),
    peerPerAverage: clampStockAnalysisInput(parsed.peerPerAverage, 160),
    themePeers: Array.isArray(parsed.themePeers)
      ? parsed.themePeers.slice(0, 8).map((v) => clampStockAnalysisInput(v, 80)).filter(Boolean)
      : [],
    risks: Array.isArray(parsed.risks)
      ? parsed.risks.slice(0, 5).map((v) => clampStockAnalysisInput(v, 240)).filter(Boolean)
      : [],
    sections: sections.slice(0, 8).map((s) => ({
      title: clampStockAnalysisInput(s?.title, 80),
      body: clampStockAnalysisInput(s?.body, 900),
    })).filter((s) => s.title && s.body),
    catalysts: catalysts.slice(0, 6).map((c) => ({
      title: clampStockAnalysisInput(c?.title, 160),
      kind: clampStockAnalysisInput(c?.kind, 20),
      impact: clampStockAnalysisInput(c?.impact, 20),
      timeline: clampStockAnalysisInput(c?.timeline, 20),
      confidence: clampStockAnalysisInput(c?.confidence, 20),
      detail: clampStockAnalysisInput(c?.detail, 600),
    })).filter((c) => c.title && c.detail),
    valuation: valuation
      ? {
          perVerdict: clampStockAnalysisInput(valuation.perVerdict, 20),
          pbrVerdict: clampStockAnalysisInput(valuation.pbrVerdict, 20),
          forwardPer: clampStockAnalysisInput(valuation.forwardPer, 80),
          sectorAveragePer: clampStockAnalysisInput(valuation.sectorAveragePer, 80),
          peerComparison: Array.isArray(valuation.peerComparison)
            ? valuation.peerComparison.slice(0, 5).map((p) => ({
                name: clampStockAnalysisInput(p?.name, 60),
                per: clampStockAnalysisInput(p?.per, 30),
                pbr: clampStockAnalysisInput(p?.pbr, 30),
              })).filter((p) => p.name)
            : [],
          reasoning: clampStockAnalysisInput(valuation.reasoning, 1200),
        }
      : null,
    technicalDetail: technicalDetail
      ? {
          maPosition: clampStockAnalysisInput(technicalDetail.maPosition, 200),
          rsiVerdict: clampStockAnalysisInput(technicalDetail.rsiVerdict, 200),
          bollingerVerdict: clampStockAnalysisInput(technicalDetail.bollingerVerdict, 200),
          support: clampStockAnalysisInput(technicalDetail.support, 120),
          resistance: clampStockAnalysisInput(technicalDetail.resistance, 120),
          pattern: clampStockAnalysisInput(technicalDetail.pattern, 200),
          reasoning: clampStockAnalysisInput(technicalDetail.reasoning, 1000),
        }
      : null,
    scenarios: scenarios
      ? ['bull', 'base', 'bear'].reduce((acc, key) => {
          const s = scenarios[key];
          if (s && typeof s === 'object') {
            acc[key] = {
              trigger: clampStockAnalysisInput(s.trigger, 200),
              priceTarget: clampStockAnalysisInput(s.priceTarget, 80),
              probability: Number.isFinite(Number(s.probability))
                ? Math.max(0, Math.min(1, Number(s.probability)))
                : null,
              narrative: clampStockAnalysisInput(s.narrative, 600),
            };
          }
          return acc;
        }, {})
      : null,
    risksDetailed: risksDetailed.slice(0, 6).map((r) => ({
      category: clampStockAnalysisInput(r?.category, 20),
      severity: clampStockAnalysisInput(r?.severity, 20),
      probability: clampStockAnalysisInput(r?.probability, 20),
      description: clampStockAnalysisInput(r?.description, 400),
      mitigant: clampStockAnalysisInput(r?.mitigant, 400),
    })).filter((r) => r.description),
    timing: timing
      ? {
          shortTerm: clampStockAnalysisInput(timing.shortTerm, 500),
          midTerm: clampStockAnalysisInput(timing.midTerm, 500),
          action: clampStockAnalysisInput(timing.action, 30),
          actionReason: clampStockAnalysisInput(timing.actionReason, 500),
        }
      : null,
    generatedAt: new Date().toISOString(),
  };
}

function attachStockAnalysisSources(payload, sources) {
  return {
    ...payload,
    sourceNews: sources?.sourceNews || [],
    sourceDisclosures: sources?.sourceDisclosures || [],
    sourceFinancials: sources?.sourceFinancials || [],
    sourceMarketCap: sources?.sourceMarketCap ?? null,
    sourceEps: sources?.sourceEps ?? null,
    sourceInvestorFlow: sources?.sourceInvestorFlow || null,
    sourceDailyInvestorFlow: sources?.sourceDailyInvestorFlow || null,
    sourceReports: sources?.sourceReports || [],
    sourceEpsTimeline: sources?.sourceEpsTimeline || [],
  };
}

/**
 * 결정론적 valuation sub-score (0~100).
 * 입력 데이터로 신호 1개 이상 잡히면 결과 반환, 아니면 null.
 * - signalCount: 잡힌 신호 수 (블렌딩 가중치 결정용)
 * - signals: 디버그/추후 표시용 신호 목록
 */
function computeValuationDeterministicScore({
  trailingPer,
  forwardPer,
  sectorPer,
  epsTimeline,
  brokerTargets,
  currentPrice,
  dartFinancials,
}) {
  const signals = [];
  let signalCount = 0;
  let score = 50;
  // "실적 회복/둔화"를 다른 각도에서 본 신호들 — double counting 방지 위해
  // 합산해서 별도 cap 적용 후 score에 더한다.
  // 포함: (1) forward PER ratio (회복/둔화), (3) EPS 시계열, (6) 영업이익 YoY 전환
  let recoveryDelta = 0;
  const addRecovery = (delta, label) => {
    recoveryDelta += delta;
    signals.push(label);
  };

  // (1) forward PER vs trailing PER — 실적 회복/둔화 시그널 (recovery group)
  if (
    Number.isFinite(forwardPer) && forwardPer > 0 &&
    Number.isFinite(trailingPer) && trailingPer > 0
  ) {
    const ratio = forwardPer / trailingPer;
    if (ratio < 0.5) {
      addRecovery(22, 'forward PER이 trailing PER의 50% 미만 — 강한 실적 회복');
    } else if (ratio < 0.7) {
      addRecovery(14, 'forward PER이 trailing PER의 70% 미만 — 실적 개선');
    } else if (ratio < 0.85) {
      addRecovery(6, 'forward PER 소폭 개선');
    } else if (ratio > 1.4) {
      addRecovery(-16, 'forward PER이 trailing PER 1.4배 초과 — 실적 둔화');
    } else if (ratio > 1.15) {
      addRecovery(-8, 'forward PER이 trailing PER을 상회 — 둔화 우려');
    }
    signalCount++;
  }

  // (2) forward PER vs 업종평균 PER — 할인/프리미엄
  if (
    Number.isFinite(forwardPer) && forwardPer > 0 &&
    Number.isFinite(sectorPer) && sectorPer > 0
  ) {
    const discount = (sectorPer - forwardPer) / sectorPer;
    if (discount > 0.35) {
      score += 10;
      signals.push('forward PER이 업종평균 대비 35%+ 할인');
    } else if (discount > 0.15) {
      score += 5;
      signals.push('forward PER이 업종평균 대비 할인');
    } else if (discount < -0.35) {
      score -= 10;
      signals.push('forward PER이 업종평균 대비 35%+ 프리미엄');
    } else if (discount < -0.15) {
      score -= 5;
      signals.push('forward PER이 업종평균 대비 프리미엄');
    }
    signalCount++;
  }

  // (3) EPS 시계열 추세 — 가장 오래된 vs 가장 최신 추정 (recovery group)
  if (Array.isArray(epsTimeline) && epsTimeline.length >= 2) {
    const valid = epsTimeline.filter((r) => Number.isFinite(r?.eps));
    if (valid.length >= 2) {
      const first = valid[0].eps;
      const last = valid[valid.length - 1].eps;
      if (first > 0 && last > 0) {
        const totalGrowth = (last - first) / first;
        if (totalGrowth > 0.6) {
          addRecovery(10, 'EPS 시계열 60%+ 누적 증가');
        } else if (totalGrowth > 0.25) {
          addRecovery(5, 'EPS 시계열 25%+ 누적 증가');
        } else if (totalGrowth < -0.3) {
          addRecovery(-10, 'EPS 시계열 30%+ 누적 감소');
        } else if (totalGrowth < -0.1) {
          addRecovery(-5, 'EPS 시계열 감소 추세');
        }
        signalCount++;
      } else if (first < 0 && last > 0) {
        addRecovery(18, 'EPS 적자→흑자 전환');
        signalCount++;
      } else if (first > 0 && last < 0) {
        addRecovery(-18, 'EPS 흑자→적자 전환');
        signalCount++;
      }
    }
  }

  // (4) 증권사 평균 목표가 vs 현재가
  // 한국 시장 baseline이 +20% 정도라 그 위로 strict threshold.
  // broker 최소 2개 이상일 때만 신뢰.
  if (
    Array.isArray(brokerTargets) &&
    Number.isFinite(currentPrice) && currentPrice > 0
  ) {
    const validTargets = brokerTargets.filter((t) => Number.isFinite(t) && t > 0);
    if (validTargets.length >= 2) {
      const avgTarget = validTargets.reduce((a, b) => a + b, 0) / validTargets.length;
      const upside = (avgTarget - currentPrice) / currentPrice;
      if (upside > 0.40) {
        score += 6;
        signals.push('증권사 평균 목표가 +40% 이상 상회');
      } else if (upside > 0.25) {
        score += 3;
        signals.push('증권사 평균 목표가 baseline 위 상회');
      } else if (upside < -0.05) {
        score -= 8;
        signals.push('증권사 평균 목표가가 현재가 아래 — 강한 부정');
      } else if (upside < 0.05) {
        score -= 3;
        signals.push('증권사 평균 목표가가 현재가 근처 — 상승여력 제한');
      }
      signalCount++;
    }
  }

  // (5) DART 영업이익 YoY — current vs previous (전년 동기) (recovery group)
  if (Array.isArray(dartFinancials) && dartFinancials.length) {
    const opRow = dartFinancials.find((f) => f?.account === '영업이익');
    const cur = parseDartAmount(opRow?.current);
    const prev = parseDartAmount(opRow?.previous);
    if (Number.isFinite(cur) && Number.isFinite(prev)) {
      if (prev < 0 && cur > 0) {
        addRecovery(10, '영업이익 적자→흑자 전환 (YoY)');
        signalCount++;
      } else if (prev > 0 && cur < 0) {
        addRecovery(-10, '영업이익 흑자→적자 전환 (YoY)');
        signalCount++;
      } else if (prev > 0 && cur > 0) {
        const yoy = (cur - prev) / prev;
        if (yoy > 0.30) {
          addRecovery(5, '영업이익 YoY +30% 이상');
          signalCount++;
        } else if (yoy > 0.10) {
          addRecovery(2, '영업이익 YoY +10% 이상');
          signalCount++;
        } else if (yoy < -0.30) {
          addRecovery(-6, '영업이익 YoY -30% 이하');
          signalCount++;
        } else if (yoy < -0.10) {
          addRecovery(-3, '영업이익 YoY -10% 이하');
          signalCount++;
        }
      } else if (prev < 0 && cur < 0) {
        // 적자 → 적자: 적자폭 축소면 가산, 확대면 감점.
        const reduction = (Math.abs(prev) - Math.abs(cur)) / Math.abs(prev);
        if (reduction > 0.30) {
          addRecovery(3, '영업적자 30%+ 축소');
          signalCount++;
        } else if (reduction < -0.30) {
          addRecovery(-5, '영업적자 30%+ 확대');
          signalCount++;
        }
      }
    }
  }

  if (signalCount === 0) return null;

  // Recovery group cap — 같은 회복/둔화 추세가 3축에서 동시에 잡혀도
  // 합쳐서 ±25점 이내로 제한해 double counting 완화.
  const cappedRecovery = Math.max(-25, Math.min(25, recoveryDelta));
  score += cappedRecovery;
  if (recoveryDelta !== cappedRecovery) {
    signals.push(`(회복 신호 합산 ${recoveryDelta > 0 ? '+' : ''}${recoveryDelta} → cap ${cappedRecovery > 0 ? '+' : ''}${cappedRecovery})`);
  }

  score = Math.max(0, Math.min(100, score));
  return { score, signals, signalCount };
}

/**
 * DART 보고서 금액 문자열을 숫자로. 한국 단위(콤마, 음수 괄호) 처리.
 * 예: "1,234,567" → 1234567
 *     "(1,234)" → -1234
 *     "-1,234" → -1234
 */
function parseDartAmount(raw) {
  if (raw == null) return null;
  let s = String(raw).trim();
  if (!s) return null;
  let sign = 1;
  // 회계 표기 음수: (1,234)
  if (/^\(.*\)$/.test(s)) {
    sign = -1;
    s = s.slice(1, -1);
  }
  // 명시적 음수 부호
  if (s.startsWith('-')) {
    sign = sign * -1;
    s = s.slice(1);
  }
  // 콤마/공백 제거
  s = s.replace(/[,\s]/g, '');
  if (!/^\d+(?:\.\d+)?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n * sign : null;
}

/**
 * 모델 점수와 결정론적 valuation 점수를 보수적으로 블렌딩.
 * - 신호 1개: 10%, 2개: 18%, 3+: 25% 가중치
 * - 모델 점수에서 ±maxDelta(=10)점 이내로만 이동 (action band 한 칸 정도)
 */
function blendStockAnalysisScore({
  modelScore,
  valuationScore,
  signalCount,
  maxDelta = 15,
}) {
  if (!Number.isFinite(modelScore)) return null;
  if (!Number.isFinite(valuationScore)) return modelScore;
  // 신호가 많을수록 결정론 가중치 ↑ — 차별화 강화.
  const weight = signalCount >= 4
    ? 0.40
    : signalCount >= 3
      ? 0.32
      : signalCount >= 2
        ? 0.22
        : 0.12;
  const blended = modelScore * (1 - weight) + valuationScore * weight;
  const delta = Math.max(-maxDelta, Math.min(maxDelta, blended - modelScore));
  return Math.round(Math.max(0, Math.min(100, modelScore + delta)));
}

/**
 * 모델이 출력한 sub-score 5개를 가중합해 score를 재계산.
 *
 * 정책: 비대칭 보정.
 * - 모델 score < 가중합 - 3: 모델이 종합점수를 안전한 60대로 내린 경우.
 *   → 가중합으로 교체해서 sub-score가 보여주는 우호 신호를 종합점수에도 반영.
 * - 모델 score > 가중합 + 3: 모델이 holistic 판단으로 종합점수를 위로 올린 경우.
 *   → 모델의 conviction을 일부 존중. 가중합 + 6까지는 허용 (그 이상은 가중합+6으로 cap).
 * - 차이 ±3 이내: 모델 score 유지.
 *
 * "80+ 점수가 거의 안 나온다"는 문제는 모델이 sub 평균보다 위로 못 가는
 * 대칭 규칙 때문이었음. holistic 신호(여러 축이 함께 강할 때 시너지)는
 * 가중합만으로 잡히지 않으므로, 위쪽에만 약간의 여유를 둔다.
 */
function recomputeScoreFromSubScores(payload) {
  const sub = payload?.subScores;
  if (!sub || typeof sub !== 'object') return payload;
  const weights = {
    priceTrend: 0.25,
    newsImpact: 0.20,
    fundamentals: 0.20,
    momentumFlow: 0.20,
    riskLevel: 0.15,
  };
  let total = 0;
  let weightSum = 0;
  for (const [key, weight] of Object.entries(weights)) {
    const v = Number(sub[key]);
    if (Number.isFinite(v) && v >= 0 && v <= 100) {
      total += v * weight;
      weightSum += weight;
    }
  }
  if (weightSum < 0.5) return payload; // sub-score가 절반 이상 비었으면 패스
  const computed = Math.round(total / weightSum);
  const modelScore = Number(payload.score);
  if (!Number.isFinite(modelScore)) {
    return { ...payload, score: computed };
  }
  const delta = modelScore - computed;
  if (delta < -3) {
    // 모델이 sub 평균보다 아래로 도망침 → 가중합으로 끌어올림
    return { ...payload, score: computed };
  }
  if (delta > 6) {
    // 모델이 너무 위로 올림 → 가중합 + 6으로 cap
    return { ...payload, score: computed + 6 };
  }
  // 차이 ±3~+6 → 모델 conviction 존중
  return payload;
}

/**
 * 점수가 결정론 보정으로 이동했을 때 timing.action이 점수 밴드에서
 * 벗어났는지 검사하고 보정.
 *
 * 점수가 70인데 매수보류, 점수가 65인데 분할매수처럼 사용자가 느낄
 * "당연한 어긋남"을 막는다. 모델이 고른 action이 밴드 내 허용 범위면
 * 그대로 두고, 밴드를 벗어났을 때만 밴드의 default 값으로 교체.
 *
 * 데이터 핵심 결측 표지(timing.action이 이미 '판단보류')는 건드리지 않음.
 */
function reconcileAction(action, finalScore) {
  if (!Number.isFinite(finalScore)) return action;
  if (action === '판단보류') return action;

  const cur = typeof action === 'string' ? action.trim() : '';
  // 각 밴드의 허용 액션 집합 (밴드 default 첫 번째 + 인접 허용 옵션)
  let band;
  if (finalScore >= 80) {
    band = { allow: ['비중확대', '분할매수'], def: '비중확대' };
  } else if (finalScore >= 70) {
    band = { allow: ['분할매수', '비중확대', '매수보류'], def: '분할매수' };
  } else if (finalScore >= 60) {
    band = { allow: ['매수보류', '분할매수', '관망'], def: '매수보류' };
  } else if (finalScore >= 50) {
    band = { allow: ['관망', '매수보류'], def: '관망' };
  } else if (finalScore >= 40) {
    band = { allow: ['매수보류', '비중축소', '관망'], def: '매수보류' };
  } else if (finalScore >= 30) {
    band = { allow: ['비중축소', '매수보류'], def: '비중축소' };
  } else {
    band = { allow: ['비중축소'], def: '비중축소' };
  }

  if (band.allow.includes(cur)) return cur;
  return band.def;
}

/**
 * 점수가 결정론 보정으로 이동했을 때 scoreLabel(우호/중립/주의)이
 * 새 구간과 어긋나지 않도록 가볍게 재정렬.
 * 모델이 적은 "이유 한 문장"은 그대로 유지하고 라벨만 교체.
 */
function reconcileScoreLabel(scoreLabel, finalScore) {
  if (!Number.isFinite(finalScore)) return scoreLabel;
  // 클라이언트 _scoreColor 임계값(70/50)과 정렬.
  const expected = finalScore >= 70 ? '우호' : finalScore >= 50 ? '중립' : '주의';
  const current = typeof scoreLabel === 'string' ? scoreLabel : '';
  if (!current) return expected;
  const has = (k) => current.includes(k);
  // 라벨이 새 구간과 같은 카테고리면 그대로 유지
  if (
    (expected === '우호' && has('우호')) ||
    (expected === '중립' && has('중립')) ||
    (expected === '주의' && has('주의'))
  ) {
    return current;
  }
  // 어긋났으면 라벨만 갈아끼우고 모델이 적은 사유는 보존
  return current
    .replace(/(우호|중립|주의)/, expected)
    .replace(/^[^.]*/, (head) =>
      /(우호|중립|주의)/.test(head) ? head : expected,
    );
}

function clampSubScore(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(100, Math.round(n)));
}

function applyNaverValuationFallback(payload, naverValuation) {
  if (!payload || !naverValuation) return payload;
  const naverPeers = Array.isArray(naverValuation.peerComparison)
    ? naverValuation.peerComparison.filter((p) => p.name)
    : [];
  if ((!Array.isArray(payload.themePeers) || payload.themePeers.length === 0) &&
      naverPeers.length) {
    payload.themePeers = naverPeers.slice(0, 8).map((p) => p.name);
  }

  const valuation = payload.valuation && typeof payload.valuation === 'object'
    ? { ...payload.valuation }
    : null;
  if (!valuation) return payload;

  if (Number.isFinite(naverValuation.forwardPer)) {
    valuation.forwardPer = `${naverValuation.forwardPer.toFixed(2)}배`;
  }
  if (Number.isFinite(naverValuation.sectorAveragePer)) {
    valuation.sectorAveragePer = `동종 종목 평균 약 ${naverValuation.sectorAveragePer.toFixed(2)}배`;
    payload.peerPerAverage = `동종업계 평균 PER 약 ${naverValuation.sectorAveragePer.toFixed(2)}배`;
  }
  if ((!Array.isArray(valuation.peerComparison) || valuation.peerComparison.length === 0) &&
      naverPeers.length) {
    valuation.peerComparison = naverPeers
      .slice(0, 4)
      .map((p) => ({
        name: p.name,
        per: Number.isFinite(p.per) && p.per > 0 ? `${p.per.toFixed(2)}배` : 'N/A',
        pbr: Number.isFinite(p.pbr) && p.pbr > 0 ? `${p.pbr.toFixed(2)}배` : 'N/A',
      }));
  }
  return { ...payload, valuation };
}

function dartAccountGroup(accountName) {
  const name = String(accountName || '').replace(/\s/g, '');
  if (['매출액', '수익(매출액)', '영업수익', '매출', '매출및지분법손익'].includes(name)) return '매출액';
  if (['영업이익', '영업손실'].includes(name)) return '영업이익';
  if (['당기순이익', '당기순손실', '분기순이익', '분기순손실', '반기순이익', '반기순손실'].includes(name)) return '당기순이익';
  if (name === '자산총계') return '자산총계';
  if (name === '부채총계') return '부채총계';
  if (name === '자본총계') return '자본총계';
  return null;
}

function periodReturn(closes, period) {
  if (!Array.isArray(closes) || closes.length <= period) return null;
  const base = closes[closes.length - 1 - period];
  const last = closes[closes.length - 1];
  if (!Number.isFinite(base) || !Number.isFinite(last) || base <= 0) return null;
  return ((last / base) - 1) * 100;
}

function rsi(closes, period = 14) {
  if (!Array.isArray(closes) || closes.length <= period) return null;
  let gains = 0;
  let losses = 0;
  for (let i = closes.length - period; i < closes.length; i += 1) {
    const diff = closes[i] - closes[i - 1];
    if (diff >= 0) gains += diff;
    else losses += Math.abs(diff);
  }
  const avgGain = gains / period;
  const avgLoss = losses / period;
  if (avgLoss === 0) return 100;
  const rs = avgGain / avgLoss;
  return 100 - (100 / (1 + rs));
}

function movingAverage(closes, period) {
  if (!Array.isArray(closes) || closes.length < period) return null;
  const values = closes.slice(-period);
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function bollinger(closes) {
  if (!Array.isArray(closes) || closes.length < 20) return null;
  const values = closes.slice(-20);
  const mean = values.reduce((sum, v) => sum + v, 0) / values.length;
  const variance = values.reduce((sum, v) => sum + Math.pow(v - mean, 2), 0) / values.length;
  const sd = Math.sqrt(variance);
  const upper = mean + (2 * sd);
  const lower = mean - (2 * sd);
  const close = closes[closes.length - 1];
  const position = sd === 0
    ? '중단'
    : close >= upper
      ? '상단 접근'
      : close <= lower
        ? '하단 접근'
        : close >= mean
          ? '중상단'
          : '중하단';
  return { middle: mean, upper, lower, position };
}

function fmtMetric(value, digits = 2, suffix = '') {
  return Number.isFinite(value) ? `${value.toFixed(digits)}${suffix}` : 'N/A';
}

function fmtKrw(value) {
  if (!Number.isFinite(value)) return 'N/A';
  if (Math.abs(value) >= 1000000000000) return `${(value / 1000000000000).toFixed(2)}조원`;
  if (Math.abs(value) >= 100000000) return `${(value / 100000000).toFixed(0)}억원`;
  return `${value.toLocaleString('ko-KR')}원`;
}

function fmtEok(value) {
  return Number.isFinite(value) ? `${value.toLocaleString('ko-KR')}억원` : 'N/A';
}

async function fetchInvestorFlowForStock(ticker, market) {
  if (!/^\d{6}$/.test(String(ticker || ''))) return null;
  const marketKey = market === 'KS' ? 'kospi' : market === 'KQ' ? 'kosdaq' : null;
  if (!marketKey) return null;
  try {
    const db = getFirestore();
    const snap = await db
      .collection('market_investor_flow')
      .orderBy('marketDate', 'desc')
      .limit(1)
      .get();
    if (snap.empty) return null;
    const doc = snap.docs[0];
    const data = doc.data() || {};
    const bucket = data[marketKey] || {};
    const findItem = (items) =>
      Array.isArray(items) ? items.find((item) => String(item.code) === ticker) || null : null;
    const pick = (item) => item
      ? {
          rank: Number.isFinite(Number(item.rank)) ? Number(item.rank) : null,
          amountText: clampStockAnalysisInput(item.amountText, 60),
          quantityText: clampStockAnalysisInput(item.quantityText, 60),
        }
      : null;
    return {
      marketDate: clampStockAnalysisInput(data.marketDate || doc.id, 20),
      market: marketKey.toUpperCase(),
      foreign: pick(findItem(bucket.foreignTop5)),
      institution: pick(findItem(bucket.institutionTop5)),
    };
  } catch (e) {
    console.warn('[fetchInvestorFlowForStock] failed:', e.message);
    return null;
  }
}

async function fetchNaverStockInvestorFlow(ticker) {
  if (!/^\d{6}$/.test(String(ticker || ''))) return null;
  try {
    const res = await axios.get(`https://finance.naver.com/item/frgn.naver`, {
      params: { code: ticker, page: 1 },
      responseType: 'arraybuffer',
      timeout: 12000,
      headers: {
        'User-Agent': 'Mozilla/5.0',
        Referer: 'https://finance.naver.com/',
        'Accept-Language': 'ko-KR,ko;q=0.9',
      },
    });
    const $ = cheerio.load(eucKrDecoder.decode(res.data));
    const days = [];
    $('table.type2 tr').each((_, tr) => {
      const cells = $(tr)
        .find('td')
        .map((__, td) => $(td).text().trim().replace(/\s+/g, ' '))
        .get();
      if (cells.length < 9 || !/^\d{4}\.\d{2}\.\d{2}$/.test(cells[0])) return;
      days.push({
        date: cells[0],
        close: numOrNull(cells[1]),
        changeRate: signedNumOrNull(cells[3]),
        volume: numOrNull(cells[4]),
        institutionNet: numOrNull(cells[5]),
        foreignNet: numOrNull(cells[6]),
        foreignHoldShares: numOrNull(cells[7]),
        foreignHoldRate: numOrNull(cells[8]),
      });
    });
    const recent = days.slice(0, 14);
    const sum = (key) => recent.reduce((acc, day) => acc + (Number.isFinite(day[key]) ? day[key] : 0), 0);
    const latest = recent[0] || null;
    return {
      source: 'Naver Finance item/frgn',
      days: recent,
      foreignNet14: sum('foreignNet'),
      institutionNet14: sum('institutionNet'),
      latestForeignHoldRate: latest?.foreignHoldRate ?? null,
    };
  } catch (e) {
    console.warn('[fetchNaverStockInvestorFlow] failed:', e.message);
    return null;
  }
}

async function fetchNewsStorySnippets(news) {
  const targets = (Array.isArray(news) ? news : [])
    .filter((n) => /^https?:\/\//.test(String(n.url || '')))
    .slice(0, 5);
  const results = await Promise.all(
    targets.map(async (n) => {
      try {
        const res = await axios.get(n.url, {
          timeout: 8000,
          headers: {
            'User-Agent': 'Mozilla/5.0',
            'Accept-Language': 'ko-KR,ko;q=0.9',
          },
        });
        const $ = cheerio.load(res.data);
        const meta =
          $('meta[property="og:description"]').attr('content') ||
          $('meta[name="description"]').attr('content') ||
          $('article').text() ||
          $('body').text();
        const snippet = clampStockAnalysisInput(
          String(meta || '').replace(/\s+/g, ' '),
          450,
        );
        return snippet
          ? {
              title: clampStockAnalysisInput(n.title, 180),
              publisher: clampStockAnalysisInput(n.publisher, 80),
              snippet,
            }
          : null;
      } catch (_) {
        return null;
      }
    }),
  );
  return results.filter(Boolean);
}

async function fetchDartReportStory(corp, disclosures, apiKey) {
  const report = (Array.isArray(disclosures) ? disclosures : []).find((d) =>
    /사업보고서|분기보고서|반기보고서/.test(d.title || ''),
  );
  if (!corp?.corpCode || !report?.receiptNo || !apiKey) return null;
  try {
    const res = await axios.get('https://opendart.fss.or.kr/api/document.xml', {
      params: { crtfc_key: apiKey, rcept_no: report.receiptNo },
      responseType: 'arraybuffer',
      timeout: 15000,
    });
    let text = '';
    try {
      const zip = new AdmZip(Buffer.from(res.data));
      const entry = zip.getEntries().find((e) => !e.isDirectory);
      text = entry ? entry.getData().toString('utf8') : '';
    } catch (_) {
      text = Buffer.from(res.data).toString('utf8');
    }
    text = text
      .replace(/<[^>]+>/g, ' ')
      .replace(/&[a-z]+;/gi, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    const keywords = ['주요 제품', '사업의 내용', '매출', '신규사업', '시장점유율', '영업의 개황'];
    const snippets = [];
    for (const keyword of keywords) {
      const index = text.indexOf(keyword);
      if (index >= 0) {
        snippets.push(text.slice(Math.max(0, index - 120), index + 520));
      }
      if (snippets.length >= 3) break;
    }
    const body = clampStockAnalysisInput(snippets.join(' / ') || text, 1800);
    return body
      ? {
          title: report.title,
          date: report.date,
          receiptNo: report.receiptNo,
          body,
        }
      : null;
  } catch (e) {
    console.warn('[fetchDartReportStory] failed:', e.response?.data || e.message);
    return null;
  }
}

function buildTechnicalSnapshot(candles) {
  const closes = candles
    .map((c) => Number(c.close))
    .filter((v) => Number.isFinite(v) && v > 0);
  const b = bollinger(closes);
  const latest = closes.length ? closes[closes.length - 1] : null;
  return {
    latestClose: latest,
    rsi14: rsi(closes, 14),
    return5: periodReturn(closes, 5),
    return20: periodReturn(closes, 20),
    return60: periodReturn(closes, 60),
    return120: periodReturn(closes, 120),
    ma5: movingAverage(closes, 5),
    ma20: movingAverage(closes, 20),
    ma60: movingAverage(closes, 60),
    ma120: movingAverage(closes, 120),
    bollinger: b,
  };
}

function seoulDateKey() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

function freeDailyAiLimit(level) {
  if (level >= 20) return 5;
  if (level >= 10) return 3;
  if (level >= 5) return 2;
  return 1;
}

async function hasRevenueCatPremium(uid, secretApiKey) {
  const apiKey = (secretApiKey || '').trim();
  if (!apiKey) return false;
  // 분석 호출의 임계 경로 — 재시도로 지연이 길어지면 클라이언트 콜러블이
  // 재전송해 이중 차감이 생길 수 있으므로 단일 시도로 둔다. 타임아웃은 8s.
  try {
    const response = await axios.get(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      {
        headers: {
          Authorization: `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 8000,
      }
    );
    const premium = response.data?.subscriber?.entitlements?.premium;
    if (!premium) return false;
    if (!premium.expires_date) return true;
    return Date.parse(premium.expires_date) > Date.now();
  } catch (error) {
    console.warn('[RevenueCat] premium lookup failed:', error?.message || error);
    return false;
  }
}

// 클라이언트(AuthService.adminUids)와 동일하게 유지할 것.
const ADMIN_UIDS = new Set([
  '1KzEXKZMoFaYOymYyoI283AR3Y32',
  'v4a3ClF3FhWGXsGnZ29wyvQNSCX2',
]);

async function isAdminUid(uid) {
  if (!uid) return false;
  if (ADMIN_UIDS.has(uid)) return true;
  try {
    const snap = await getFirestore().collection('config').doc('admin').get();
    const data = snap.data() || {};
    if (data.uid && data.uid === uid) return true;
    if (Array.isArray(data.uids) && data.uids.includes(uid)) return true;
    return false;
  } catch (e) {
    console.warn('[isAdminUid] lookup failed:', e?.message || e);
    return false;
  }
}

async function consumeStockAiAnalysisQuota(uid, revenueCatSecretApiKey, requestId) {
  if (await isAdminUid(uid)) return null;
  const db = getFirestore();
  const isPremium = await hasRevenueCatPremium(uid, revenueCatSecretApiKey);
  const dateKey = seoulDateKey();
  const quotaRef = db.collection('users').doc(uid).collection('ai_quota').doc(dateKey);
  const publicRef = db.collection('user_public').doc(uid);
  const reqId = (requestId || '').toString().trim().slice(0, 64);

  await db.runTransaction(async (tx) => {
    const [quotaSnap, publicSnap] = await Promise.all([
      tx.get(quotaRef),
      tx.get(publicRef),
    ]);
    const data = quotaSnap.data() || {};
    const recent = Array.isArray(data.recentRequestIds) ? data.recentRequestIds : [];
    // 같은 requestId가 이미 차감됐으면(전송 재시도/이중 호출) 재차감하지 않는다.
    if (reqId && recent.includes(reqId)) return;
    const used = Number(data.count || 0);
    const level = Number(publicSnap.data()?.level || 1);
    const limit = isPremium ? 5 : freeDailyAiLimit(level);
    if (used >= limit) {
      throw new HttpsError(
        'resource-exhausted',
        isPremium
          ? '프리미엄 AI 분석은 하루 5회까지 사용할 수 있습니다.'
          : `현재 레벨에서는 AI 분석을 하루 ${limit}회까지 사용할 수 있습니다.`
      );
    }
    // 최근 requestId를 최대 20개까지만 보관(멱등성 판단용).
    const nextRecent = reqId ? [...recent, reqId].slice(-20) : recent;
    tx.set(
      quotaRef,
      {
        count: used + 1,
        recentRequestIds: nextRecent,
        updatedAt: new Date(),
        lastAccess: isPremium ? 'premium' : 'free',
      },
      { merge: true }
    );
  });
  return dateKey;
}

async function refundStockAiAnalysisQuota(uid, dateKey, requestId) {
  if (!uid || !dateKey) return;
  const reqId = (requestId || '').toString().trim().slice(0, 64);
  try {
    const db = getFirestore();
    const quotaRef = db.collection('users').doc(uid).collection('ai_quota').doc(dateKey);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(quotaRef);
      const data = snap.data() || {};
      const recent = Array.isArray(data.recentRequestIds) ? data.recentRequestIds : [];
      // requestId가 있는데 차감 기록이 없으면(중복 환불/차감 안 됨) 환불하지 않는다.
      if (reqId && !recent.includes(reqId)) return;
      const used = Number(data.count || 0);
      if (used <= 0) return;
      tx.set(
        quotaRef,
        {
          count: used - 1,
          recentRequestIds: reqId ? recent.filter((id) => id !== reqId) : recent,
          updatedAt: new Date(),
        },
        { merge: true }
      );
    });
  } catch (e) {
    console.warn('[generateStockAiAnalysis] quota refund failed:', e?.message || e);
  }
}

exports.generateStockAiAnalysis = onCall(
  {
    region: 'asia-northeast3',
    timeoutSeconds: 540,
    memory: '1GiB',
    secrets: [OPENAI_API_KEY, DART_API_KEY, REVENUECAT_SECRET_API_KEY],
  },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', '로그인 후 AI 분석을 사용할 수 있습니다.');
    }

    const data = request.data || {};
    const stock = data.stock || {};
    const price = data.price || {};
    const fundamentals = data.fundamentals || {};
    const candles = Array.isArray(data.candles) ? data.candles.slice(-140) : [];
    const news = Array.isArray(data.news) ? data.news.slice(0, 8) : [];

    const ticker = clampStockAnalysisInput(stock.ticker, 30);
    const name = clampStockAnalysisInput(stock.name, 120);
    const market = clampStockAnalysisInput(stock.market, 20);
    if (!ticker || !name) {
      throw new HttpsError('invalid-argument', '종목명과 티커가 필요합니다.');
    }
    const requestId = clampStockAnalysisInput(data.requestId, 64);
    const quotaDateKey = await consumeStockAiAnalysisQuota(
      request.auth.uid,
      REVENUECAT_SECRET_API_KEY.value(),
      requestId
    );
    try {
    const isDomesticStock = /^\d{6}$/.test(ticker) && ['KS', 'KQ'].includes(market.toUpperCase());

    const candleLines = candles.map((c) => {
      const date = clampStockAnalysisInput(c.date, 20);
      const open = Number(c.open);
      const high = Number(c.high);
      const low = Number(c.low);
      const close = Number(c.close);
      if (![open, high, low, close].every(Number.isFinite)) return null;
      return `${date} O:${open} H:${high} L:${low} C:${close}`;
    }).filter(Boolean).join('\n');
    const technicalSnapshot = buildTechnicalSnapshot(candles);

    const newsLines = news.map((n, i) => {
      const title = clampStockAnalysisInput(n.title, 220);
      const publisher = clampStockAnalysisInput(n.publisher, 80);
      const publishedAt = clampStockAnalysisInput(n.publishedAt, 40);
      return `${i + 1}. ${title}${publisher ? ` (${publisher})` : ''}${publishedAt ? ` - ${publishedAt}` : ''}`;
    }).filter(Boolean).join('\n');

    const [kisSnapshot, dartContext, investorFlow, dailyInvestorFlow, newsStorySnippets, naverValuation, epsTimeline] = isDomesticStock
      ? (await Promise.allSettled([
          fetchKisDomesticSnapshot(ticker),
          fetchDartContext(ticker, (DART_API_KEY.value() || '').trim()),
          fetchInvestorFlowForStock(ticker, market.toUpperCase()),
          fetchNaverStockInvestorFlow(ticker),
          fetchNewsStorySnippets(news),
          fetchNaverDomesticValuation(ticker),
          fetchNaverEpsTimeline(ticker),
        ])).map((r, i) => {
          if (r.status === 'fulfilled') return r.value;
          console.warn(`[generateStockAiAnalysis] external fetch #${i} failed:`, r.reason?.message || r.reason);
          return i === 4 ? [] : null;
        })
      : [null, null, null, null, [], null, null];

    const kisLines = kisSnapshot
      ? [
          `- 현재가: ${fmtMetric(kisSnapshot.price, 0)}원`,
          `- 등락률: ${fmtMetric(kisSnapshot.changeRate, 2, '%')}`,
          `- 누적거래량: ${Number.isFinite(kisSnapshot.volume) ? kisSnapshot.volume.toLocaleString('ko-KR') : 'N/A'}주`,
          `- 누적거래대금: ${fmtKrw(kisSnapshot.tradingValue)}`,
          `- 시가총액(KIS): ${fmtEok(kisSnapshot.marketCap)}`,
          `- PER/PBR/EPS/BPS(KIS): ${fmtMetric(kisSnapshot.per, 2)} / ${fmtMetric(kisSnapshot.pbr, 2)} / ${fmtMetric(kisSnapshot.eps, 0)}원 / ${fmtMetric(kisSnapshot.bps, 0)}원`,
          `- 52주 고가/저가: ${fmtMetric(kisSnapshot.high52w, 0)}원 / ${fmtMetric(kisSnapshot.low52w, 0)}원`,
        ].join('\n')
      : '- KIS 상세 스냅샷: 미수집';

    const naverValuationLines = naverValuation
      ? [
          `- PER/PBR/BPS: ${fmtMetric(naverValuation.per, 2)} / ${fmtMetric(naverValuation.pbr, 2)} / ${fmtMetric(naverValuation.bps, 0)}원`,
          `- FPER/추정EPS: ${fmtMetric(naverValuation.forwardPer, 2)} / ${fmtMetric(naverValuation.forwardEps, 0)}원`,
          `- 동종업계 평균 PER: ${fmtMetric(naverValuation.sectorAveragePer, 2)}배`,
          `- 동종 종목: ${naverValuation.peerComparison?.length ? naverValuation.peerComparison.map((p) => {
            const parts = [p.name];
            if (Number.isFinite(p.per)) parts.push(`PER ${p.per.toFixed(2)}배`);
            if (Number.isFinite(p.pbr)) parts.push(`PBR ${p.pbr.toFixed(2)}배`);
            return parts.join(' ');
          }).join(', ') : 'N/A'}`,
        ].join('\n')
      : '- 네이버 밸류에이션: 미수집';
    const naverReportLines = naverValuation?.reports?.length
      ? naverValuation.reports.map((r, i) =>
          `${i + 1}. ${r.date} ${r.broker} "${r.title}" / 의견 ${r.opinion || 'N/A'} / 목표가 ${Number.isFinite(r.targetPrice) ? `${r.targetPrice.toLocaleString('ko-KR')}원` : '미제공'}`,
        ).join('\n')
      : `- ${NAVER_RESEARCH_LOOKBACK_LABEL} 증권사 리포트: 미수집`;

    const epsTimelineLines = Array.isArray(epsTimeline) && epsTimeline.length
      ? epsTimeline
          .map((row) => {
            const epsText = Number.isFinite(row.eps) ? `${row.eps.toLocaleString('ko-KR')}원` : 'N/A';
            const perText = Number.isFinite(row.per) ? `${row.per.toFixed(2)}배` : null;
            const tag = row.estimate ? ' (컨센서스)' : '';
            return `- ${row.period}${tag}: EPS ${epsText}${perText ? ` / PER ${perText}` : ''}`;
          })
          .join('\n')
      : '- 연도별 EPS·PER 컨센서스 시계열: 미수집';

    const dartDisclosureLines = dartContext?.hasData && dartContext.disclosures?.length
      ? dartContext.disclosures
          .map((d, i) => `${i + 1}. ${d.date} ${d.title} (${d.submitter || '제출자 미상'}, 접수번호 ${d.receiptNo})`)
          .join('\n')
      : `- 최근 공시: ${dartContext?.reason || '수집 데이터 없음'}`;

    const dartFinancialLines = dartContext?.hasData && dartContext.financials?.length
      ? [
          `- 기준 보고서: ${dartContext.financialReport || '확인 필요'}`,
          ...dartContext.financials.map((f) => `- ${f.account}: 당기 ${f.current || 'N/A'} / 전기 ${f.previous || 'N/A'} (${f.statement || '재무제표'})`),
        ].join('\n')
      : `- 재무제표: ${dartContext?.reason || '수집 데이터 없음'}`;

    const investorFlowLines = investorFlow
      ? [
          `- 기준일: ${investorFlow.marketDate}`,
          `- 외국인 순매수 상위(TOP20) 포함 여부: ${investorFlow.foreign ? `${investorFlow.foreign.rank}위, ${investorFlow.foreign.amountText}` : '미포함'}`,
          `- 기관 순매수 상위(TOP20) 포함 여부: ${investorFlow.institution ? `${investorFlow.institution.rank}위, ${investorFlow.institution.amountText}` : '미포함'}`,
        ].join('\n')
      : '- 수급 스냅샷: 미수집';

    const dailyInvestorFlowLines = dailyInvestorFlow?.days?.length
      ? [
          `- 최근 ${dailyInvestorFlow.days.length}거래일 외국인 순매매 합계: ${dailyInvestorFlow.foreignNet14.toLocaleString('ko-KR')}주`,
          `- 최근 ${dailyInvestorFlow.days.length}거래일 기관 순매매 합계: ${dailyInvestorFlow.institutionNet14.toLocaleString('ko-KR')}주`,
          `- 최신 외국인 보유율: ${fmtMetric(dailyInvestorFlow.latestForeignHoldRate, 2, '%')}`,
          ...dailyInvestorFlow.days.map((d) =>
            `- ${d.date}: 외국인 ${Number.isFinite(d.foreignNet) ? d.foreignNet.toLocaleString('ko-KR') : 'N/A'}주 / 기관 ${Number.isFinite(d.institutionNet) ? d.institutionNet.toLocaleString('ko-KR') : 'N/A'}주 / 등락률 ${fmtMetric(d.changeRate, 2, '%')}`,
          ),
        ].join('\n')
      : '- 최근 2주 일별 수급: 미수집';

    const newsStoryLines = newsStorySnippets?.length
      ? newsStorySnippets
          .map((n, i) => `${i + 1}. ${n.title}${n.publisher ? ` (${n.publisher})` : ''}: ${n.snippet}`)
          .join('\n')
      : '- 뉴스 본문 요약: 미수집';

    const dartStoryLines = dartContext?.reportStory
      ? `- ${dartContext.reportStory.date} ${dartContext.reportStory.title}: ${dartContext.reportStory.body}`
      : '- DART 사업 내용 요약: 미수집';

    const sourcePayload = {
      sourceNews: news.map((n) => ({
        title: clampStockAnalysisInput(n.title, 220),
        url: clampStockAnalysisInput(n.url, 500),
        publisher: clampStockAnalysisInput(n.publisher, 80),
        publishedAt: clampStockAnalysisInput(n.publishedAt, 40),
      })).filter((n) => n.title),
      sourceMarketCap: Number.isFinite(kisSnapshot?.marketCap)
        ? Math.round(kisSnapshot.marketCap * 100000000)
        : null,
      sourceEps: Number.isFinite(kisSnapshot?.eps) ? kisSnapshot.eps : null,
      sourceInvestorFlow: investorFlow,
      sourceDailyInvestorFlow: dailyInvestorFlow,
      sourceReports: naverValuation?.reports?.length
        ? naverValuation.reports.map((r) => ({
            title: clampStockAnalysisInput(r.title, 180),
            url: clampStockAnalysisInput(r.url, 500),
            publisher: clampStockAnalysisInput(r.broker, 80),
            publishedAt: clampStockAnalysisInput(r.date, 40),
            opinion: clampStockAnalysisInput(r.opinion, 40),
            targetPrice: Number.isFinite(r.targetPrice) ? r.targetPrice : null,
            previousTargetPrice: Number.isFinite(r.previousTargetPrice) ? r.previousTargetPrice : null,
            priceAtWriteDate: Number.isFinite(r.priceAtWriteDate) ? r.priceAtWriteDate : null,
          })).filter((r) => r.title)
        : [],
      sourceDisclosures: dartContext?.hasData && Array.isArray(dartContext.disclosures)
        ? dartContext.disclosures.map((d) => ({
            date: clampStockAnalysisInput(d.date, 20),
            title: clampStockAnalysisInput(d.title, 180),
            url: d.receiptNo ? `https://dart.fss.or.kr/dsaf001/main.do?rcpNo=${encodeURIComponent(d.receiptNo)}` : '',
            submitter: clampStockAnalysisInput(d.submitter, 80),
            receiptNo: clampStockAnalysisInput(d.receiptNo, 30),
          })).filter((d) => d.title)
        : [],
      sourceFinancials: dartContext?.hasData && Array.isArray(dartContext.financials)
        ? dartContext.financials.map((f) => ({
            account: clampStockAnalysisInput(f.account, 40),
            current: clampStockAnalysisInput(f.current, 40),
            previous: clampStockAnalysisInput(f.previous, 40),
            statement: clampStockAnalysisInput(f.statement, 40),
          })).filter((f) => f.account)
        : [],
      sourceEpsTimeline: Array.isArray(epsTimeline)
        ? epsTimeline
            .map((row) => ({
              period: clampStockAnalysisInput(row?.period, 20),
              eps: Number.isFinite(row?.eps) ? row.eps : null,
              per: Number.isFinite(row?.per) ? row.per : null,
              estimate: Boolean(row?.estimate),
            }))
            .filter((row) => row.period && row.eps != null)
        : [],
    };

    const providedForwardPer = Number.isFinite(Number(fundamentals.forwardPer))
      ? Number(fundamentals.forwardPer)
      : naverValuation?.forwardPer;
    const providedSectorAveragePer = Number.isFinite(Number(fundamentals.sectorAveragePer))
      ? Number(fundamentals.sectorAveragePer)
      : naverValuation?.sectorAveragePer;

    const prompt = `당신은 한국 주식 앱의 "AI 종목 분석 리포트"를 작성하는 애널리스트입니다.
아래 데이터만 근거로, 사용자가 모바일 화면에서 바로 읽을 수 있는 정교한 점수형 리포트를 작성하세요.
데이터에 없는 사실은 "확인 필요" 또는 "추정"이라고 명시하고, 단정적인 매수/매도 권유와 목표가 제시는 금지합니다.

[종목]
- 이름: ${name}
- 티커: ${ticker}
- 시장: ${market}

[현재가]
- 가격: ${price.currentPrice ?? 'N/A'}
- 등락: ${price.change ?? 'N/A'}
- 등락률: ${price.changeRate ?? 'N/A'}%

[밸류에이션/재무]
- 시가총액: ${fundamentals.marketCap ?? 'N/A'}
- PER(trailing): ${fundamentals.per ?? 'N/A'}
- PBR: ${fundamentals.pbr ?? 'N/A'}
- BPS: ${fundamentals.bps ?? 'N/A'}
- Forward PER (제공 데이터, 있으면 그대로 사용): ${Number.isFinite(providedForwardPer) ? providedForwardPer.toFixed(2) : 'N/A'}
- 업종/동종 종목 평균 PER (제공 데이터, 있으면 그대로 사용): ${Number.isFinite(providedSectorAveragePer) ? providedSectorAveragePer.toFixed(2) : 'N/A'}

[KIS 현재가/거래/밸류 스냅샷]
${kisLines}

[네이버 밸류에이션/동종업계 스냅샷]
${naverValuationLines}

[${NAVER_RESEARCH_LOOKBACK_LABEL} 증권사 리포트]
${naverReportLines}

[연도별 EPS·PER 컨센서스 시계열 (오래된 → 최신)]
${epsTimelineLines}

[외국인/기관 수급 스냅샷]
${investorFlowLines}

[최근 2주 일별 외국인/기관 수급]
${dailyInvestorFlowLines}

[OpenDART 최근 공시: 최근 180일, 최대 10건]
${dartDisclosureLines}

[OpenDART 최근 재무제표 주요 계정]
${dartFinancialLines}

[DART 사업/제품 스토리 근거]
${dartStoryLines}

[최근 캔들: 오래된 순서]
${candleLines || 'N/A'}

[앱 계산 기술 지표]
- 최신 종가: ${fmtMetric(technicalSnapshot.latestClose, 0)}
- RSI(14): ${fmtMetric(technicalSnapshot.rsi14, 1)}
- 5일 수익률: ${fmtMetric(technicalSnapshot.return5, 1, '%')}
- 20일 수익률: ${fmtMetric(technicalSnapshot.return20, 1, '%')}
- 60일 수익률: ${fmtMetric(technicalSnapshot.return60, 1, '%')}
- 120일 수익률: ${fmtMetric(technicalSnapshot.return120, 1, '%')}
- MA5: ${fmtMetric(technicalSnapshot.ma5, 0)}
- MA20: ${fmtMetric(technicalSnapshot.ma20, 0)}
- MA60: ${fmtMetric(technicalSnapshot.ma60, 0)}
- MA120: ${fmtMetric(technicalSnapshot.ma120, 0)}
- 볼린저밴드: ${technicalSnapshot.bollinger ? `중심 ${fmtMetric(technicalSnapshot.bollinger.middle, 0)}, 상단 ${fmtMetric(technicalSnapshot.bollinger.upper, 0)}, 하단 ${fmtMetric(technicalSnapshot.bollinger.lower, 0)}, 위치 ${technicalSnapshot.bollinger.position}` : 'N/A'}

[최근 뉴스 헤드라인]
${newsLines || 'N/A'}

[뉴스 본문/요약 스토리 근거]
${newsStoryLines}

[리포트 작성 원칙]
- 화면은 "종합 점수판 → 핵심 재료 → 시나리오 → 전망·액션 → 데이터 보드 → 리스크 상세 → 근거 소스" 순서로 보여줄 예정입니다. 유료 사용자가 보는 화면이라 정보의 깊이와 구체성이 중요합니다.
- 점수 구간 표현은 하나만 사용하세요. "우호와 중립", "중립-우호", "중립~긍정"처럼 서로 다른 판단을 동시에 쓰지 마세요.
- 각 필드에는 숫자, 방향성, 근거, 한계를 같이 넣으세요. 예: "PER 16.2배는 반도체 업종 평균 약 14배보다 다소 높은 편, PBR 2.39배는 장부가 대비 프리미엄 구간."

[금지 표현 / 메타 코멘트 절대 사용 금지]
사용자에게 보이는 화면이므로 다음 표현은 어떤 필드에서도 절대 사용하지 마세요. 이 규칙을 어기면 출력은 무효입니다.
- "중립 성향의 리포트입니다", "이 리포트는...", "본 리포트는..." 같은 자기 메타 코멘트
- "(정량적 내용 미공개)", "(비공개)", "(자세한 수치는 비공개)" 같은 비공개 디스클레이머
- "미확인 변수", "확인 필요" 단독, "산출 불가", "데이터 없음" 같은 placeholder 표현
- "KIS 기준", "OpenDART 기준", "(KIS)", "(OpenDART)", "데이터:", "단위 확인 필요" 같은 데이터 출처/내부 처리 문구
- "핵심 원인은", "핵심 원인:", "근거 뉴스/공시:", "거래/가격 반응:", "설명 한계:"처럼 분석 메모 라벨로 시작하는 문장
- "표기됩니다", "제공됩니다" 같은 보고서체 — "확인됩니다", "나타납니다"로 대체
- AI/모델 자체에 대한 언급 ("모델이", "AI 추정", "본 분석은")

[숫자/추정 강제]
- 모든 숫자 필드는 반드시 구체 숫자 또는 범위로 채우세요. 데이터가 없으면 모델이 알고 있는 최신 시장 지식을 바탕으로 추정값을 적고 끝에 "(추정)"만 붙이세요. "(추정)"은 허용되지만 placeholder는 금지.
- valuation.forwardPer: 입력 "Forward PER (제공 데이터)"가 N/A가 아니면 그 값을 그대로 사용(예: "12.4배"). N/A이면 향후 1~2년 EPS 추정과 현재가 기준으로 직접 산출한 숫자를 적으세요. 예: "약 11배(추정)" 또는 "10~13배 범위(추정)". 절대 빈 문자열이나 "산출 불가" 금지.
- valuation.sectorAveragePer: 입력 "업종/동종 종목 평균 PER (제공 데이터)"가 N/A가 아니면 그 값을 그대로 사용하세요. N/A이면 해당 종목이 속한 한국/미국 업종의 평균 PER을 반드시 숫자로 추정하세요. 예: "반도체 업종 약 14배(추정)", "양극재/2차전지 약 25배(추정)", "S&P500 평균 약 22배". 빈 문자열 금지.
- peerPerAverage: sectorAveragePer와 동일한 숫자를 다른 한 줄 표현으로. 예: "동종업계 평균 PER 약 14배(추정)".
- valuation.peerComparison: 2~4개 동종업계 종목의 trailing PER/PBR을 반드시 숫자로. 정말 모르는 한 두 항목만 "N/A" 허용. "약 18.5" "20배 안팎" 같은 표현 가능.

- PER만으로 고평가/저평가를 단정하지 마세요. 선행 PER, 실적 개선 스토리, 동종업계 비교를 함께 고려해 종합 판단하세요.
- 바이오/제약/플랫폼/적자 성장주는 절대 PER보다 동종업계 평균, 파이프라인/임상 단계, 매출 성장률, 현금흐름을 우선 비교하세요. 단 sectorAveragePer는 비교 가능한 typical 범위를 그래도 숫자로 제시.
- themePeers에 3~8개 종목명, peerComparison과 일부 겹쳐도 됨.
- 앱 계산 기술 지표의 RSI, 기간 수익률, 이동평균, 볼린저밴드는 반드시 technical 또는 sections에 구체적인 숫자로 반영하세요.
- 이동평균은 5/20/60/120일선을 따로 나열하기보다 현재가가 단기·중기·장기 평균선 대비 위/아래 어디에 있는지 종합 판정으로 설명하세요. "5/20/60/120일 대비 상회"라고 쓰지 말고 "5·20·60·120일 이동평균선 위"처럼 정확히 쓰세요.
- KIS와 OpenDART 수집 데이터는 숫자/공시명/날짜를 임의로 바꾸지 말고 그대로 인용하세요.
- 사용자 화면에 표시될 문장에는 "KIS", "OpenDART", "KIS 기준", "OpenDART 기준", "데이터:", "단위 확인 필요", "표기됩니다" 같은 내부 처리 문구를 쓰지 마세요.
- 출처명보다 사용자가 이해할 원인과 의미를 우선하세요. 예: "최근 공시에 따르면", "현재가 기준", "최근 2주 수급에서는"처럼 표현하세요.
- KIS EPS가 제공되면 EPS를 역산하지 말고 제공 EPS를 기준으로 설명하세요. EPS가 N/A일 때만 역산 가능성과 한계를 설명하세요.
- 시가총액(KIS)은 억원 단위로 제공됩니다. 예: "1조 86억원" 또는 "10,086억원"처럼 사용자 친화적으로 표현하세요.
- DART 사업/제품 스토리 근거와 뉴스 본문 요약에 제품명, 사업부문, 고객사, 수요처, 매출 성장 단서가 있으면 이를 당일 재료와 테마 분석의 핵심 근거로 우선 반영하세요. 예: MLCC, 전장부품, 반도체 소재처럼 구체 제품/산업명을 쓰세요.
- 실적 서프라이즈는 컨센서스 데이터가 없으면 "컨센서스 데이터가 없어 서프라이즈 여부는 판단할 수 없습니다"라고 쓰세요.
- 최근 공시 목록은 원인 판단의 내부 근거로만 사용하세요. summary, todayReason, news, catalysts, sections에는 "2026-05-27 [기재정정]투자판단관련주요경영사항"처럼 날짜+공시명을 그대로 노출하지 말고, "최근 주요 경영사항 정정 공시가 있었습니다"처럼 의미를 풀어 쓰세요.
- "좋다/나쁘다"만 쓰지 말고 왜 그런지 근거를 붙이세요.
- 사용자에게 직접 말하는 문장은 모두 높임말로 작성하세요. 반말, 명령조, "봐야 함", "~임", "~가능" 같은 메모체를 쓰지 마세요.
- 문장 끝은 되도록 "입니다", "습니다", "필요합니다", "보입니다", "확인됩니다"처럼 마무리하세요.
- 투자 조언처럼 보이는 표현(매수, 매도, 목표가, 반드시, 확실)은 금지합니다.

[점수 산정 프레임]
0~100점으로 평가하세요. 기준은 다음 가중치입니다.
- 가격/추세/기술적 흐름 25점: 최근 캔들, 5/20/60/120일 이동평균 추정, 추세, 변동성, 지지/저항
- 뉴스/당일 재료 20점: 최근 뉴스 방향성, 등락 설명력, 테마성, 이벤트 신뢰도
- 재무/밸류에이션 20점: 다음을 종합해 평가하세요.
  * (a) trailing PER 단독으로 고평가/저평가 결론 금지. **forward PER 또는 1~2년 EPS 추정 기반 PER**을 1차 기준으로 사용.
  * (b) forward PER이 trailing PER보다 의미 있게 낮으면(예: 70% 이하) 실적 회복 시그널로 가산, 30% 이상 낮으면 강한 가산. 반대로 forward PER이 trailing PER을 크게 상회하면 둔화로 감점.
  * (c) forward PER이 업종평균 PER 대비 할인이면 가산, 프리미엄이면 감점.
  * (d) EPS 시계열에서 향후 1~2년 EPS가 증가 추세면 가산, 감소면 감점. **적자→흑자 전환은 강한 가산**.
  * (e) PBR/BPS/시총은 참고용 보조 지표로만 사용.
  * Forward PER이 N/A여도 EPS 시계열에서 직접 추정해 반영하세요.
- 모멘텀/수급 추정 20점: 단기 모멘텀, 거래량/변동성 단서, 과열/눌림
- 리스크 15점: 데이터 부족, 밸류 부담, 뉴스 노이즈, 기술적 이탈 가능성

[점수 산출 절차 — 반드시 다음 순서대로]
1단계: 다섯 축 sub-score를 각각 0~100으로 결정. 각 축을 **독립적으로** 평가하고, 약한 신호엔 35~50, 보통 신호엔 50~65, 강한 신호엔 65~85, 매우 강한 신호엔 85+ 범위에서 정확한 정수값을 매기세요.
  - priceTrend (가중 25%): 추세/모멘텀/지지저항 위치
  - newsImpact (가중 20%): 뉴스 방향성/재료 신뢰도
  - fundamentals (가중 20%): 위 [점수 산정 프레임] 재무 규칙대로
  - momentumFlow (가중 20%): 단기 모멘텀/수급 추정
  - riskLevel (가중 15%): 데이터 결측·밸류 부담·뉴스 노이즈가 적을수록 **높은** 값 (즉 100 = 리스크 거의 없음)

2단계: 종합 score = round(priceTrend*0.25 + newsImpact*0.20 + fundamentals*0.20 + momentumFlow*0.20 + riskLevel*0.15)
이 계산값에서 ±3 이내로만 조정 가능. 그 이상 벗어나면 안 됩니다.

[점수 분포 강제 규칙 — 위반 금지]
- 60~65 구간을 default로 쓰지 마세요. 진짜 양방향 혼조가 아니라면 피하세요.
- 다섯 sub-score가 모두 55~65에 몰리면 안 됩니다 — 어느 한 축은 분명히 70 이상이거나 50 이하여야 합니다 (정말 평탄한 종목이 아닌 한).
- 두 종목의 한 축에서 30점 이상 차이나면 → 종합 점수도 **5점 이상** 차이나야 합니다.
- "확인 필요"라는 이유로 회피하지 말고, 데이터가 보여주는 방향으로 25~90 범위 안에서 명확히 결정하세요.
- 동점 금지, 1점 단위 차별화.
- **상단 분포 강제**: 신호가 다축으로 함께 강한 종목(추세+모멘텀+재료가 모두 우호)에서는 종합 80+를 피하지 마세요. 100개 분석 중 5~15개는 80점대가 나와야 정상 분포입니다. 75에서 멈추지 말고 강한 종목은 82, 85, 88까지 올리세요. 90+는 정말 드물지만 가능합니다.
- **하단 분포 강제**: 다축이 함께 약한 종목(추세 하락 + 실적 둔화 + 리스크 큼)도 35~45 구간을 피하지 말고 명확히 점수에 반영하세요.
- 종합점수는 sub-score 가중평균에서 ±3 이내가 원칙이지만, 다축이 동시에 강하면(시너지) 가중평균 +5점까지 위로 줄 수 있고, 다축이 동시에 약하면 -5점까지 아래로 줄 수 있습니다 — 단, sub-score 자체를 그 방향으로 명확히 매긴 다음 종합점수를 조정하세요.

[점수 구간 가이드]
- 80+: 다수 축이 강하게 우호적이고 큰 리스크 없을 때
- 65~79: 주축이 우호적이지만 일부 약점/노이즈 섞임
- 50~64: 우호/주의 요소가 균형 — **진짜 혼조일 때만**
- 35~49: 분명한 약점 있음
- <35: 다수 부정 신호 누적

[필수 분석 관점]
1. 테마/섹터: 기업명, 시장, 뉴스 헤드라인으로 추정하되 불확실하면 명시.
2. 당일 등락 이유: 사용자가 바로 이해할 수 있게 "무엇 때문에 움직였는지"를 먼저 쓰고, 가격 변화·거래대금·뉴스/공시 근거·아직 설명되지 않는 부분을 분리.
3. 재무/밸류: 현재 PER, 선행 PER 산출 가능성, 향후 1~2년 영업이익 개선 근거, 동종업계 비교 필요성, PBR, BPS, 시총을 해석. EPS가 없으면 "PER 역산 EPS" 가능 여부와 한계를 언급.
4. 기술적 분석: 최근 고점/저점, 단기 추세, 현재가가 5/20/60/120일 이동평균 묶음 대비 어느 위치인지 종합. 볼린저밴드는 변동성/상단·하단 접근 여부를 추정.
5. 뉴스 분석: 뉴스 제목을 샅샅이 비교해 실적, 정책, 수주, 테마, 수급, 단순 노이즈 중 어느 쪽인지 구체적으로 분류. 테마는 기업 사업과 뉴스 근거가 맞물리는지 설명.
6. RSI와 기간 수익률: RSI(14), 5/20/60/120일 수익률을 반드시 언급하고 과열/침체/추세 지속 여부를 판단.
7. 실적 서프라이즈: 컨센서스 대비 상회/하회 근거가 뉴스나 데이터에 없으면 확인 필요라고 명시.
8. 최근 공시: 뉴스 헤드라인과 공시 목록에서 계약/수주/증자/지분 단서가 있는지 확인하되, 사용자에게 보이는 문장에는 날짜+공시명 원문을 그대로 붙이지 마세요.
9. 모멘텀: 단기 상승 지속력, 과열, 눌림, 재료 지속성, 최근 2주 외국인/기관 순매매 합계와 방향, 확인해야 할 다음 이벤트.
10. 리스크: 최소 3개 이상. "데이터 부족"도 리스크로 취급 가능.

[sections 구성 지침]
sections에는 아래 제목을 가능하면 모두 포함하세요. 각 body는 2~4개의 짧은 체크 문장으로 작성하세요.
- "CAN SLIM 체크": C/A/N/S/L/I/M 관점 중 데이터로 볼 수 있는 것과 부족한 것.
- "기술 지표": 이동평균, 볼린저밴드, 지지/저항, 변동성.
- "재무 지표": 현재 PER, 선행 PER 산출 가능성, 향후 1~2년 이익 전망, 동종업계 비교, PBR/BPS/시총/EPS와 한계.
- "기간 수익률": 5/20/60/120일 수익률과 추세 해석.
- "실적 서프라이즈": 컨센서스 상회/하회 확인 가능 여부.
- "최근 공시": 공시/계약/수주/증자/지분 변동 단서와 확인 필요 여부.
- "뉴스 재료": 최근 뉴스가 가격에 미칠 수 있는 방향과 노이즈 여부.
- "확인할 것": 다음 공시, 실적, 거래량, 뉴스 후속성 등 사용자가 체크할 항목.

[sections body 포맷 규칙 — 매우 중요]
화면에서 body가 구조화된 리스트로 표시됩니다. 아래 제목은 반드시 다음 형식으로 작성:
- "CAN SLIM 체크" body: C/A/N/S/L/I/M 7개 알파벳 각각을 한 줄씩 분리. 형식은 정확히 "C: 분기 EPS 개선 여부 ...\nA: 연 EPS 흐름 ...\nN: 신제품/신경영 ...\nS: 거래량/공급 ...\nL: 업계 리더십 ...\nI: 기관 매수 ...\nM: 시장 방향 ...". 각 줄은 알파벳 + ":" + 공백 + 내용. 데이터 부족하면 "C: 분기 EPS 데이터 확인 필요"처럼 짧게.
- "기술 지표" body: 라벨로 분리. 형식 "이동평균: ...\n볼린저밴드: ...\n지지/저항: ...\nRSI: ...". 각 항목 1문장씩.
- "확인할 것" body: 각 체크 포인트를 한 문장씩 줄바꿈으로 분리. 형식 "다음 분기 실적 발표일 확인.\n외국인 순매수 지속 여부 점검.\n자사주 소각 일정 확인.". 한 줄 = 하나의 체크.
- 위 규칙은 절대 깨지면 안 됩니다. 줄바꿈은 실제 "\n" 문자로 출력하세요.

[추가 분석 관점: 심화 리포트용]
11. 핵심 재료(catalysts): 최근 1~3개월 안에 가격을 움직일 만한 구체 재료(공시·계약·실적·정책·테마 이벤트)를 3~5개 골라 각각 종류·영향·시계·신뢰도·근거 설명을 분리해 작성. 단순 헤드라인 나열이 아니라 "왜 가격에 영향을 주는지"를 detail에 4~6문장으로 풍부하게 쓰세요. 구체 숫자나 공시/뉴스 인용을 포함하고, 영향 메커니즘(매출/이익/마진/수주잔고/임상단계 등)을 설명하세요.
12. 밸류에이션 비교(valuation): forwardPer와 sectorAveragePer는 반드시 숫자(또는 범위)로 채우세요. 입력 데이터에 Forward PER 또는 업종/동종 종목 평균 PER이 있으면 그 값을 그대로, 없으면 모델이 알고 있는 향후 1~2년 이익 추정과 업종 평균을 바탕으로 "약 11배(추정)"처럼 적습니다. peerComparison에는 동종업계 2~4개 종목의 trailing PER과 PBR을 숫자로 채우고, 정말 모르는 항목만 "N/A"로 두세요. perVerdict/pbrVerdict는 "낮음/적정/높음/확인필요" 중 하나, reasoning은 4~6문장.
13. 기술 상세(technicalDetail): 지지선·저항선은 추정 가격(예: "135,000원 근처")으로 쓰고 단정적이지 않게 "추정", "근처"를 붙이세요. 패턴은 보이지 않으면 "뚜렷한 패턴 미확인"이라고 쓰세요.
14. 시나리오(scenarios): 강세(bull)/기본(base)/약세(bear) 3개를 모두 작성하고 probability 세 값의 합이 정확히 1.0이 되도록 하세요. priceTarget은 "+8~12%" 또는 "165,000원 근처"처럼 범위/근사로 쓰고 단정적 목표가는 금지. narrative는 시나리오 트리거와 신호를 2~3문장.
15. 구조화 리스크(risksDetailed): 기존 risks 문자열 배열과 별개로 카테고리·심각도·발생가능성·대응법을 구조화해 3~5개 작성하세요. category는 재무/시장/규제/사업/기술/수급 중 하나, severity·probability는 높음/보통/낮음 중 하나.
16. 타이밍·액션(timing): action은 "분할매수/관망/매수보류/비중확대/비중축소/판단보류" 중 하나만 고르되, 점수와 신호 강도에 따라 **반드시 다양하게** 분포되도록 다음 가이드를 따르세요. **"분할매수"를 default로 선택하지 마세요** — 신호가 정말 우세할 때만 매수 액션을, 그 외에는 관망/매수보류를 우선 고려.
  - score ≥ 80: **비중확대** (재료 신뢰도 높음 + 추세 우호 + 리스크 작음, 세 조건 모두 충족 시)
  - score 70~79: **분할매수** (주축 신호 우호적이고 단기 변동만 우려될 때) 또는 **비중확대** (재료 신뢰도 매우 높을 때)
  - score 60~69: **매수보류**가 기본 (양호하지만 단기 과열·고PER 우려), 모멘텀+재료가 모두 명확히 우세하면 **분할매수**
  - score 50~59: **관망**이 기본 (혼조), 약점이 두드러지면 **매수보류**
  - score 40~49: **매수보류** 또는 **비중축소** (약점이 더 명확하면 비중축소)
  - score 30~39: **비중축소**
  - score < 30: **비중축소** (즉시 대응)
  - 핵심 데이터(가격/실적/뉴스 중 2개 이상) 결측: **판단보류**

  **분포 강제**: 같은 점수 구간에서도 신호 강도에 따라 다른 액션을 선택하세요. 70~79 구간이라고 무조건 "분할매수" 출력 금지 — 신호가 매우 강하면 "비중확대"를, 단기 우려가 강하면 "매수보류"를 골라 다양성을 확보하세요.
actionReason은 "단정적 매수·매도 권유"로 들리지 않되 방향은 명확히 드러나도록 작성하세요. shortTerm은 1~2주, midTerm은 1~3개월 관점으로 2~3문장씩.

반드시 아래 JSON 객체만 출력하세요. 첫 글자는 {, 마지막 글자는 } 이어야 합니다. 마크다운 코드블록, 앞뒤 설명, 주석 금지.
{
  "companyOverview": "이 회사가 어떤 사업을 하는지 3~4문장으로 소개. 다음을 포함하세요: (1) 주력 사업/제품 — 매출 비중 큰 사업부문이나 대표 제품 1~3개 (2) 산업 내 포지션 — 시장점유율·경쟁사 대비 위치·강점 (3) 주요 고객사·수요처 또는 사업 모델 핵심 (4) 최근 사업 변화나 신성장 동력이 있으면 한 문장. DART 사업 스토리 근거와 종목명/섹터 정보를 적극 활용하세요. 단정적 미래 표현 금지. 마지막 문장은 사실적 회사 정보로 끝내세요.",
  "summary": "5~6개의 짧은 문장으로 구성한 풍부한 핵심 요약. 각 문장 끝에 반드시 '\\n\\n'(두 줄바꿈)을 넣어 사용자 화면에서 문단 단위로 보이게 하세요. 다음 요소를 한 문장씩 차례로 작성: (1) 최근 등락의 가장 큰 배경 — 어떤 재료·실적·테마가 가격을 움직였는지 구체적으로 (2) 밸류에이션 위치 — 현재 PER/PBR이 업종 평균(숫자) 대비 어디인지 (3) 기술/모멘텀 — 추세 단계와 과열 여부 (4) 가장 중요한 리스크 1개 (5) 다음에 확인해야 할 포인트. **첫 문장 맨 앞에 '핵심 원인은', '중립 성향의 리포트입니다', '본 리포트는', '이 분석은' 같은 메타 코멘트 절대 금지** — 바로 본론으로 들어가세요. 형식적이지 않게 자연스러운 한국어로 작성.",
  "subScores": {
    "priceTrend": 0,
    "newsImpact": 0,
    "fundamentals": 0,
    "momentumFlow": 0,
    "riskLevel": 0
  },
  "score": 0,
  "scoreLabel": "점수 구간 해석. 우호, 중립, 주의 중 하나만 고르고 그 이유를 1문장",
  "theme": "핵심 테마 1~3개만 사용자에게 보이는 문장으로 작성. 근거 설명보다 어떤 테마인지가 먼저 보이게 작성",
  "sector": "섹터 분석. 업종/산업 분류와 확실성",
  "todayReason": "최근 등락 이유 상세 분석. 4~6문장 분량으로 작성하세요. 첫 문장은 '핵심 원인은' 같은 라벨 없이 사용자가 바로 이해할 가격 변동 배경으로 시작하세요. 이어서 제품/실적/테마/정책 스토리 맥락, 뉴스·공시의 의미 요약, 거래량/가격 반응 강도를 자연스러운 문단으로 설명하세요. 제목·날짜 원문을 그대로 붙이지 말고 의미로 풀어 쓰세요. **'미확인 변수', '확인이 필요한 부분' 같은 placeholder 문장 금지**. 단순 헤드라인 반복이 아니라 사용자가 '왜 움직였는지'를 입체적으로 이해할 수 있게 작성.",
  "fundamentals": "실적/밸류에이션 1문단 요약 3~4문장. 상세는 valuation 객체에 작성하세요.",
  "technical": "기술 분석 1문단 요약 3~4문장. 상세는 technicalDetail 객체에 작성하세요.",
  "news": "최근 뉴스 흐름의 방향성을 2~3문장으로 요약. 헤드라인을 그대로 나열하지 말고, 어떤 흐름이 우세한지(긍정/부정/혼조), 어떤 테마가 주도하는지, 어떤 점이 노이즈인지를 사용자가 한눈에 보게 정리. 예: '2차전지 양극재 신규 수주와 IRA 보조금 확대 기대가 우세한 흐름이지만, 단기 과열을 우려하는 증권사 코멘트도 일부 섞여 있습니다.'",
  "momentum": "모멘텀 분석 3~4문장. 단기 흐름, 과열/눌림, 재료 지속성, 수급 보강",
  "peerPerAverage": "동종업계 평균 PER을 숫자로 한 줄 요약. 예: '반도체 업종 평균 PER 약 14배(추정)'. 절대 '확인 필요'만 단독으로 쓰지 마세요.",
  "themePeers": ["같은 테마 종목명1", "같은 테마 종목명2", "같은 테마 종목명3"],
  "catalysts": [
    {
      "title": "재료 한 줄 제목. 사용자가 바로 이해할 핵심 문장 (예: 'LG엔솔향 NCM 양극재 1.8조 4년 공급계약')",
      "kind": "공시|뉴스|이벤트|실적|수급|루머 중 하나",
      "impact": "강한긍정|긍정|중립|부정|강한부정 중 하나",
      "timeline": "단기|중기|장기 중 하나",
      "confidence": "높음|보통|낮음 중 하나",
      "detail": "4~6문장 분량의 풍부한 분석. 다음을 포함: (1) 이 재료가 왜 가격에 영향을 주는지 — 매출/이익/마진 구조에 어떻게 작용하는지 (2) 구체 숫자나 공시명/뉴스 헤드라인 인용 (3) 영향이 얼마나 지속될지 (4) 비교/사례 — 비슷한 과거 케이스나 동종 업종 사례 (5) 변수/제약 — 신뢰도가 보통/낮음이면 무엇이 걸리는지. 단순 헤드라인 반복은 금지."
    }
  ],
  "valuation": {
    "perVerdict": "낮음|적정|높음|확인필요 중 하나",
    "pbrVerdict": "낮음|적정|높음|확인필요 중 하나",
    "forwardPer": "선행 PER. 입력 데이터 Forward PER이 있으면 그 값(예: '12.4배'). 없으면 모델 추정 (예: '약 11배(추정, 향후 1~2년 EPS 개선 가정)')",
    "sectorAveragePer": "해당 종목 업종/산업의 평균 PER을 숫자로. 예: '반도체 업종 약 14배(추정)' 또는 '10~14배 범위'. '확인 필요'만 단독 사용 금지.",
    "peerComparison": [
      {"name": "비교 종목명1", "per": "PER 숫자 (예: '17.5' 또는 '18배 안팎'). 정말 불가능할 때만 'N/A'", "pbr": "PBR 숫자"}
    ],
    "reasoning": "4~6문장. 현재 PER/PBR이 동종업계 대비 어디에 있는지(숫자 인용), 선행 PER 관점 추가 해석, 적정/할인/프리미엄 판단 근거, 한계."
  },
  "technicalDetail": {
    "maPosition": "5·20·60·120일 이동평균선 종합 위치 한 줄",
    "rsiVerdict": "RSI 수치와 과열/침체 해석",
    "bollingerVerdict": "볼린저밴드 위치와 변동성 한 줄",
    "support": "추정 지지선 가격 또는 확인 필요",
    "resistance": "추정 저항선 가격 또는 확인 필요",
    "pattern": "감지된 캔들/차트 패턴 또는 뚜렷한 패턴 미확인",
    "reasoning": "현재 추세, 변동성, 진입/대응 관점 3~5문장"
  },
  "scenarios": {
    "bull": {"trigger": "강세 시나리오 트리거 한 줄", "priceTarget": "+N% 또는 가격 범위 또는 확인 필요", "probability": 0.0, "narrative": "현실화 조건과 신호 2~3문장"},
    "base": {"trigger": "...", "priceTarget": "...", "probability": 0.0, "narrative": "..."},
    "bear": {"trigger": "...", "priceTarget": "...", "probability": 0.0, "narrative": "..."}
  },
  "risksDetailed": [
    {"category": "재무|시장|규제|사업|기술|수급", "severity": "높음|보통|낮음", "probability": "높음|보통|낮음", "description": "리스크 설명 1~2문장", "mitigant": "투자자가 관찰/대응할 수 있는 방법 1~2문장"}
  ],
  "timing": {
    "shortTerm": "1~2주 전망 2~3문장",
    "midTerm": "1~3개월 전망 2~3문장",
    "action": "분할매수|관망|매수보류|비중확대|비중축소|판단보류 중 하나",
    "actionReason": "그렇게 판단한 이유 2~3문장. 단정적 매수·매도 표현 금지"
  },
  "risks": ["구체적 리스크1", "구체적 리스크2", "구체적 리스크3"],
  "sections": [
    {"title": "CAN SLIM 체크", "body": "C/A/N/S/L/I/M 관점 체크"},
    {"title": "기술 지표", "body": "이동평균/볼린저밴드/지지저항 체크"},
    {"title": "확인할 것", "body": "다음에 볼 데이터와 이벤트"}
  ]
}`;

    const openAiApiKey = (OPENAI_API_KEY.value() || '').trim();
    if (!openAiApiKey) {
      console.warn('[generateStockAiAnalysis] OPENAI_API_KEY is empty');
      throw new HttpsError('internal', 'AI 분석 설정이 완료되지 않았습니다.');
    }

    let response;
    try {
      response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-5-mini',
        input: prompt,
        max_output_tokens: 10000,
        reasoning: { effort: 'medium' },
        text: {
          verbosity: 'high',
          format: {
            type: 'json_schema',
            name: 'stock_ai_analysis',
            strict: true,
            schema: {
              type: 'object',
              additionalProperties: false,
              required: [
                'companyOverview',
                'summary',
                'subScores',
                'score',
                'scoreLabel',
                'theme',
                'sector',
                'todayReason',
                'fundamentals',
                'technical',
                'news',
                'momentum',
                'peerPerAverage',
                'themePeers',
                'risks',
                'sections',
                'catalysts',
                'valuation',
                'technicalDetail',
                'scenarios',
                'risksDetailed',
                'timing',
              ],
              properties: {
                companyOverview: { type: 'string' },
                summary: { type: 'string' },
                subScores: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['priceTrend', 'newsImpact', 'fundamentals', 'momentumFlow', 'riskLevel'],
                  properties: {
                    priceTrend: { type: 'number', minimum: 0, maximum: 100 },
                    newsImpact: { type: 'number', minimum: 0, maximum: 100 },
                    fundamentals: { type: 'number', minimum: 0, maximum: 100 },
                    momentumFlow: { type: 'number', minimum: 0, maximum: 100 },
                    riskLevel: { type: 'number', minimum: 0, maximum: 100 },
                  },
                },
                score: { type: 'number', minimum: 0, maximum: 100 },
                scoreLabel: { type: 'string' },
                theme: { type: 'string' },
                sector: { type: 'string' },
                todayReason: { type: 'string' },
                fundamentals: { type: 'string' },
                technical: { type: 'string' },
                news: { type: 'string' },
                momentum: { type: 'string' },
                peerPerAverage: { type: 'string' },
                themePeers: {
                  type: 'array',
                  maxItems: 8,
                  items: { type: 'string' },
                },
                risks: {
                  type: 'array',
                  maxItems: 5,
                  items: { type: 'string' },
                },
                sections: {
                  type: 'array',
                  maxItems: 8,
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    required: ['title', 'body'],
                    properties: {
                      title: { type: 'string' },
                      body: { type: 'string' },
                    },
                  },
                },
                catalysts: {
                  type: 'array',
                  maxItems: 6,
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    required: ['title', 'kind', 'impact', 'timeline', 'confidence', 'detail'],
                    properties: {
                      title: { type: 'string' },
                      kind: {
                        type: 'string',
                        enum: ['공시', '뉴스', '이벤트', '실적', '수급', '루머'],
                      },
                      impact: {
                        type: 'string',
                        enum: ['강한긍정', '긍정', '중립', '부정', '강한부정'],
                      },
                      timeline: {
                        type: 'string',
                        enum: ['단기', '중기', '장기'],
                      },
                      confidence: {
                        type: 'string',
                        enum: ['높음', '보통', '낮음'],
                      },
                      detail: { type: 'string' },
                    },
                  },
                },
                valuation: {
                  type: 'object',
                  additionalProperties: false,
                  required: [
                    'perVerdict',
                    'pbrVerdict',
                    'forwardPer',
                    'sectorAveragePer',
                    'peerComparison',
                    'reasoning',
                  ],
                  properties: {
                    perVerdict: {
                      type: 'string',
                      enum: ['낮음', '적정', '높음', '확인필요'],
                    },
                    pbrVerdict: {
                      type: 'string',
                      enum: ['낮음', '적정', '높음', '확인필요'],
                    },
                    forwardPer: { type: 'string' },
                    sectorAveragePer: { type: 'string' },
                    peerComparison: {
                      type: 'array',
                      maxItems: 5,
                      items: {
                        type: 'object',
                        additionalProperties: false,
                        required: ['name', 'per', 'pbr'],
                        properties: {
                          name: { type: 'string' },
                          per: { type: 'string' },
                          pbr: { type: 'string' },
                        },
                      },
                    },
                    reasoning: { type: 'string' },
                  },
                },
                technicalDetail: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['maPosition', 'rsiVerdict', 'bollingerVerdict', 'support', 'resistance', 'pattern', 'reasoning'],
                  properties: {
                    maPosition: { type: 'string' },
                    rsiVerdict: { type: 'string' },
                    bollingerVerdict: { type: 'string' },
                    support: { type: 'string' },
                    resistance: { type: 'string' },
                    pattern: { type: 'string' },
                    reasoning: { type: 'string' },
                  },
                },
                scenarios: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['bull', 'base', 'bear'],
                  properties: {
                    bull: {
                      type: 'object',
                      additionalProperties: false,
                      required: ['trigger', 'priceTarget', 'probability', 'narrative'],
                      properties: {
                        trigger: { type: 'string' },
                        priceTarget: { type: 'string' },
                        probability: { type: 'number', minimum: 0, maximum: 1 },
                        narrative: { type: 'string' },
                      },
                    },
                    base: {
                      type: 'object',
                      additionalProperties: false,
                      required: ['trigger', 'priceTarget', 'probability', 'narrative'],
                      properties: {
                        trigger: { type: 'string' },
                        priceTarget: { type: 'string' },
                        probability: { type: 'number', minimum: 0, maximum: 1 },
                        narrative: { type: 'string' },
                      },
                    },
                    bear: {
                      type: 'object',
                      additionalProperties: false,
                      required: ['trigger', 'priceTarget', 'probability', 'narrative'],
                      properties: {
                        trigger: { type: 'string' },
                        priceTarget: { type: 'string' },
                        probability: { type: 'number', minimum: 0, maximum: 1 },
                        narrative: { type: 'string' },
                      },
                    },
                  },
                },
                risksDetailed: {
                  type: 'array',
                  maxItems: 6,
                  items: {
                    type: 'object',
                    additionalProperties: false,
                    required: ['category', 'severity', 'probability', 'description', 'mitigant'],
                    properties: {
                      category: {
                        type: 'string',
                        enum: ['재무', '시장', '규제', '사업', '기술', '수급'],
                      },
                      severity: {
                        type: 'string',
                        enum: ['높음', '보통', '낮음'],
                      },
                      probability: {
                        type: 'string',
                        enum: ['높음', '보통', '낮음'],
                      },
                      description: { type: 'string' },
                      mitigant: { type: 'string' },
                    },
                  },
                },
                timing: {
                  type: 'object',
                  additionalProperties: false,
                  required: ['shortTerm', 'midTerm', 'action', 'actionReason'],
                  properties: {
                    shortTerm: { type: 'string' },
                    midTerm: { type: 'string' },
                    action: {
                      type: 'string',
                      enum: ['분할매수', '관망', '매수보류', '비중확대', '비중축소', '판단보류'],
                    },
                    actionReason: { type: 'string' },
                  },
                },
              },
            },
          },
        },
      }),
      });
    } catch (e) {
      console.warn('[generateStockAiAnalysis] OpenAI request failed:', e?.message || e);
      throw new HttpsError('internal', 'AI 분석 생성에 실패했습니다. 잠시 후 다시 시도해주세요.');
    }

    const body = await response.json().catch(() => null);
    if (!response.ok) {
      const detail = body?.error?.message || response.statusText || 'OpenAI API request failed';
      console.warn('[generateStockAiAnalysis] OpenAI error:', detail);
      throw new HttpsError('internal', 'AI 분석 생성에 실패했습니다. 잠시 후 다시 시도해주세요.');
    }

    const text = (body?.output_text || (body?.output || [])
      .flatMap((item) => item?.content || [])
      .map((part) => part?.text || '')
      .filter(Boolean)
      .join('\n'))
      .trim();

    // 응답이 비었거나 추론 토큰만 소진된 채 끝난 경우 → 잘못된 fallback 페이로드를
    // 저장하는 대신 명확히 실패시켜 쿼터를 환불받게 한다.
    if (!text) {
      const status = body?.status || '';
      const incomplete = body?.incomplete_details?.reason || '';
      console.warn(
        `[generateStockAiAnalysis] empty OpenAI output (status=${status}, incomplete=${incomplete})`
      );
      throw new HttpsError('internal', 'AI 분석 응답이 비어있어요. 잠시 후 다시 시도해주세요.');
    }

    let payload;
    try {
      const parsed = extractJsonObject(text);
      payload = attachStockAnalysisSources(
        applyNaverValuationFallback(
          normalizeStockAnalysisPayload(parsed),
          naverValuation
        ),
        sourcePayload
      );
    } catch (e) {
      console.warn('[generateStockAiAnalysis] JSON parse failed:', e?.message || e);
      console.warn('[generateStockAiAnalysis] Raw AI response:', clampStockAnalysisInput(text, 1200));
      payload = attachStockAnalysisSources(
        applyNaverValuationFallback(
          fallbackStockAnalysisPayload(text),
          naverValuation
        ),
        sourcePayload
      );
    }

    // sub-score 가중합으로 종합 점수 재계산. 모델이 sub-score는 분포 있게
    // 매겼는데 종합만 "안전한 60대"로 도망친 경우 가중합으로 교체.
    if (payload) {
      const before = payload.score;
      payload = recomputeScoreFromSubScores(payload);
      if (payload.score !== before) {
        console.log(
          `[generateStockAiAnalysis] sub-score recompute ${ticker}: ` +
          `model=${before} -> ${payload.score} ` +
          `(sub: ${JSON.stringify(payload.subScores)})`,
        );
      }
    }

    // 결정론적 valuation 보정.
    // 트레일링 PER만으로 점수를 깎는 모델 편향을 줄이기 위해 forward PER /
    // EPS 시계열 기반 valuation 점수를 계산하되, **종합점수가 아닌
    // fundamentals sub-score에 흡수**시킨다. 그러면 화면에 보이는
    // "sub-score × 가중치 = 종합점수" 식이 항상 성립해 괴리감이 사라진다.
    // valuation 보정의 본질이 펀더멘털 신호 보정이므로 의미적으로도 맞다.
    try {
      const trailingPerNum = Number.isFinite(Number(fundamentals?.per))
        ? Number(fundamentals.per)
        : null;
      const brokerTargets = Array.isArray(naverValuation?.reports)
        ? naverValuation.reports
            .map((r) => Number(r?.targetPrice))
            .filter((n) => Number.isFinite(n) && n > 0)
        : [];
      const currentPriceNum = Number(price?.currentPrice);
      const dartFinancials = Array.isArray(dartContext?.financials)
        ? dartContext.financials
        : [];
      const valuationCalc = computeValuationDeterministicScore({
        trailingPer: trailingPerNum,
        forwardPer: Number.isFinite(providedForwardPer) ? providedForwardPer : null,
        sectorPer: Number.isFinite(providedSectorAveragePer) ? providedSectorAveragePer : null,
        epsTimeline,
        brokerTargets,
        currentPrice: Number.isFinite(currentPriceNum) ? currentPriceNum : null,
        dartFinancials,
      });
      const sub = payload?.subScores;
      if (
        valuationCalc &&
        Number.isFinite(valuationCalc.score) &&
        sub &&
        Number.isFinite(Number(sub.fundamentals))
      ) {
        const signalCount = valuationCalc.signalCount;
        // 신호 강도 → fundamentals 보정 강도 (기존 blendStockAnalysisScore 가중치 표 차용)
        const w =
          signalCount >= 4 ? 0.4
          : signalCount >= 3 ? 0.32
          : signalCount >= 2 ? 0.22
          : signalCount >= 1 ? 0.12
          : 0;
        if (w > 0) {
          const oldFund = Math.round(Number(sub.fundamentals));
          const newFund = Math.round(
            Math.max(0, Math.min(100, oldFund * (1 - w) + valuationCalc.score * w))
          );
          if (newFund !== oldFund) {
            payload.subScores.fundamentals = newFund;
            // 종합점수도 sub × 가중치 가중평균으로 다시 계산.
            const weights = {
              priceTrend: 0.25,
              newsImpact: 0.20,
              fundamentals: 0.20,
              momentumFlow: 0.20,
              riskLevel: 0.15,
            };
            let total = 0;
            let weightSum = 0;
            for (const [k, ww] of Object.entries(weights)) {
              const v = Number(payload.subScores[k]);
              if (Number.isFinite(v) && v >= 0 && v <= 100) {
                total += v * ww;
                weightSum += ww;
              }
            }
            if (weightSum >= 0.5) {
              const newTotal = Math.round(total / weightSum);
              const beforeTotal = payload.score;
              payload.score = newTotal;
              payload.scoreLabel = reconcileScoreLabel(payload.scoreLabel, newTotal);
              console.log(
                `[generateStockAiAnalysis] valuation absorbed into fundamentals ${ticker}: ` +
                `fund=${oldFund}->${newFund} val=${valuationCalc.score} ` +
                `signals=${signalCount} w=${w.toFixed(2)} ` +
                `total=${beforeTotal}->${newTotal} ` +
                `(${valuationCalc.signals.join(', ')})`,
              );
            }
          }
        }
      }
    } catch (e) {
      console.warn('[generateStockAiAnalysis] valuation absorb failed:', e?.message || e);
    }

    // 최종 score 확정 후 timing.action이 점수 밴드와 어긋났는지 검사.
    // "70점인데 매수보류", "65점인데 분할매수" 같은 어긋남을 막는다.
    try {
      if (payload?.timing && Number.isFinite(payload?.score)) {
        const before = payload.timing.action;
        const after = reconcileAction(before, payload.score);
        if (after && after !== before) {
          payload.timing.action = after;
          console.log(
            `[generateStockAiAnalysis] action reconciled ${ticker}: ` +
            `score=${payload.score} ${before} -> ${after}`,
          );
        }
      }
    } catch (e) {
      console.warn('[generateStockAiAnalysis] action reconcile failed:', e?.message || e);
    }

    // 클라이언트가 백그라운드/연결 종료 상태여도 결과가 유실되지 않도록
    // Firestore에 직접 저장한다. 클라이언트는 같은 문서를 listen 해서
    // 함수 응답과 Firestore snapshot 중 먼저 도착하는 쪽을 사용한다.
    const analysisId = `${market.toUpperCase()}_${ticker.toUpperCase()}`;
    try {
      // 분석 시점 가격 스냅샷 — 카드에서 "분석 후 +X.X%" 비교에 사용
      const baselinePrice = Number(price.currentPrice);
      const snapshot = {
        ...payload,
        ticker,
        name,
        market,
        updatedAt: new Date(),
      };
      if (Number.isFinite(baselinePrice) && baselinePrice > 0) {
        snapshot.analysisPrice = baselinePrice;
      }
      await getFirestore()
        .collection('users')
        .doc(request.auth.uid)
        .collection('stock_ai_analyses')
        .doc(analysisId)
        .set(snapshot, { merge: true });
    } catch (e) {
      console.warn('[generateStockAiAnalysis] Firestore save failed:', e?.message || e);
    }

    // 분석 완료 푸시 알림 — 클라이언트가 백그라운드/종료 상태여도 결과를 알린다.
    try {
      const db = getFirestore();
      const uid = request.auth.uid;
      const tokensSnap = await db
        .collection('fcm_tokens')
        .where('uid', '==', uid)
        .get();
      const tokens = tokensSnap.docs
        .map((d) => d.data().token)
        .filter((t) => typeof t === 'string' && t.length > 0);

      if (tokens.length > 0) {
        const score = Number.isFinite(Number(payload?.score)) ? Math.round(Number(payload.score)) : null;
        const scoreLabel = (payload?.scoreLabel || '').toString().trim();
        const body = score !== null
          ? `${name} · ${score}점${scoreLabel ? ` (${scoreLabel})` : ''}`
          : `${name} 분석이 준비되었습니다.`;

        const response = await getMessaging().sendEachForMulticast({
          tokens,
          notification: {
            title: 'AI 분석이 완료되었어요',
            body,
          },
          data: {
            type: 'ai_analysis_complete',
            analysisId,
            ticker,
            market,
            name,
          },
          android: {
            priority: 'high',
            notification: { channelId: 'default', sound: 'default' },
          },
          apns: {
            payload: { aps: { sound: 'default' } },
          },
        });

        // 만료된 토큰 정리
        const invalidTokens = [];
        response.responses.forEach((r, i) => {
          if (!r.success) {
            const code = r.error?.code || '';
            if (
              code === 'messaging/invalid-registration-token' ||
              code === 'messaging/registration-token-not-registered'
            ) {
              invalidTokens.push(tokens[i]);
            }
          }
        });
        if (invalidTokens.length > 0) {
          await Promise.all(
            invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
          );
        }
      }
    } catch (e) {
      console.warn('[generateStockAiAnalysis] FCM notify failed:', e?.message || e);
    }

    return payload;
    } catch (err) {
      await refundStockAiAnalysisQuota(request.auth.uid, quotaDateKey, requestId);
      throw err;
    }
  }
);

// ── 경제·실적·IPO 캘린더 동기화 (하루 2회: 06:30 / 18:30 KST) ────────────────
exports.syncMarketCalendar = onSchedule(
  {
    schedule: '30 6,18 * * *',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
    timeoutSeconds: 120,
    secrets: [FINNHUB_API_KEY, FRED_API_KEY],
  },
  async () => {
    await runCalendarSync(getFirestore(), {
      finnhubKey: FINNHUB_API_KEY.value() || null,
      fredKey: FRED_API_KEY.value() || null,
    });
  }
);

// ── 당일 주요 일정 푸시 (매일 08:00 KST) ─────────────────────────────────────
exports.notifyMarketCalendarToday = onSchedule(
  {
    schedule: '0 8 * * *',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
    timeoutSeconds: 60,
  },
  async () => {
    await notifyTodayEvents(getFirestore());
  }
);

// ── 수동 트리거 (테스트용) ───────────────────────────────────────────────────
exports.syncMarketCalendarNow = onRequest(
  { region: 'asia-northeast3', timeoutSeconds: 120, secrets: [FINNHUB_API_KEY, FRED_API_KEY] },
  async (req, res) => {
    try {
      const result = await runCalendarSync(getFirestore(), {
        finnhubKey: FINNHUB_API_KEY.value() || null,
        fredKey: FRED_API_KEY.value() || null,
      });
      if (req.query.notify === '1') {
        result.notify = await notifyTodayEvents(getFirestore());
      }
      res.json({ ok: true, ...result });
    } catch (e) {
      console.error('[syncMarketCalendarNow] 실패:', e);
      res.status(500).json({ ok: false, error: e?.message || String(e) });
    }
  }
);
