const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DEFAULT_SOURCES = [
  {
    name: 'Google News KR Market',
    url: 'https://news.google.com/rss/search?q=%EC%A6%9D%EC%8B%9C%20OR%20%EC%BD%94%EC%8A%A4%ED%94%BC%20OR%20%ED%99%98%EC%9C%A8%20when%3A1d&hl=ko&gl=KR&ceid=KR%3Ako',
  },
  {
    name: 'Google News US Market',
    url: 'https://news.google.com/rss/search?q=stock%20market%20futures%20OR%20Federal%20Reserve%20OR%20earnings%20when%3A1d&hl=en-US&gl=US&ceid=US%3Aen',
  },
  {
    name: 'Google News Korea Stocks',
    url: 'https://news.google.com/rss/search?q=%EC%BD%94%EC%8A%A4%EB%8B%A5%20OR%20%EB%B0%98%EB%8F%84%EC%B2%B4%20OR%202%EC%B0%A8%EC%A0%84%EC%A7%80%20when%3A1d&hl=ko&gl=KR&ceid=KR%3Ako',
  },
  {
    name: 'Yahoo Finance',
    url: 'https://finance.yahoo.com/news/rssindex',
  },
];

const IMPORTANT_KEYWORDS = [
  'fed',
  'fomc',
  'inflation',
  'cpi',
  'ppi',
  'pce',
  'treasury',
  'yield',
  'oil',
  'earnings',
  'guidance',
  'tariff',
  'chip',
  'ai',
  'semiconductor',
  'futures',
  '증시',
  '코스피',
  '코스닥',
  '환율',
  '금리',
  '물가',
  '반도체',
  '실적',
  '가이던스',
  '관세',
  '유가',
  '선물',
  '연준',
  '환율',
];

const CATEGORY_RULES = [
  ['매크로', ['fed', 'fomc', 'inflation', 'cpi', 'ppi', 'pce', 'rate', 'yield', '연준', '금리', '물가', '국채']],
  ['시장', ['stock market', 'futures', 'nasdaq', 's&p', 'dow', 'kospi', 'kosdaq', '증시', '코스피', '코스닥', '선물']],
  ['섹터', ['semiconductor', 'chip', 'ai', 'oil', 'battery', '반도체', '2차전지', '바이오', '유가', '방산']],
  ['종목', ['earnings', 'guidance', 'shares', 'stock', '실적', '가이던스', '주가', '상승', '하락']],
];

function pad2(value) {
  return String(value).padStart(2, '0');
}

function formatDate(date) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

function getKstNow() {
  return new Date(new Date().toLocaleString('en-US', { timeZone: 'Asia/Seoul' }));
}

function decodeXmlEntities(value) {
  return value
    .replace(/<!\[CDATA\[(.*?)\]\]>/gs, '$1')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
    .trim();
}

function stripHtml(value) {
  return decodeXmlEntities(value.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' '));
}

function getTag(block, tag) {
  const match = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i'));
  return match ? decodeXmlEntities(match[1]) : '';
}

function normalizeUrl(url) {
  if (!url) return '';
  try {
    const parsed = new URL(url);
    parsed.searchParams.delete('utm_source');
    parsed.searchParams.delete('utm_medium');
    parsed.searchParams.delete('utm_campaign');
    return parsed.toString();
  } catch (_) {
    return url.trim();
  }
}

function sourceFromTitle(title) {
  const parts = title.split(' - ');
  if (parts.length < 2) return '';
  return parts[parts.length - 1].trim();
}

function removePublisherFromTitle(title) {
  const parts = title.split(' - ');
  if (parts.length < 2) return title;
  return parts.slice(0, -1).join(' - ').trim();
}

function parseRss(xml, sourceName) {
  const itemMatches = xml.match(/<item[\s\S]*?<\/item>/gi) || [];
  return itemMatches.map((block) => {
    const rawTitle = stripHtml(getTag(block, 'title'));
    const link = normalizeUrl(stripHtml(getTag(block, 'link')));
    const description = stripHtml(getTag(block, 'description'));
    const pubDateRaw = stripHtml(getTag(block, 'pubDate'));
    const publishedAt = pubDateRaw ? new Date(pubDateRaw) : null;
    const publisher = stripHtml(getTag(block, 'source')) || sourceFromTitle(rawTitle) || sourceName;
    const title = sourceFromTitle(rawTitle) ? removePublisherFromTitle(rawTitle) : rawTitle;
    return { title, link, description, pubDateRaw, publishedAt, sourceName, publisher };
  }).filter((item) => item.title && item.link);
}

async function fetchSource(source) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), Number(process.env.NEWS_TIMEOUT_MS || 15000));
  try {
    const response = await fetch(source.url, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'stockstorage-premarket-briefing/1.0',
        Accept: 'application/rss+xml, application/xml, text/xml',
      },
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const xml = await response.text();
    return parseRss(xml, source.name);
  } finally {
    clearTimeout(timeout);
  }
}

function loadSources() {
  if (!process.env.NEWS_SOURCES_JSON) return DEFAULT_SOURCES;
  const parsed = JSON.parse(process.env.NEWS_SOURCES_JSON);
  if (!Array.isArray(parsed)) throw new Error('NEWS_SOURCES_JSON must be a JSON array.');
  return parsed;
}

function titleKey(title) {
  return title
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function scoreItem(item, now) {
  const text = `${item.title} ${item.description}`.toLowerCase();
  const keywordScore = IMPORTANT_KEYWORDS.reduce(
    (score, keyword) => score + (text.includes(keyword.toLowerCase()) ? 3 : 0),
    0
  );
  const ageHours = item.publishedAt instanceof Date && !Number.isNaN(item.publishedAt)
    ? Math.max(0, (now - item.publishedAt) / 36e5)
    : 24;
  const freshnessScore = Math.max(0, 16 - ageHours);
  const koreanBonus = /[가-힣]/.test(item.title) ? 4 : 0;
  return keywordScore + freshnessScore + koreanBonus;
}

function categorize(item) {
  const text = `${item.title} ${item.description}`.toLowerCase();
  const found = CATEGORY_RULES.find(([, words]) => words.some((word) => text.includes(word.toLowerCase())));
  return found ? found[0] : '기타';
}

function dedupeAndRank(items, now) {
  const seen = new Map();
  for (const item of items) {
    const key = titleKey(item.title);
    const scored = { ...item, score: scoreItem(item, now), category: categorize(item) };
    const existing = seen.get(key);
    if (!existing || scored.score > existing.score) seen.set(key, scored);
  }

  return Array.from(seen.values())
    .sort((a, b) => b.score - a.score)
    .slice(0, Number(process.env.MAX_BRIEFING_ITEMS || 18));
}

function formatSourceLine(item, index) {
  const publisher = item.publisher ? ` / ${item.publisher}` : '';
  const published = item.publishedAt instanceof Date && !Number.isNaN(item.publishedAt)
    ? ` / ${item.publishedAt.toISOString()}`
    : '';
  return `${index + 1}. [${item.category}] ${item.title}${publisher}${published}\n   ${item.link}`;
}

function buildFallbackBriefing(items, kstNow) {
  const date = formatDate(kstNow);
  const grouped = new Map();
  for (const item of items) {
    if (!grouped.has(item.category)) grouped.set(item.category, []);
    grouped.get(item.category).push(item);
  }

  const order = ['매크로', '시장', '섹터', '종목', '기타'];
  const lines = [
    `# 장전 뉴스 브리핑 (${date})`,
    '',
    '## 한줄 요약',
    items[0]
      ? `오늘 장전 체크 포인트는 ${items.slice(0, 3).map((item) => item.title).join(' / ')} 입니다.`
      : '수집된 주요 뉴스가 없습니다.',
    '',
  ];

  for (const category of order) {
    const categoryItems = grouped.get(category) || [];
    if (!categoryItems.length) continue;
    lines.push(`## ${category}`);
    for (const item of categoryItems.slice(0, 4)) {
      lines.push(`- ${item.title} (${item.publisher || item.sourceName})`);
    }
    lines.push('');
  }

  lines.push('## 체크 포인트');
  lines.push('- 지수 선물, 환율, 국채금리, 유가 흐름을 함께 확인하세요.');
  lines.push('- 개별 종목 뉴스는 장 시작 전 거래대금과 함께 재확인하세요.');
  lines.push('');
  lines.push('## 원문');
  items.slice(0, 10).forEach((item, index) => {
    lines.push(`${index + 1}. ${item.title}`);
    lines.push(`   ${item.link}`);
  });

  return lines.join('\n');
}

function extractResponseText(data) {
  if (typeof data.output_text === 'string' && data.output_text.trim()) return data.output_text.trim();
  const chunks = [];
  for (const output of data.output || []) {
    for (const content of output.content || []) {
      if (content.type === 'output_text' && content.text) chunks.push(content.text);
    }
  }
  return chunks.join('\n').trim();
}

async function generateWithOpenAI(items, kstNow) {
  if (!process.env.OPENAI_API_KEY) return null;

  const input = [
    `기준일: ${formatDate(kstNow)} KST`,
    '아래 뉴스 목록만 근거로 한국어 장전 뉴스 브리핑을 작성해.',
    '형식: 제목 1개, 한줄요약 2문장, 매크로/시장/섹터/종목 섹션, 마지막 체크포인트 3개.',
    '주의: 투자 조언처럼 단정하지 말고, 확인이 필요한 내용은 "~관찰"처럼 표현해.',
    '',
    items.map(formatSourceLine).join('\n'),
  ].join('\n');

  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: process.env.OPENAI_MODEL || 'gpt-4.1-mini',
      instructions: '너는 한국 개인투자자를 위한 장전 뉴스 브리핑 편집자다. 과장 없이, 핵심만 압축한다.',
      input,
      max_output_tokens: Number(process.env.OPENAI_MAX_OUTPUT_TOKENS || 1400),
    }),
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`OpenAI API failed: ${response.status} ${JSON.stringify(data)}`);
  }
  return extractResponseText(data);
}

function initializeFirebase() {
  if (admin.apps.length) return admin.firestore();
  let serviceAccount;
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  } else {
    const serviceAccountPath = path.join(__dirname, 'service-account.json');
    if (!fs.existsSync(serviceAccountPath)) return null;
    serviceAccount = require(serviceAccountPath);
  }
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  return admin.firestore();
}

async function saveToFirestore(payload) {
  if (process.env.SKIP_FIREBASE === '1') return;
  const db = initializeFirebase();
  if (!db) {
    console.log('Firebase service account not found. Skipping Firestore save.');
    return;
  }
  await db.collection('premarket_briefings').doc(payload.dateKey).set(payload, { merge: true });
  await db.collection('premarket_briefings_meta').doc('latest').set(payload, { merge: true });
  console.log(`Saved briefing to Firestore: premarket_briefings/${payload.dateKey}`);
}

async function sendFcmNotification(payload) {
  if (process.env.SEND_FCM !== '1') return;
  initializeFirebase();
  await admin.messaging().send({
    topic: process.env.FCM_TOPIC || 'stock_alerts',
    notification: {
      title: `장전 브리핑 ${payload.dateKey}`,
      body: payload.summary,
    },
    data: {
      type: 'premarket_briefing',
      dateKey: payload.dateKey,
    },
  });
  console.log('Sent FCM notification.');
}

async function sendTelegram(payload) {
  const token = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_CHAT_ID;
  if (!token || !chatId) return;
  const text = payload.briefing.slice(0, 3900);
  const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
  });
  if (!response.ok) throw new Error(`Telegram send failed: ${response.status} ${await response.text()}`);
  console.log('Sent Telegram message.');
}

function writeLocalBriefing(payload) {
  const outputDir = path.join(__dirname, 'out', 'premarket');
  fs.mkdirSync(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, `${payload.dateKey}.md`);
  fs.writeFileSync(outputPath, payload.briefing, 'utf8');
  console.log(`Wrote ${outputPath}`);
}

async function main() {
  const kstNow = getKstNow();
  if (process.env.SKIP_WEEKEND !== '0') {
    const day = kstNow.getDay();
    if (day === 0 || day === 6) {
      console.log('Weekend in KST. Skipping premarket briefing.');
      return;
    }
  }

  const sources = loadSources();
  const results = await Promise.allSettled(sources.map(fetchSource));
  const items = results.flatMap((result, index) => {
    if (result.status === 'fulfilled') return result.value;
    console.warn(`Source failed: ${sources[index].name}: ${result.reason.message}`);
    return [];
  });

  const ranked = dedupeAndRank(items, new Date());
  let briefing = null;
  try {
    briefing = await generateWithOpenAI(ranked, kstNow);
  } catch (error) {
    console.warn(error.message);
  }
  if (!briefing) briefing = buildFallbackBriefing(ranked, kstNow);

  const firstLine = briefing.split('\n').find((line) => line.trim() && !line.startsWith('#')) || '';
  const payload = {
    dateKey: formatDate(kstNow),
    generatedAt: admin.firestore.Timestamp.now(),
    sourceCount: sources.length,
    itemCount: ranked.length,
    summary: firstLine.replace(/^[-*\s]+/, '').slice(0, 180),
    briefing,
    items: ranked.map((item) => ({
      title: item.title,
      link: item.link,
      publisher: item.publisher,
      sourceName: item.sourceName,
      category: item.category,
      score: Number(item.score.toFixed(2)),
      pubDateRaw: item.pubDateRaw,
    })),
  };

  writeLocalBriefing(payload);
  await saveToFirestore(payload);
  await sendFcmNotification(payload);
  await sendTelegram(payload);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
