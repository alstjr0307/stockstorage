const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { collectNightFuturesQuotes } = require('./night_futures_stream');

function socketClass() {
  return class Socket extends EventEmitter {
    static instance;
    sent = [];
    constructor() { super(); this.constructor.instance = this; }
    send(value) { this.sent.push(JSON.parse(value)); }
    terminate() { this.terminated = true; this.emit('close'); }
  };
}
function fields(symbol, price) {
  const f = Array(50).fill('0');
  Object.assign(f, { 0: symbol, 2: '47.3', 3: '5', 4: '3.25', 5: String(price), 10: '1882' });
  return f.join('^');
}

test('keeps both subscriptions open for late KOSDAQ trades and preserves latest quote', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const WebSocket = socketClass();
  const observed = [];
  const result = collectNightFuturesQuotes('test', ['A01612', 'A06612'], {
    WebSocket, onQuote: (symbol) => observed.push(symbol),
  });
  const ws = WebSocket.instance;
  ws.emit('open');
  assert.deepEqual(ws.sent.map(m => m.body.input.tr_key), ['A01612', 'A06612']);
  ws.emit('message', `0|H0MFCNT0|001|${fields('A01612', 1080)}`);
  t.mock.timers.tick(20000);
  assert.equal(ws.terminated, undefined);
  ws.emit('message', `0|H0MFCNT0|002|${fields('A06612', 1407.7)}^${fields('A06612', 1408)}`);
  t.mock.timers.tick(30000);
  const quotes = await result;
  assert.equal(quotes.get('A06612').price, 1408);
  assert.equal(quotes.get('A06612').change, -47.3);
  assert.equal(quotes.get('A01612').price, 1080);
  assert.equal(observed.length, 3);
  assert.equal(ws.terminated, true);
});

test('no trades produces no fabricated quotes', async t => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const WebSocket = socketClass();
  const result = collectNightFuturesQuotes('test', ['A06612'], { WebSocket });
  t.mock.timers.tick(50000);
  assert.equal((await result).size, 0);
});

test('subscription rejection is reported and socket closed', async () => {
  const WebSocket = socketClass();
  const result = collectNightFuturesQuotes('test', ['A06612'], { WebSocket });
  const rejected = assert.rejects(result, /subscription rejected: INVALID/);
  WebSocket.instance.emit('message', JSON.stringify({body: {rt_cd: '1', msg_cd: 'INVALID'}}));
  await rejected;
  assert.equal(WebSocket.instance.terminated, true);
});
