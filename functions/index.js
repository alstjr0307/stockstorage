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
      title: '👤 신규 가입자',
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
    const pickName = pickSnap.data()?.name ?? '종목';

    // 같은 종목에 댓글 단 다른 유저 uid 수집
    const commentsSnap = await db
      .collection('stock_picks').doc(pickId).collection('comments').get();
    const uids = new Set(
      commentsSnap.docs
        .map((d) => d.data().uid)
        .filter((u) => u && u !== commenterUid)
    );
    if (uids.size === 0) return;

    // uid → FCM 토큰 조회
    const tokensSnap = await db.collection('fcm_tokens').get();
    const tokens = tokensSnap.docs
      .filter((d) => uids.has(d.data().uid))
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '누군가';
    const preview = content?.length > 30 ? content.slice(0, 30) + '…' : content;

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

    // 만료 토큰 정리
    if (invalidTokens.length > 0) {
      await Promise.all(
        invalidTokens.map((t) => db.collection('fcm_tokens').doc(t).delete())
      );
    }
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

    // 작성자 FCM 토큰 조회
    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid).get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '누군가';
    const preview = content?.length > 30 ? content.slice(0, 30) + '…' : content;

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

    const tokensSnap = await db.collection('fcm_tokens')
      .where('uid', '==', authorUid)
      .get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);
    if (tokens.length === 0) return;

    const senderName = nickname || '\uB204\uAD70\uAC00';
    const previewRaw = typeof content === 'string' ? content : '';
    const preview = previewRaw.length > 30 ? `${previewRaw.slice(0, 30)}...` : previewRaw;

    const invalidTokens = [];
    const chunkSize = 500;
    for (let i = 0; i < tokens.length; i += chunkSize) {
      const chunk = tokens.slice(i, i + chunkSize);
      const response = await getMessaging().sendEachForMulticast({
        notification: {
          title: '\uD83D\uDCDD \uB9E4\uB9E4\uC77C\uC9C0\uC5D0 \uB313\uAE00\uC774 \uB2EC\uB838\uC5B4\uC694',
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
    if (!title && !body) return;

    const db = getFirestore();

    // fcm_tokens 컬렉션에서 모든 토큰 수집
    const tokensSnap = await db.collection('fcm_tokens').get();
    const tokens = tokensSnap.docs
      .map((d) => d.data().token)
      .filter((t) => typeof t === 'string' && t.length > 0);

    if (tokens.length === 0) {
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
