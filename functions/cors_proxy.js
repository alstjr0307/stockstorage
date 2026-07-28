// 웹(Flutter Web) 클라이언트의 CORS 우회용 범용 프록시.
//
// 브라우저는 finance.naver.com / query*.finance.yahoo.com 등으로의 직접 요청을
// CORS 로 차단한다. 클라이언트(stock_price_service._pget)는 웹일 때 이 onCall 로
// 요청을 중계한다. onCall 은 Firebase SDK 호출이라 CORS 가 발생하지 않는다.
//
// 비용 억제:
//  - 허용 호스트 allowlist (임의 URL 프록시 금지).
//  - 함수 인스턴스 메모리에 짧은 TTL(기본 10초) 캐시 → 동일 URL 반복 호출 시
//    상류(네이버/야후) 요청 수를 유저 수와 무관하게 억제.
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const axios = require('axios');

// 허용 호스트(정확 일치). 필요한 것만 추가.
const ALLOWED_HOSTS = new Set([
  'finance.naver.com',
  'api.finance.naver.com',
  'polling.finance.naver.com',
  'm.stock.naver.com',
  'query1.finance.yahoo.com',
  'query2.finance.yahoo.com',
]);

const CACHE_TTL_MS = 10 * 1000;
const CACHE_MAX_ENTRIES = 500;
const _cache = new Map(); // url -> { status, body, ts }

function _getCached(url) {
  const hit = _cache.get(url);
  if (!hit) return null;
  if (Date.now() - hit.ts < CACHE_TTL_MS) return hit;
  _cache.delete(url);
  return null;
}

// 만료 항목을 지운다. 인스턴스가 오래 살아도 캐시가 계속 커지지 않도록.
function _pruneCache() {
  const now = Date.now();
  for (const [url, entry] of _cache) {
    if (now - entry.ts >= CACHE_TTL_MS) _cache.delete(url);
  }
  // 짧은 시간에 서로 다른 URL 이 몰린 경우엔 오래된 것부터 버린다(Map 은 삽입 순서).
  while (_cache.size > CACHE_MAX_ENTRIES) {
    _cache.delete(_cache.keys().next().value);
  }
}

const MAX_BATCH = 20;

async function _fetchOne(url, headers) {
  let host;
  try {
    host = new URL(url).host;
  } catch (_) {
    return { status: 400, body: '' };
  }
  if (!ALLOWED_HOSTS.has(host)) return { status: 403, body: '' };

  const cached = _getCached(url);
  if (cached) return { status: cached.status, body: cached.body };

  try {
    const res = await axios.get(url, {
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          + '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        ...headers,
      },
      timeout: 8000,
      // 응답을 원문 문자열 그대로 전달(클라이언트에서 jsonDecode).
      responseType: 'text',
      transformResponse: (d) => d,
      // 4xx/5xx 도 예외로 던지지 않고 그대로 반환.
      validateStatus: () => true,
    });
    const body = typeof res.data === 'string'
      ? res.data
      : JSON.stringify(res.data);
    const out = { status: res.status, body, ts: Date.now() };
    _cache.set(url, out);
    _pruneCache();
    return { status: out.status, body: out.body };
  } catch (e) {
    console.error('[corsProxy] fetch failed:', host, e.message);
    return { status: 502, body: '' };
  }
}

const corsProxy = onCall(
  { region: 'asia-northeast3', timeoutSeconds: 10, memory: '256MiB' },
  async (request) => {
    // 웹 클라이언트는 여러 요청을 batch 로 묶어 보낸다.
    const batch = request.data?.requests;
    if (Array.isArray(batch)) {
      if (batch.length === 0 || batch.length > MAX_BATCH) {
        throw new HttpsError(
          'invalid-argument',
          `requests must have 1..${MAX_BATCH} items`,
        );
      }
      const results = await Promise.all(
        batch.map((item) => _fetchOne(String(item?.url || ''), item?.headers || {})),
      );
      return { results };
    }

    // 예전 앱 빌드 호환: 단건 요청.
    const url = String(request.data?.url || '');
    const headers = request.data?.headers || {};
    if (!url) throw new HttpsError('invalid-argument', 'url is required');

    let host;
    try {
      host = new URL(url).host;
    } catch (_) {
      throw new HttpsError('invalid-argument', 'invalid url');
    }
    if (!ALLOWED_HOSTS.has(host)) {
      throw new HttpsError('permission-denied', `host not allowed: ${host}`);
    }
    return _fetchOne(url, headers);
  },
);

module.exports = { corsProxy };
