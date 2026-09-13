'use strict';

const HOST = 'https://stockstorage-13828.web.app';
const WEB = 'https://stockstorage-web.web.app/';
const PLAY = 'https://play.google.com/store/apps/details?id=www.stockstorage.stockdiary';
const APP_STORE = 'https://apps.apple.com/app/id1577127218';
const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, c => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
})[c]);

function parseStockPath(path) {
  const match = /^\/stock\/(KS|KQ|US)\/([A-Z0-9.\-]+)\/?$/.exec(path);
  if (!match) return null;
  const [, market, ticker] = match;
  if (!(market === 'US' ? /^[A-Z][A-Z0-9.\-]{0,14}$/ : /^\d{6}$/).test(ticker)) return null;
  return { market, ticker };
}

function timestampMillis(value) {
  const millis = value?.toMillis?.();
  return Number.isFinite(millis) ? millis : 0;
}

// Only public market_feature_stocks are read. A shared URL does not expose
// private AI reports, account identifiers, memos, or paid pick content.
async function loadPublicSnapshot(db, stock) {
  const snap = await db.collection('market_feature_stocks')
    .where('ticker', '==', stock.ticker)
    .select('ticker', 'name', 'market', 'reason', 'price', 'changeRate', 'sourceDate', 'createdAt')
    .limit(20).get();
  const matches = snap.docs.map(doc => doc.data()).filter(data =>
    data.market === stock.market || (data.market === 'KR' && stock.market !== 'US'));
  matches.sort((a, b) => timestampMillis(b.sourceDate) - timestampMillis(a.sourceDate));
  return matches[0] ?? null;
}

function renderStockLanding(stock, snapshot, nameHint = '') {
  const name = (typeof snapshot?.name === 'string' && snapshot.name.trim()) ||
    (typeof nameHint === 'string' && nameHint.length <= 80 && nameHint.trim()) || stock.ticker;
  const canonical = `${HOST}/stock/${stock.market}/${stock.ticker}`;
  const query = new URLSearchParams({ market: stock.market, ticker: stock.ticker, name,
    utm_source: 'stock_landing', utm_medium: 'share', utm_campaign: 'stock_follow' });
  const webUrl = `${WEB}?${query}`;
  const shareUrl = `${canonical}?${new URLSearchParams({ name })}`;
  const androidIntent = `intent://${shareUrl.slice('https://'.length)}#Intent;scheme=https;package=www.stockstorage.stockdiary;S.browser_fallback_url=${encodeURIComponent(webUrl)};end`;
  const dateMs = timestampMillis(snapshot?.sourceDate);
  const date = dateMs > 0 ? new Date(dateMs).toLocaleDateString('ko-KR', { timeZone: 'Asia/Seoul' }) : '';
  const hasPrice = date && Number.isFinite(snapshot?.price) && snapshot.price > 0;
  const price = hasPrice ? `${stock.market === 'US' ? '$' : ''}${snapshot.price.toLocaleString('ko-KR', { maximumFractionDigits: stock.market === 'US' ? 2 : 0 })}${stock.market === 'US' ? '' : '원'}` : '';
  const reason = typeof snapshot?.reason === 'string' ? snapshot.reason.trim().slice(0, 1800) : '';
  const description = `${name} (${stock.ticker}) 종목을 확인하고 관심종목에 저장하세요. 원하는 가격에 알림을 설정할 수 있습니다.`;
  return `<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(name)} (${escapeHtml(stock.ticker)}) · 주식저장소</title>
<meta name="description" content="${escapeHtml(description)}">
${snapshot ? '' : '<meta name="robots" content="noindex,follow">'}
<link rel="canonical" href="${escapeHtml(canonical)}">
<meta property="og:type" content="website"><meta property="og:locale" content="ko_KR">
<meta property="og:title" content="${escapeHtml(name)} · 내 관심종목으로 저장하기">
<meta property="og:description" content="${escapeHtml(description)}"><meta property="og:url" content="${escapeHtml(canonical)}">
<style>
:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f4f7f6;color:#132a24;font-family:system-ui,-apple-system,sans-serif;line-height:1.6}main{max-width:660px;margin:0 auto;padding:32px 20px 56px}.brand{font-size:15px;font-weight:800;color:#087a55;text-decoration:none}.card{background:white;border:1px solid #dce6e1;border-radius:24px;padding:28px;margin-top:24px}.eyebrow{font-size:12px;font-weight:700;letter-spacing:1px;color:#647870}h1{font-size:clamp(26px,7vw,40px);line-height:1.2;margin:12px 0;overflow-wrap:anywhere}h2{font-size:21px;line-height:1.4}p{margin:10px 0}.muted{color:#5c7067;font-size:14px}.price{font-size:29px;font-weight:800;margin:20px 0 0}.summary{white-space:pre-line;overflow-wrap:anywhere}.actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:24px}.button{display:block;border-radius:12px;padding:13px 18px;background:#087a55;color:white;text-decoration:none;font-weight:750;text-align:center}.secondary{background:#e9f3ed;color:#08704e}.steps{padding-left:22px}.steps li{margin:10px 0}.store{display:flex;flex-wrap:wrap;gap:18px;margin-top:20px}.store a{color:#385b4d;font-size:14px}footer{margin-top:24px;font-size:12px;color:#68796f}a:focus-visible{outline:3px solid #147bd1;outline-offset:4px}@media(max-width:360px){.card{padding:20px}.actions a{width:100%}}
</style></head><body><main>
<a class="brand" href="${HOST}">주식저장소</a>
<section class="card"><div class="eyebrow">${escapeHtml(stock.market)} · ${escapeHtml(stock.ticker)}</div>
<h1>${escapeHtml(name)}</h1><p class="muted">관심 있는 종목을 확인하고, 다음에도 이어서 지켜보세요.</p>
${hasPrice ? `<p class="price">${escapeHtml(price)}</p><p class="muted">${escapeHtml(date)} 공개 자료 기준 · 실시간 시세가 아닙니다.</p>` : ''}
${reason ? `<h2>공개 종목 요약</h2><p class="summary">${escapeHtml(reason)}</p>${!hasPrice && date ? `<p class="muted">${escapeHtml(date)} 공개 자료 기준</p>` : ''}` : '<p class="muted">공개 요약이 아직 없는 종목입니다. 종목 상세에서 시세와 뉴스를 확인해보세요.</p>'}
<div class="actions"><a class="button" href="${escapeHtml(webUrl)}">이 종목 확인하고 저장하기</a><a id="open-app" class="button secondary" href="${escapeHtml(shareUrl)}">앱에서 열기</a></div>
<p class="muted">종목 상세는 로그인 없이 볼 수 있어요. 저장할 때 로그인해주세요.</p></section>
<section class="card"><h2>한 번 본 종목을, 내 관심종목으로</h2><ol class="steps"><li>관심종목에 저장해 다음에도 바로 찾기</li><li>앱 홈에서 저장한 종목의 시세 확인하기</li><li>원하는 가격을 정해 조건 알림 받기</li></ol><p class="muted">조건 알림은 앱 알림 수신 설정이 필요해요.</p><div class="store"><a href="${PLAY}">Google Play</a><a href="${APP_STORE}">App Store</a></div></section>
<footer>공개 자료는 갱신 시점에 따라 달라질 수 있습니다. 공유한 개인 AI 리포트의 원문은 이 페이지에 공개되지 않습니다.</footer>
</main><script>if(/Android/i.test(navigator.userAgent)){document.getElementById('open-app').href=${JSON.stringify(androidIntent).replace(/</g, '\\u003c')};}</script></body></html>`;
}

function createStockLandingHandler(db) {
  return async (req, res) => {
    if (!['GET', 'HEAD'].includes(req.method)) return res.status(405).set('Allow', 'GET, HEAD').send('Method not allowed');
    const stock = parseStockPath(req.path);
    if (!stock) return res.status(404).send('종목 링크를 확인해주세요.');
    let snapshot;
    try { snapshot = await loadPublicSnapshot(db, stock); }
    catch (error) {
      console.warn('[stockLanding] public snapshot unavailable:', error.code ?? 'unknown');
      return res.status(503).set('Retry-After', '60').send('잠시 후 다시 확인해주세요.');
    }
    // Query names are display hints only and never placed in a shared cache.
    res.set('Cache-Control', 'private, max-age=60');
    res.set('X-Content-Type-Options', 'nosniff');
    res.set('Referrer-Policy', 'strict-origin-when-cross-origin');
    return res.status(200).type('html').send(renderStockLanding(stock, snapshot, req.query?.name));
  };
}

module.exports = { parseStockPath, loadPublicSnapshot, renderStockLanding, createStockLandingHandler };
