const { onDocumentCreated, onDocumentWritten } = require('firebase-functions/v2/firestore');
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

// ?�?� ?�규 가?�자 ??관리자?�게 ?�림 ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.notifyAdminOnNewUser = auth.user().onCreate(async (user) => {
  const db = getFirestore();

  // config/admin 문서?�서 관리자 UID 조회
  const adminSnap = await db.collection('config').doc('admin').get();
  const adminUid = adminSnap.data()?.uid;
  if (!adminUid) return;

  // 관리자 FCM ?�큰 조회
  const tokensSnap = await db.collection('fcm_tokens')
    .where('uid', '==', adminUid).get();
  const tokens = tokensSnap.docs
    .map((d) => d.data().token)
    .filter((t) => typeof t === 'string' && t.length > 0);
  if (tokens.length === 0) return;

  const displayName = user.displayName || user.email || '?????�음';
  const provider = user.providerData?.[0]?.providerId ?? 'unknown';

  await getMessaging().sendEachForMulticast({
    notification: {
      title: '👤 신규 가입자',
      body: `${displayName} (${provider})`,
    },
    android: { notification: { sound: 'default', channelId: 'stockstorage_alerts' } },
    apns: { payload: { aps: { sound: 'default' } } },
    tokens,
  });
});

// ?�?� ?��? ?�림 (???��? ??같�? 종목 ?��? ?�성?�들?�게 ?�시) ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.sendCommentNotification = onDocumentCreated(
  { document: 'stock_picks/{pickId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content: text } = data;
    const { pickId } = event.params;
    const db = getFirestore();

    // 종목 ?�름 조회
    const pickSnap = await db.collection('stock_picks').doc(pickId).get();
    const pickName = pickSnap.data()?.name ?? '종목';

    // 같�? 종목???��? ???�른 ?��? uid ?�집
    const commentsSnap = await db
      .collection('stock_picks').doc(pickId).collection('comments').get();
    const uids = new Set(
      commentsSnap.docs
        .map((d) => d.data().uid)
        .filter((u) => u && u !== commenterUid)
    );
    if (uids.size === 0) return;

    // uid ??FCM ?�큰 조회
    const tokensSnap = await db.collection('fcm_tokens').get();
    const tokens = tokensSnap.docs
      .filter((d) => uids.has(d.data().uid))
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '?�군가';
    const preview = text?.length > 30 ? text.slice(0, 30) + '...' : text;

    // FCM 발송
    const chunkSize = 500;
    const invalidTokens = [];
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: `💬 ${pickName} 새 댓글`,
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

    // 만료 ?�큰 ?�리
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }
  }
);

// ?�?� ?�유게시???��? ?�림 (???��? ??게시글 ?�성?�에�??�시) ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.sendPostCommentNotification = onDocumentCreated(
  { document: 'posts/{postId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { postId } = event.params;
    const db = getFirestore();

    // 게시글 조회 ???�성??UID ?�인
    const postSnap = await db.collection('posts').doc(postId).get();
    if (!postSnap.exists) return;

    const postData = postSnap.data();
    const authorUid = postData?.uid;

    // ?�기 글???�기가 ?��? ???�림 ?�음
    if (!authorUid || authorUid === commenterUid) return;

    // ?�성??FCM ?�큰 조회
    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid).get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '?�군가';
    const preview = content?.length > 30 ? content.slice(0, 30) + '...' : content;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: `💬 내 글에 댓글이 달렸어요`,
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

// ?�?� ?�코지?? 30분마???�펨코리??주식게시??글 ???�집 ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
// ���� �Ÿ����� ��� �˸� (�� ��� �� �Ÿ����� �ۼ��ڿ��� Ǫ��) ����������������������������������������������
exports.sendJournalCommentNotification = onDocumentCreated(
  { document: 'trading_journal/{journalId}/comments/{commentId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { uid: commenterUid, nickname, content } = data;
    const { journalId } = event.params;
    const db = getFirestore();

    // �Ÿ����� ��ȸ �� �ۼ��� UID Ȯ��
    const journalSnap = await db.collection('trading_journal').doc(journalId).get();
    if (!journalSnap.exists) return;

    const journalData = journalSnap.data();
    const authorUid = journalData?.uid;

    // �ڱ� �ۿ� �ڱ� ����� �˸� ����
    if (!authorUid || authorUid === commenterUid) return;

    // �ۼ��� FCM ��ū ��ȸ
    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid).get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '�͸�';
    const preview = content?.length > 30 ? content.slice(0, 30) + '��' : content;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: '📝 매매일지에 댓글이 달렸어요',
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
// trading_journal ?? ??? publishedAt? ??? ?? ??
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

exports.crawlFemcoIndex = onSchedule(
  { schedule: 'every 30 minutes', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const db = getFirestore();
    const now = new Date();
    const cutoff = new Date(now.getTime() - 30 * 60 * 1000); // 30�???

    try {
      const headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept-Language': 'ko-KR,ko;q=0.9',
        'Referer': 'https://www.fmkorea.com/',
      };

      // ?�펨코리??주식 게시??1~3?�이지 ?�집
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
          // ?�간 ?�싱: "HH:MM" ?�식?�면 ?�늘 ?�짜�? "MM.DD" ?�면 과거
          if (!timeText) return;

          let postDate = null;
          if (/^\d{2}:\d{2}$/.test(timeText)) {
            const [h, m] = timeText.split(':').map(Number);
            postDate = new Date(now);
            postDate.setHours(h, m, 0, 0);
          } else {
            // MM.DD ?�식?�면 ?�늘보다 과거
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

      // Firestore ?�??
      const slotKey = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}_${String(now.getHours()).padStart(2,'0')}:${now.getMinutes() < 30 ? '00' : '30'}`;

      await db.collection('board_index').doc('femco')
        .collection('logs').doc(slotKey).set({
          count,
          timestamp: now,
          slot: slotKey,
        });

      // 최신�?갱신
      await db.collection('board_index').doc('femco').set({
        count,
        updatedAt: now,
        slot: slotKey,
      }, { merge: true });

    } catch (_) {
    }
  }
);

// ?�?� 카카???�증코드 ??Firebase 커스?� ?�큰 (??admin?? ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.kakaoAuthCode = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const { code, redirectUri } = request.data;
    if (!code || !redirectUri) {
      throw new HttpsError('invalid-argument', 'code?� redirectUri가 ?�요?�니??');
    }

    // ?�증코드 ???�세???�큰
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

    // ?�세???�큰 ???��? ?�보
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

// ?�?� 카카??커스?� ?�큰 발급 ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
// ?�라?�언?�에??카카???�세???�큰??보내�??�버?�서 검�???Firebase 커스?� ?�큰 반환
exports.createKakaoCustomToken = onCall(
  { region: 'asia-northeast3' },
  async (request) => {
    const { accessToken } = request.data;
    if (!accessToken) {
      throw new HttpsError('invalid-argument', 'accessToken???�요?�니??');
    }

    // 카카??API�??�세???�큰 검�?
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
            reject(new HttpsError('unauthenticated', '?�효?��? ?��? 카카???�큰?�니??'));
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

    // Firebase 커스?� ?�큰 ?�성
    const customToken = await getAuth().createCustomToken(uid, {
      provider: 'kakao',
      kakaoId,
    });

    return { customToken };
  }
);

// ?�?� FCM ?�시 ?�림 발송 (notification_queue ?�리�? ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.sendPushOnNotificationQueue = onDocumentCreated(
  { document: 'notification_queue/{docId}', region: 'asia-northeast3' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { title, body } = data;
    if (!title && !body) return;

    const db = getFirestore();

    // fcm_tokens 컬렉?�에??모든 ?�큰 ?�집
    const tokensSnap = await db.collection('fcm_tokens').get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);

    if (tokens.length === 0) {
      await event.data.ref.delete();
      return;
    }

    // FCM 멀?�캐?�트 발송 (??번에 최�? 500�?
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

    // 만료???�큰 ?�리
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }

    // 처리 ?�료????문서 ??��
    await event.data.ref.delete();
  }
);

// ?�?� KOSPI 200 ?�간?�물 ?�재가 (KIS API) ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
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
  _kisTokenExpiry = now + (res.data.expires_in - 300) * 1000; // 5�??�유
  return _kisToken;
}

// ?�당 ???�의 ??번째 목요???�물 최종거래?? ?�짜 반환
function getSecondThursday(year, month) {
  const firstDay = new Date(Date.UTC(year, month - 1, 1));
  const dow = firstDay.getUTCDay(); // 0=?? 4=�?
  const firstThursday = 1 + (4 - dow + 7) % 7;
  return firstThursday + 7;
}

// KOSPI200 ?�간?�물 ?�축코드: A0 + (year-2010 2?�리) + ??2?�리
// 최종거래??분기 ??번째 목요?? ?�후�??�음 분기물로 ?�환
function getNightFuturesSymbol() {
  const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth() + 1;
  const day = kst.getUTCDate();

  const qMonths = [3, 6, 9, 12];
  let expiryMonth = qMonths.find(m => m >= month);
  let expiryYear = year;
  if (!expiryMonth) { expiryMonth = 3; expiryYear = year + 1; }

  // ?�재 분기?�이�? 최종거래???�후�??�음 분기�??�용
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

// KIS WebSocket ?�인??발급
async function getKisApprovalKey(appKey, appSecret) {
  const res = await axios.post(
    'https://openapi.koreainvestment.com:9443/oauth2/Approval',
    { grant_type: 'client_credentials', appkey: appKey, secretkey: appSecret }
  );
  return res.data.approval_key;
}

// AES-256-CBC 복호??
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

// KIS WebSocket?�로 ?�간?�물 ?�시�?체결가 1???�신 (?�시???�함)
function fetchViaWebSocket(approvalKey, symbol, timeoutMs = 25000) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let aesKey = null;
    let aesIv = null;
    const done = (fn, val) => { if (!settled) { settled = true; clearTimeout(timer); try { ws.terminate(); } catch(_){} fn(val); } };

    const timer = setTimeout(() => done(reject, new Error('timeout')), timeoutMs);

    const ws = new WebSocket('ws://ops.koreainvestment.com:21000');

    ws.on('open', () => {
      console.log('[WS] connected');
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
          // SUBSCRIBE SUCCESS ??AES ???�??
          if (json.body?.msg1 === 'SUBSCRIBE SUCCESS') {
            aesKey = json.body?.output?.key;
            aesIv  = json.body?.output?.iv;
            console.log('[WS] 구독 ?�공, ?�호?�키 ?�신:', !!aesKey);
          }
        } catch (_) {}
        return;
      }

      const parts = msg.split('|');
      console.log('[WS] ?�이?�메?��?:', parts[0], parts[1], parts[2], parts[3]?.slice(0, 60));
      if (parts.length < 4 || parts[1] !== 'H0UPANC0') return;

      let dataStr = parts[3];

      // ?�호?�된 경우 복호??
      if (parts[0] === '1') {
        if (!aesKey || !aesIv) {
          console.warn('[WS] ?�호???�이?�인?????�음');
          return;
        }
        try {
          dataStr = aesDecrypt(dataStr, aesKey, aesIv);
        } catch (e) {
          console.error('[WS] 복호???�패:', e.message);
          return;
        }
      }

      // ?�이??건수(parts[2])만큼 ?�코?��? ?�을 ???�음 ??�?번째�??�용
      const firstRecord = dataStr.split('^' + symbol).shift() || dataStr;
      const fields = firstRecord.split('^');
      console.log('[WS] fields[0..9]:', fields.slice(0, 10).join(', '));

      // H0UPANC0 ?�드: 0:?�축코드 1:?�업?�자 2:체결?�각 3:?�재가 4:?�일?��?5:?�락�?
      const price = parseFloat(fields[3]);
      const change = parseFloat(fields[4]);
      const changeRate = parseFloat(fields[5]);
      if (!price || price <= 0) {
        console.warn('[WS] 가�??�싱 ?�패, fields:', fields.slice(0, 8).join(', '));
        return;
      }

      console.log('[WS] 체결가 ?�신:', price, change, changeRate);
      done(resolve, { price, change, changeRate });
    });

    ws.on('error', (e) => { console.error('[WS] ?�러:', e.message); done(reject, e); });
  });
}

// approvalKey ?�발�????�시???�함 fetchViaWebSocket
async function fetchWithRetry(appKey, appSecret, symbol) {
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const approvalKey = await getKisApprovalKey(appKey, appSecret);
      const data = await fetchViaWebSocket(approvalKey, symbol, 20000); // 20�?
      return data;
    } catch (e) {
      console.error(`[WS] ?�도 ${attempt} ?�패:`, e.message);
      if (attempt < 2) {
        await new Promise(r => setTimeout(r, 1000));
      } else {
        throw e;
      }
    }
  }
}

// ?�?� ?�간?�물 가�?5분마??Firestore??기록 (?�스?�리 축적) ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.recordNightFuturesPrice = onSchedule(
  { schedule: 'every 1 minutes', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const kst = new Date(new Date().getTime() + 9 * 60 * 60 * 1000);
    const kstHour = kst.getUTCHours();
    if (kstHour >= 5 && kstHour < 18) return; // ???�간 ?�킵

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

      // 7???�상 ???�이???�리 (최�? 2000�??��?)
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

// ?�?� ?�간?�물 ?�정 반환 (approval_key + symbol + ?�스?�리) ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.getKisNightFuturesConfig = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 15 },
  async () => {
    const db = getFirestore();
    const snap = await db.collection('_admin').doc('kis').get();
    if (!snap.exists) throw new HttpsError('not-found', 'KIS ?�정 ?�음');

    const { appKey, appSecret } = snap.data();
    const symbol = getNightFuturesSymbol();
    const approvalKey = await getKisApprovalKey(appKey, appSecret);

    // 최근 300�?(5분봉 기�? ??25?�간)
    const histSnap = await db.collection('night_futures_prices')
      .orderBy('timestamp', 'desc').limit(300).get();

    const history = histSnap.docs.reverse().map(d => ({
      time: d.data().timestamp.toMillis(),
      price: d.data().price,
    }));

    return { approvalKey, symbol, history };
  }
);

// getKospiNightFutures: WebSocket ?�이 Firestore 최신 ?�이?�만 반환
// (WebSocket?� recordNightFuturesPrice ?��?줄러�??�용 ??appkey 충돌 방�?)
exports.getKospiNightFutures = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 10 },
  async () => {
    const db = getFirestore();
    const symbol = getNightFuturesSymbol();

    const histSnap = await db.collection('night_futures_prices')
      .orderBy('timestamp', 'desc').limit(1).get();

    if (histSnap.empty) {
      console.warn('[getKospiNightFutures] night_futures_prices 컬렉??비어 ?�음');
      return { hasData: false };
    }

    const d = histSnap.docs[0].data();
    return {
      hasData: true,
      name: `KOSPI200 ?�간?�물 (${symbol})`,
      price: d.price,
      change: d.change,
      changeRate: d.changeRate,
      prevClose: d.price - d.change,
      volume: 0,
      sign: d.change >= 0 ? '2' : '4',
    };
  }
);



// ?�?� ?�코 주갤 ?�롤�?공통 로직 ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
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

// ?�?� ?�코 주갤 ?�자�?게시글 ??집계 (1?�간마다) ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
exports.fetchFmkoreaIndex = onSchedule(
  { schedule: 'every 60 minutes', region: 'asia-northeast3', timeoutSeconds: 120 },
  async () => { await _scrapeFmkoreaIndex(); }
);

// ?�?� ?�코 주갤 ?�동 ?�리�?(최초 1???�행?? ?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�?�
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

// ── 커뮤니티 자동 포스팅(일상 글) ───────────────────────────────────────────

const BOT_SCHEDULE_COLLECTION = 'bot_daily_post_schedules';
const BOT_POSTS_PER_DAY = 20;
const BOT_WINDOW_START_MINUTE = 9 * 60; // 09:00 KST
const BOT_WINDOW_END_MINUTE = 22 * 60; // 22:00 KST (exclusive)
const BOT_MAX_POSTS_PER_RUN = 1;
const BOT_STOCK_RATIO = 0.7;
const BOT_UID_PREFIX = 'bot_user_';

const BOT_PERSONAS = [
  { uid: `${BOT_UID_PREFIX}01`, nickname: '동네직장인' },
  { uid: `${BOT_UID_PREFIX}02`, nickname: '아침러너' },
  { uid: `${BOT_UID_PREFIX}03`, nickname: '퇴근후독서' },
  { uid: `${BOT_UID_PREFIX}04`, nickname: '커피한잔' },
  { uid: `${BOT_UID_PREFIX}05`, nickname: '소소한기록' },
  { uid: `${BOT_UID_PREFIX}06`, nickname: '집밥연구소' },
  { uid: `${BOT_UID_PREFIX}07`, nickname: '주말산책러' },
  { uid: `${BOT_UID_PREFIX}08`, nickname: '야식참는중' },
];

const BOT_FALLBACK_STOCKS = [
  { ticker: '005930', name: '삼성전자', mentionCount: 0 },
  { ticker: '000660', name: 'SK하이닉스', mentionCount: 0 },
  { ticker: '035420', name: 'NAVER', mentionCount: 0 },
  { ticker: '068270', name: '셀트리온', mentionCount: 0 },
  { ticker: '005380', name: '현대차', mentionCount: 0 },
  { ticker: '012450', name: '한화에어로스페이스', mentionCount: 0 },
];

const BOT_STOCK_TITLE_TEMPLATES = [
  '{name} 오늘 자리 보는 사람?',
  '{name} ({ticker}) 눌림 구간 애매하네',
  '{name} 수급 계속 붙는 느낌',
  '{name} 오늘 거래대금 꽤 도네',
  '{name} 지금 추격 vs 관망',
  '{name} 단기 자리 의견 갈리네',
];

const BOT_STOCK_CONTENT_TEMPLATES = [
  '펨코 언급 {mentions}회 찍혔네요. 저는 오늘은 추격보다 눌림 대기 중입니다.',
  '체감상 {name} 얘기가 계속 나오네요. 단타 구간이면 손절 라인 짧게 잡는 게 맞아 보입니다.',
  '{name} 오늘 변동 꽤 크네요. 시초 강하면 따라가고 아니면 관망하려고요.',
  '{name} 관심도 올라온 건 확실한데, 종가 위치 보고 내일 대응할 생각입니다.',
  '오늘은 {name} 수급 체크하는 날인 듯요. 급등 캔들 나오면 분할로만 접근하려고 합니다.',
  '{name} 커뮤 화력 붙었네요. 저는 돌파 확인 전엔 비중 크게 안 싣는 쪽입니다.',
  '{name} 차트 예쁘긴 한데 고점 매수는 부담되네요. 눌릴 때만 볼까 합니다.',
  '{name} 단기 탄력은 살아있는 듯합니다. 다만 추격은 리스크 커서 짧게만 볼게요.',
];

const BOT_DAILY_TITLE_TEMPLATES = [
  '오늘 장 보고 멘탈 관리 중',
  '다들 오늘 매매 어땠나요',
  '장 끝나고 복기하는 중',
  '손절 원칙 다시 적어봄',
  '오늘은 매매 쉬는 게 맞았나',
  '시드 관리가 제일 어렵네요',
  '수익보다 잃지 않는 날로',
  '장마감 후 마음 정리',
];

const BOT_DAILY_CONTENT_TEMPLATES = [
  '수익보다 원칙 지키는 날로 마감했습니다. 다들 고생했어요.',
  '오늘은 무리 안 하고 관망 위주로 갔네요. 멘탈 지키는 게 더 중요하네요.',
  '진입보다 기다림이 더 어려운 날이었네요. 내일은 더 차분하게 가봅니다.',
  '손절 한 번 했지만 계획대로라 괜찮았습니다. 복기하고 마무리합니다.',
  '괜히 조급하면 실수만 늘더라고요. 오늘은 매매 횟수 줄여서 마감했습니다.',
  '수익보다 리스크 관리가 더 체감되는 날이네요. 다들 저녁 맛있게 드세요.',
  '장중에 흔들렸는데 비중 조절 덕분에 크게 안 다쳤습니다. 내일 다시 봅시다.',
  '오늘은 쉬어가는 매매였습니다. 시장은 내일도 열리니 무리 안 하려 합니다.',
];

function getKstNow(base = new Date()) {
  return new Date(base.getTime() + (9 * 60 * 60 * 1000));
}

function getKstDateKey(base = new Date()) {
  const kst = getKstNow(base);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function parseDateKey(dateKey) {
  const [yy, mm, dd] = dateKey.split('-').map((v) => parseInt(v, 10));
  return { yy, mm, dd };
}

function getKstMinuteOfDay(base = new Date()) {
  const kst = getKstNow(base);
  return (kst.getUTCHours() * 60) + kst.getUTCMinutes();
}

function pickUniqueRandomMinutes(count, startMinute, endMinuteExclusive) {
  const pool = [];
  for (let m = startMinute; m < endMinuteExclusive; m++) pool.push(m);

  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }

  return pool.slice(0, count).sort((a, b) => a - b);
}

function hashString(input) {
  let h = 2166136261;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0);
}

function pickBySeed(arr, seedText) {
  const idx = hashString(seedText) % arr.length;
  return arr[idx];
}

function pickByWeightedSeed(seedText, ratioA = 0.5) {
  const normalized = Math.max(0, Math.min(1, ratioA));
  const val = hashString(seedText) / 4294967295;
  return val < normalized;
}

async function getHotMentionsForBot(db) {
  try {
    const snap = await db
      .collection('fmkorea_stock_mentions_realtime')
      .doc('today')
      .get();
    if (!snap.exists) return [];
    const data = snap.data() || {};
    const topMentions = Array.isArray(data.topMentions) ? data.topMentions : [];
    return topMentions
      .map((m) => ({
        ticker: typeof m.ticker === 'string' ? m.ticker.trim() : '',
        name: typeof m.name === 'string' ? m.name.trim() : '',
        mentionCount: Number.isFinite(m.mentionCount) ? Number(m.mentionCount) : 0,
      }))
      .filter((m) => m.name || m.ticker)
      .slice(0, 20);
  } catch (_) {
    return [];
  }
}

async function ensureBotDailySchedule(db, dateKey) {
  const ref = db.collection(BOT_SCHEDULE_COLLECTION).doc(dateKey);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return;

    const minuteOffsets = pickUniqueRandomMinutes(
      BOT_POSTS_PER_DAY,
      BOT_WINDOW_START_MINUTE,
      BOT_WINDOW_END_MINUTE,
    );

    tx.set(ref, {
      dateKey,
      targetCount: BOT_POSTS_PER_DAY,
      minuteOffsets,
      postedOffsets: [],
      createdAt: new Date(),
      updatedAt: new Date(),
    });
  });
}

function resolveBotStock(seed, hotMentions) {
  if (Array.isArray(hotMentions) && hotMentions.length > 0) {
    return pickBySeed(hotMentions, `${seed}-hot-stock`);
  }
  return pickBySeed(BOT_FALLBACK_STOCKS, `${seed}-fallback-stock`);
}

function buildBotDraft(seed, stock) {
  const rawTitle = pickBySeed(BOT_STOCK_TITLE_TEMPLATES, `${seed}-title`);
  const rawContent = pickBySeed(BOT_STOCK_CONTENT_TEMPLATES, `${seed}-content`);
  const name = stock.name || stock.ticker || '이 종목';
  const ticker = stock.ticker || '';
  const mentions = Math.max(0, Number(stock.mentionCount) || 0);
  return {
    title: rawTitle
      .replaceAll('{name}', name)
      .replaceAll('{ticker}', ticker),
    content: rawContent
      .replaceAll('{name}', name)
      .replaceAll('{ticker}', ticker)
      .replaceAll('{mentions}', String(mentions)),
  };
}

function buildDailyDraft(seed) {
  const title = pickBySeed(BOT_DAILY_TITLE_TEMPLATES, `${seed}-daily-title`);
  const content = pickBySeed(BOT_DAILY_CONTENT_TEMPLATES, `${seed}-daily-content`);
  return { title, content };
}

function buildBotPost(dateKey, minuteOffset, hotMentions) {
  const seed = `${dateKey}-${minuteOffset}`;
  const persona = pickBySeed(BOT_PERSONAS, `${seed}-persona`);
  const useStockPost = pickByWeightedSeed(`${seed}-type`, BOT_STOCK_RATIO);
  const stock = resolveBotStock(seed, hotMentions);
  const draft = useStockPost ? buildBotDraft(seed, stock) : buildDailyDraft(seed);
  const postType = useStockPost ? 'stock' : 'daily';
  return {
    uid: persona.uid,
    nickname: persona.nickname,
    title: draft.title,
    content: draft.content,
    likes: 0,
    imageUrls: [],
    isBot: true,
    botProfileId: persona.uid,
    botPostType: postType,
    createdAt: new Date(),
  };
}

exports.generateBotDailySchedule = onSchedule(
  { schedule: 'every day 00:01', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const db = getFirestore();
    const dateKey = getKstDateKey();
    await ensureBotDailySchedule(db, dateKey);
  }
);

exports.publishCommunityBotPosts = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Asia/Seoul', region: 'asia-northeast3', timeoutSeconds: 60 },
  async () => {
    const db = getFirestore();
    const nowMinute = getKstMinuteOfDay();
    const dateKey = getKstDateKey();
    const hotMentions = await getHotMentionsForBot(db);

    if (nowMinute < BOT_WINDOW_START_MINUTE || nowMinute >= BOT_WINDOW_END_MINUTE) {
      return;
    }

    await ensureBotDailySchedule(db, dateKey);
    const scheduleRef = db.collection(BOT_SCHEDULE_COLLECTION).doc(dateKey);

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(scheduleRef);
      if (!snap.exists) return;

      const data = snap.data() || {};
      const minuteOffsets = Array.isArray(data.minuteOffsets) ? data.minuteOffsets : [];
      const postedOffsets = Array.isArray(data.postedOffsets) ? data.postedOffsets : [];
      const postedSet = new Set(postedOffsets);

      const dueOffsets = minuteOffsets
        .filter((m) => typeof m === 'number' && m <= nowMinute && !postedSet.has(m))
        .sort((a, b) => a - b);

      if (dueOffsets.length === 0) return;
      const offsetsToPost = dueOffsets.slice(0, BOT_MAX_POSTS_PER_RUN);

      for (const minuteOffset of offsetsToPost) {
        const postRef = db.collection('posts').doc();
        tx.set(postRef, buildBotPost(dateKey, minuteOffset, hotMentions));
        postedSet.add(minuteOffset);
      }

      tx.set(scheduleRef, {
        postedOffsets: Array.from(postedSet).sort((a, b) => a - b),
        lastRunMinute: nowMinute,
        updatedAt: new Date(),
      }, { merge: true });
    });
  }
);

