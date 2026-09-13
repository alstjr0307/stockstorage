// 두 시장을 한 연결로 구독해 코스닥의 드문 체결도 수신한다.
async function collectNightFuturesQuotes(approval, symbols, {
  WebSocket = require('ws'),
  durationMs = 50000,
  onQuote = () => {},
} = {}) {
  return new Promise((resolve, reject) => {
    const quotes = new Map();
    const wanted = new Set(symbols);
    let settled = false;
    const ws = new WebSocket('ws://ops.koreainvestment.com:21000');
    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      ws.terminate();
      if (error) reject(error);
      else resolve(quotes);
    };
    const timer = setTimeout(() => finish(), durationMs);
    ws.on('open', () => {
      for (const symbol of wanted) {
        ws.send(JSON.stringify({
          header: { approval_key: approval, custtype: 'P', tr_type: '1', 'content-type': 'utf-8' },
          body: { input: { tr_id: 'H0MFCNT0', tr_key: symbol } },
        }));
      }
    });
    ws.on('message', (raw) => {
      if (settled) return;
      const message = raw.toString();
      if (message.startsWith('{')) {
        let data;
        try { data = JSON.parse(message); } catch (_) { return; }
        if (data.header?.tr_id === 'PINGPONG') ws.send(message);
        else if (data.body?.rt_cd && data.body.rt_cd !== '0') {
          finish(new Error(`KIS subscription rejected: ${data.body.msg_cd || 'unknown'}`));
        }
        return;
      }
      const parts = message.split('|');
      if (parts[1] !== 'H0MFCNT0' || !parts[3]) return;
      const fields = parts[3].split('^');
      // H0MFCNT0는 50개 필드. 합쳐서 전송된 체결도 각각 처리한다.
      for (let offset = 0; offset + 10 < fields.length; offset += 50) {
        const f = fields.slice(offset, offset + 50);
        const symbol = f[0];
        const price = Number(f[5]);
        if (!wanted.has(symbol) || !Number.isFinite(price) || price <= 0) continue;
        const dir = f[3] === '4' || f[3] === '5' ? -1 : 1;
        const quote = {
          price,
          change: Math.abs(Number(f[2]) || 0) * dir,
          changeRate: Math.abs(Number(f[4]) || 0) * dir,
          volume: Number(f[10]) || 0,
          timestamp: new Date(),
        };
        quotes.set(symbol, quote);
        onQuote(symbol, quote);
      }
    });
    ws.on('error', finish);
    ws.on('close', () => finish(new Error('KIS connection closed early')));
  });
}

module.exports = { collectNightFuturesQuotes };
