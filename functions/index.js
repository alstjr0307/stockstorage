const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { auth } = require('firebase-functions/v1');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getMessaging } = require('firebase-admin/messaging');
const { getFirestore } = require('firebase-admin/firestore');
const https = require('https');
const axios = require('axios');
const cheerio = require('cheerio');
const WebSocket = require('ws');
const {
  crawlDailyInvestorFlow,
  collectDailyInvestorFlow,
  saveDailyInvestorFlow,
} = require('./investor_flow');

initializeApp();
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

// ?Ä?Ä ?†Í∑ú Í∞Ä?ÖÏûê ??Í¥ÄÎ¶¨Ïûê?êÍ≤å ?åÎ¶º ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.notifyAdminOnNewUser = auth.user().onCreate(async (user) => {
  const db = getFirestore();

  // config/admin Î¨∏ÏÑú?êÏÑú Í¥ÄÎ¶¨Ïûê UID Ï°∞Ìöå
  const adminSnap = await db.collection('config').doc('admin').get();
  const adminUid = adminSnap.data()?.uid;
  if (!adminUid) return;

  // Í¥ÄÎ¶¨Ïûê FCM ?†ÌÅ∞ Ï°∞Ìöå
  const tokensSnap = await db.collection('fcm_tokens')
    .where('uid', '==', adminUid).get();
  const tokens = tokensSnap.docs
    .map((d) => d.data().token)
    .filter((t) => typeof t === 'string' && t.length > 0);
  if (tokens.length === 0) return;

  const displayName = user.displayName || user.email || '?????ÜÏùå';
  const provider = user.providerData?.[0]?.providerId ?? 'unknown';

  await getMessaging().sendEachForMulticast({
    notification: {
      title: '?ë§ ?†Í∑ú Í∞Ä?ÖÏûê',
      body: `${displayName} (${provider})`,
    },
    android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
    apns: { payload: { aps: { sound: 'default' } } },
    tokens,
  });
});

// ?Ä?Ä ?ìÍ? ?åÎ¶º (???ìÍ? ??Í∞ôÏ? Ï¢ÖÎ™© ?ìÍ? ?ëÏÑ±?êÎì§?êÍ≤å ?∏Ïãú) ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.sendCommentNotification = onDocumentCreated(
  { document: 'stock_picks/{pickId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, text } = data;
    const { pickId } = event.params;
    const db = getFirestore();

    // Ï¢ÖÎ™© ?¥Î¶Ñ Ï°∞Ìöå
    const pickSnap = await db.collection('stock_picks').doc(pickId).get();
    const pickName = pickSnap.data()?.name ?? 'Ï¢ÖÎ™©';

    // Í∞ôÏ? Ï¢ÖÎ™©???ìÍ? ???§Î•∏ ?†Ï? uid ?òÏßë
    const commentsSnap = await db
      .collection('stock_picks').doc(pickId).collection('comments').get();
    const uids = new Set(
      commentsSnap.docs
        .map((d) => d.data().uid)
        .filter((u) => u && u !== commenterUid)
    );
    if (uids.size === 0) return;

    // uid ??FCM ?†ÌÅ∞ Ï°∞Ìöå
    const tokensSnap = await db.collection('fcm_tokens').get();
    const tokens = tokensSnap.docs
      .filter((d) => uids.has(d.data().uid))
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '?ÑÍµ∞Í∞Ä';
    const preview = text?.length > 30 ? text.slice(0, 30) + '...' : text;

    // FCM Î∞úÏÜ°
    const chunkSize = 500;
    const invalidTokens = [];
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: `?í¨ ${pickName} ???ìÍ?`,
          body: `${senderName}: ${preview}`,
        },
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

    // ÎßåÎ£å ?†ÌÅ∞ ?ïÎ¶¨
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }
  }
);

// ?Ä?Ä ?êÏú†Í≤åÏãú???ìÍ? ?åÎ¶º (???ìÍ? ??Í≤åÏãúÍ∏Ä ?ëÏÑ±?êÏóêÍ≤??∏Ïãú) ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.sendPostCommentNotification = onDocumentCreated(
  { document: 'posts/{postId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { postId } = event.params;
    const db = getFirestore();

    // Í≤åÏãúÍ∏Ä Ï°∞Ìöå ???ëÏÑ±??UID ?ïÏù∏
    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;

    const postData = postSnap.data();
    const authorUid = postData?.uid;

    // ?êÍ∏∞ Í∏Ä???êÍ∏∞Í∞Ä ?ìÍ? ???åÎ¶º ?ÜÏùå
    if (!authorUid || authorUid === commenterUid) return;

    // ?ëÏÑ±??FCM ?†ÌÅ∞ Ï°∞Ìöå
    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid).get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '?ÑÍµ∞Í∞Ä';
    const preview = content?.length > 30 ? content.slice(0, 30) + '...' : content;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: `?í¨ ??Í∏Ä???ìÍ????¨Î†∏?¥Ïöî`,
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
  }
);

// ?Ä?Ä ?®ÏΩîÏßÄ?? 30Î∂ÑÎßà???êÌé®ÏΩîÎ¶¨??Ï£ºÏãùÍ≤åÏãú??Í∏Ä ???òÏßë ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
// ¶°¶° ∏≈∏≈¿œ¡ˆ ¥Ò±€ æÀ∏≤ (ªı ¥Ò±€ °Ê ∏≈∏≈¿œ¡ˆ ¿€º∫¿⁄ø°∞‘ «™Ω√) ¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°¶°
exports.sendJournalCommentNotification = onDocumentCreated(
  { document: 'trading_journal/{journalId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { journalId } = event.params;
    const db = getFirestore();

    // ∏≈∏≈¿œ¡ˆ ¡∂»∏ π◊ ¿€º∫¿⁄ UID »Æ¿Œ
    const journalSnap = await db.collection('trading_journal').doc(journalId).get();
    if (!journalSnap.exists) return;

    const journalData = journalSnap.data();
    const authorUid = journalData?.uid;

    // ¿⁄±‚ ±€ø° ¿⁄±‚ ¥Ò±€¿∫ æÀ∏≤ ¡¶ø‹
    if (!authorUid || authorUid === commenterUid) return;

    // ¿€º∫¿⁄ FCM ≈‰≈´ ¡∂»∏
    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid).get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '¿Õ∏Ì';
    const preview = content?.length > 30 ? content.slice(0, 30) + '°¶' : content;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: '?? ∏≈∏≈¿œ¡ˆ ¥Ò±€¿Ã ¥ﬁ∑»æÓø‰',
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
  }
);
exports.crawlFemcoIndex = onSchedule(
  { schedule: 'every 30 minutes', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const cutoff = new Date(now.getTime() - 30 * 60 * 1000); // 30Î∂???

    try {
      const headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'ko-KR,ko;q=0.9',
        'Referer': 'https://www.fmkorea.com/',
      };

      // ?êÌé®ÏΩîÎ¶¨??Ï£ºÏãù Í≤åÏãú??1~3?òÏù¥ÏßÄ ?òÏßë
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
          // ?úÍ∞Ñ ?åÏã±: "HH:MM" ?ïÏãù?¥Î©¥ ?§Îäò ?†ÏßúÎ°? "MM.DD" ?¥Î©¥ Í≥ºÍ±∞
          if (!timeText) return;

          let postDate = null;
          if (/^\d{2}:\d{2}$/.test(timeText)) {
            const [h, m] = timeText.split(':').map(Number);
            postDate = new Date(now);
            postDate.setHours(h, m, 0, 0);
          } else {
            // MM.DD ?ïÏãù?¥Î©¥ ?§ÎäòÎ≥¥Îã§ Í≥ºÍ±∞
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

      // Firestore ?Ä??
      const slotKey = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}_${String(now.getHours()).padStart(2,'0')}:${now.getMinutes() < 30 ? '00' : '30'}`;

      await db.collection('board_index').doc('femco')
        .collection('logs').doc(slotKey).set({
          count,
          timestamp: now,
          slot: slotKey,
        });

      // ÏµúÏã†Í∞?Í∞±Ïã†
      await db.collection('board_index').doc('femco').set({
        count,
        updatedAt: now,
        slot: slotKey,
      }, { merge: true });

    } catch (_) {
    }
  }
);

// ?Ä?Ä Ïπ¥Ïπ¥???∏Ï¶ùÏΩîÎìú ??Firebase Ïª§Ïä§?Ä ?†ÌÅ∞ (??admin?? ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.kakaoAuthCode = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const { code, redirectUri } = request.data;
    if (!code || !redirectUri) {
      throw new HttpsError('invalid-argument', 'code?Ä redirectUriÍ∞Ä ?ÑÏöî?©Îãà??');
    }

    // ?∏Ï¶ùÏΩîÎìú ???°ÏÑ∏???†ÌÅ∞
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

    // ?°ÏÑ∏???†ÌÅ∞ ???†Ï? ?ïÎ≥¥
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

// ?Ä?Ä Ïπ¥Ïπ¥??Ïª§Ïä§?Ä ?†ÌÅ∞ Î∞úÍ∏â ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
// ?¥Îùº?¥Ïñ∏?∏Ïóê??Ïπ¥Ïπ¥???°ÏÑ∏???†ÌÅ∞??Î≥¥ÎÇ¥Î©??úÎ≤Ñ?êÏÑú Í≤ÄÏ¶???Firebase Ïª§Ïä§?Ä ?†ÌÅ∞ Î∞òÌôò
exports.createKakaoCustomToken = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const { accessToken } = request.data;
    if (!accessToken) {
      throw new HttpsError('invalid-argument', 'accessToken???ÑÏöî?©Îãà??');
    }

    // Ïπ¥Ïπ¥??APIÎ°??°ÏÑ∏???†ÌÅ∞ Í≤ÄÏ¶?
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
            reject(new HttpsError('unauthenticated', '?†Ìö®?òÏ? ?äÏ? Ïπ¥Ïπ¥???†ÌÅ∞?ÖÎãà??'));
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

    // Firebase Ïª§Ïä§?Ä ?†ÌÅ∞ ?ùÏÑ±
    const customToken = await getAuth().createCustomToken(uid, {
      provider: 'kakao',
      kakaoId,
    });

    return { customToken };
  }
);

// ?Ä?Ä FCM ?∏Ïãú ?åÎ¶º Î∞úÏÜ° (notification_queue ?∏Î¶¨Í±? ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.sendPushOnNotificationQueue = onDocumentCreated(
  { document: 'notification_queue/{docId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { title, body } = data;
    if (!title && !body) return;

    const db = getFirestore();

    // fcm_tokens Ïª¨Î†â?òÏóê??Î™®Îì† ?†ÌÅ∞ ?òÏßë
    const tokensSnap = await db.collection('fcm_tokens').get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);

    if (tokens.length === 0) {
      await event.data.ref.delete();
      return;
    }

    // FCM Î©Ä?∞Ï∫ê?§Ìä∏ Î∞úÏÜ° (??Î≤àÏóê ÏµúÎ? 500Í∞?
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

    // ÎßåÎ£å???†ÌÅ∞ ?ïÎ¶¨
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }

    // Ï≤òÎ¶¨ ?ÑÎ£å????Î¨∏ÏÑú ??†ú
    await event.data.ref.delete();
  }
);

// ?Ä?Ä KOSPI 200 ?ºÍ∞Ñ?†Î¨º ?ÑÏû¨Í∞Ä (KIS API) ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
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
  _kisTokenExpiry = now + (res.data.expires_in - 300) * 1000; // 5Î∂??¨Ïú†
  return _kisToken;
}

// ?¥Îãπ ???îÏùò ??Î≤àÏß∏ Î™©Ïöî???†Î¨º ÏµúÏ¢ÖÍ±∞Îûò?? ?†Ïßú Î∞òÌôò
function getSecondThursday(year, month) {
  const firstDay = new Date(Date.UTC(year, month - 1, 1));
  const dow = firstDay.getUTCDay(); // 0=?? 4=Î™?
  const firstThursday = 1 + (4 - dow + 7) % 7;
  return firstThursday + 7;
}

// KOSPI200 ?ºÍ∞Ñ?†Î¨º ?®Ï∂ïÏΩîÎìú: A0 + (year-2010 2?êÎ¶¨) + ??2?êÎ¶¨
// ÏµúÏ¢ÖÍ±∞Îûò??Î∂ÑÍ∏∞ ??Î≤àÏß∏ Î™©Ïöî?? ?¥ÌõÑÎ©??§Ïùå Î∂ÑÍ∏∞Î¨ºÎ°ú ?ÑÌôò
function getNightFuturesSymbol() {
  const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth() + 1;
  const day = kst.getUTCDate();

  const qMonths = [3, 6, 9, 12];
  let expiryMonth = qMonths.find(m => m >= month);
  let expiryYear = year;
  if (!expiryMonth) { expiryMonth = 3; expiryYear = year + 1; }

  // ?ÑÏû¨ Î∂ÑÍ∏∞?îÏù¥Í≥? ÏµúÏ¢ÖÍ±∞Îûò???¥ÌõÑÎ©??§Ïùå Î∂ÑÍ∏∞Î¨??¨Ïö©
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

// KIS WebSocket ?πÏù∏??Î∞úÍ∏â
async function getKisApprovalKey(appKey, appSecret) {
  const res = await axios.post(
    'https://openapi.koreainvestment.com:9443/oauth2/Approval',
    { grant_type: 'client_credentials', appkey: appKey, secretkey: appSecret }
  );
  return res.data.approval_key;
}

// AES-256-CBC Î≥µÌò∏??
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

// KIS WebSocket?ºÎ°ú ?ºÍ∞Ñ?†Î¨º ?§ÏãúÍ∞?Ï≤¥Í≤∞Í∞Ä 1???òÏã† (?¨Ïãú???¨Ìï®)
function fetchViaWebSocket(approvalKey, symbol, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let aesKey = null;
    let aesIv = null;
    const done = (fn, val) => { if (!settled) { settled = true; clearTimeout(timer); try { ws.terminate(); } catch(_){} fn(val); } };

    const timer = setTimeout(() => done(reject, new Error('timeout')), timeoutMs);

    const ws = new WebSocket('ws://ops.koreainvestment.com:21000');

    ws.on('open', () => {
      console.log('[WS] ?∞Í≤∞??);
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
          // SUBSCRIBE SUCCESS ??AES ???Ä??
          if (json.body?.msg1 === 'SUBSCRIBE SUCCESS') {
            aesKey = json.body?.output?.key;
            aesIv  = json.body?.output?.iv;
            console.log('[WS] Íµ¨ÎèÖ ?±Í≥µ, ?îÌò∏?îÌÇ§ ?òÏã†:', !!aesKey);
          }
        } catch (_) {}
        return;
      }

      const parts = msg.split('|');
      console.log('[WS] ?åÏù¥?ÑÎ©î?úÏ?:', parts[0], parts[1], parts[2], parts[3]?.slice(0, 60));
      if (parts.length < 4 || parts[1] !== 'H0UPANC0') return;

      let dataStr = parts[3];

      // ?îÌò∏?îÎêú Í≤ΩÏö∞ Î≥µÌò∏??
      if (parts[0] === '1') {
        if (!aesKey || !aesIv) {
          console.warn('[WS] ?îÌò∏???∞Ïù¥?∞Ïù∏?????ÜÏùå');
          return;
        }
        try {
          dataStr = aesDecrypt(dataStr, aesKey, aesIv);
        } catch (e) {
          console.error('[WS] Î≥µÌò∏???§Ìå®:', e.message);
          return;
        }
      }

      // ?∞Ïù¥??Í±¥Ïàò(parts[2])ÎßåÌÅº ?àÏΩî?úÍ? ?àÏùÑ ???àÏùå ??Ï≤?Î≤àÏß∏Îß??¨Ïö©
      const firstRecord = dataStr.split('^' + symbol).shift() || dataStr;
      const fields = firstRecord.split('^');
      console.log('[WS] fields[0..9]:', fields.slice(0, 10).join(', '));

      // H0UPANC0 ?ÑÎìú: 0:?®Ï∂ïÏΩîÎìú 1:?ÅÏóÖ?ºÏûê 2:Ï≤¥Í≤∞?úÍ∞Å 3:?ÑÏû¨Í∞Ä 4:?ÑÏùº?ÄÎπ?5:?±ÎùΩÎ•?
      const price = parseFloat(fields[3]);
      const change = parseFloat(fields[4]);
      const changeRate = parseFloat(fields[5]);
      if (!price || price <= 0) {
        console.warn('[WS] Í∞ÄÍ≤??åÏã± ?§Ìå®, fields:', fields.slice(0, 8).join(', '));
        return;
      }

      console.log('[WS] Ï≤¥Í≤∞Í∞Ä ?òÏã†:', price, change, changeRate);
      done(resolve, { price, change, changeRate });
    });

    ws.on('error', (e) => { console.error('[WS] ?êÎü¨:', e.message); done(reject, e); });
  });
}

// approvalKey ?¨Î∞úÍ∏????¨Ïãú???¨Ìï® fetchViaWebSocket
async function fetchWithRetry(appKey, appSecret, symbol) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const approvalKey = await getKisApprovalKey(appKey, appSecret);
      const data = await fetchViaWebSocket(approvalKey, symbol, 20000); // 20Ï¥?
      return data;
    } catch (e) {
      console.error(`[WS] ?úÎèÑ ${attempt} ?§Ìå®:`, e.message);
      if (attempt < 2) {
        await new Promise(r => setTimeout(r, 1000));
      } else {
        throw e;
      }
    }
  }
}

// ?Ä?Ä ?ºÍ∞Ñ?†Î¨º Í∞ÄÍ≤?5Î∂ÑÎßà??Firestore??Í∏∞Î°ù (?àÏä§?†Î¶¨ Ï∂ïÏ†Å) ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.recordNightFuturesPrice = onSchedule(
  { schedule: 'every 1 minutes', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
    const kstHour = kst.getUTCHours();
    if (kstHour >= 5 && kstHour < 18) return; // ???úÍ∞Ñ ?§ÌÇµ

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

      // 7???¥ÏÉÅ ???∞Ïù¥???ïÎ¶¨ (ÏµúÎ? 2000Í∞??†Ï?)
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

// ?Ä?Ä ?ºÍ∞Ñ?†Î¨º ?§Ï†ï Î∞òÌôò (approval_key + symbol + ?àÏä§?†Î¶¨) ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.getKisNightFuturesConfig = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 15 },
  async () => {
    const db = getFirestore();
    const snap = await db.collection('_admin').doc('kis').get();
    if (!snap.exists) throw new HttpsError('not-found', 'KIS ?§Ï†ï ?ÜÏùå');

    const { appKey, appSecret } = snap.data();
    const symbol = getNightFuturesSymbol();
    const approvalKey = await getKisApprovalKey(appKey, appSecret);

    // ÏµúÍ∑º 300Í∞?(5Î∂ÑÎ¥â Í∏∞Ï? ??25?úÍ∞Ñ)
    const histSnap = await db.collection('night_futures_prices')
      .orderBy('timestamp', 'desc').limit(300).get();

    const history = histSnap.docs.reverse().map(d => ({
      time: d.data().timestamp.toMillis(),
      price: d.data().price,
    }));

    return { approvalKey, symbol, history };
  }
);

// getKospiNightFutures: WebSocket ?ÜÏù¥ Firestore ÏµúÏã† ?∞Ïù¥?∞Îßå Î∞òÌôò
// (WebSocket?Ä recordNightFuturesPrice ?§Ï?Ï§ÑÎü¨Îß??¨Ïö© ??appkey Ï∂©Îèå Î∞©Ï?)
exports.getKospiNightFutures = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 10 },
  async () => {
    const db = getFirestore();
    const symbol = getNightFuturesSymbol();

    const histSnap = await db.collection('night_futures_prices')
      .orderBy('timestamp', 'desc').limit(1).get();

    if (histSnap.empty) {
      console.warn('[getKospiNightFutures] night_futures_prices Ïª¨Î†â??ÎπÑÏñ¥ ?àÏùå');
      return { hasData: false };
    }

    const d = histSnap.docs[0].data();
    return {
      hasData: true,
      name: `KOSPI200 ?ºÍ∞Ñ?†Î¨º (${symbol})`,
      price: d.price,
      change: d.change,
      changeRate: d.changeRate,
      prevClose: d.price - d.change,
      volume: 0,
      sign: d.change >= 0 ? '2' : '4',
    };
  }
);



// ?Ä?Ä ?®ÏΩî Ï£ºÍ∞§ ?¨Î°§Îß?Í≥µÌÜµ Î°úÏßÅ ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
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

// ?Ä?Ä ?®ÏΩî Ï£ºÍ∞§ ?ºÏûêÎ≥?Í≤åÏãúÍ∏Ä ??ÏßëÍ≥Ñ (1?úÍ∞ÑÎßàÎã§) ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
exports.fetchFmkoreaIndex = onSchedule(
  { schedule: 'every 60 minutes', region: 'asia-northeast3', timeoutSeconds: 120 },
  async () => { await _scrapeFmkoreaIndex(); }
);

// ?Ä?Ä ?®ÏΩî Ï£ºÍ∞§ ?òÎèô ?∏Î¶¨Í±?(ÏµúÏ¥à 1???§Ìñâ?? ?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä?Ä
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

