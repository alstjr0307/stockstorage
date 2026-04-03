const fs = require('fs');
const path = require('path');
const https = require('https');
const iconv = require('iconv-lite');

const LIST_URL =
  'https://kind.krx.co.kr/corpgeneral/corpList.do?method=download&searchType=13';

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https
      .get(
        url,
        {
          headers: {
            'User-Agent': 'Mozilla/5.0',
            Referer:
              'https://kind.krx.co.kr/corpgeneral/corpList.do?method=loadInitPage',
            Accept:
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        },
        (res) => {
          const chunks = [];
          res.on('data', (d) => chunks.push(d));
          res.on('end', () => {
            try {
              const body = iconv.decode(Buffer.concat(chunks), 'euc-kr');
              resolve(body);
            } catch (e) {
              reject(e);
            }
          });
        },
      )
      .on('error', reject);
  });
}

function stripHtml(text) {
  return String(text || '')
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

function parseRows(html) {
  const rows = [];
  const trRegex = /<tr[\s\S]*?>([\s\S]*?)<\/tr>/gi;
  let trMatch;
  while ((trMatch = trRegex.exec(html)) !== null) {
    const trInner = trMatch[1];
    const tdRegex = /<td[^>]*>([\s\S]*?)<\/td>/gi;
    const cells = [];
    let tdMatch;
    while ((tdMatch = tdRegex.exec(trInner)) !== null) {
      cells.push(stripHtml(tdMatch[1]));
    }
    if (cells.length < 3) continue;

    const name = cells[0] || '';
    const market = cells[1] || '';
    const ticker = cells[2] || '';
    if (!name || !ticker) continue;
    if (!/^\d{6}$/.test(ticker)) continue;
    rows.push({ ticker, name, market });
  }
  return rows;
}

function generateAliasParts(name) {
  const base = new Set();
  const extra = new Set();
  const raw = String(name || '').trim();
  if (!raw) return { base, extra };
  base.add(raw);

  const compact = raw.replace(/\s+/g, '');
  if (compact && compact !== raw) base.add(compact);

  const suffixes = [
    '홀딩스',
    '지주',
    '전자',
    '공업',
    '바이오',
    '제약',
    '솔루션',
    '에너지',
    '산업',
    '건설',
    '화학',
    '물산',
    '식품',
    '증권',
    '금융',
    '전기',
    '통신',
  ];

  for (const sfx of suffixes) {
    if (!compact.endsWith(sfx)) continue;
    const stem = compact.slice(0, compact.length - sfx.length);
    if (stem.length >= 2) extra.add(stem);
  }

  // User-requested patterns:
  // 4글자: 1,3글자 조합 / 5글자: 1,3 + 1,4글자 조합
  if (/^[가-힣]{4}$/.test(compact)) {
    extra.add(`${compact[0]}${compact[2]}`);
  } else if (/^[가-힣]{5}$/.test(compact)) {
    extra.add(`${compact[0]}${compact[2]}`);
    extra.add(`${compact[0]}${compact[3]}`);
  }

  return { base, extra };
}

function buildAliasJson(rows) {
  const byTicker = new Map();
  const extraAliasOwners = new Map();

  const addOwner = (alias, ticker) => {
    const key = String(alias || '').trim();
    if (!key || key.length < 2) return;
    if (!extraAliasOwners.has(key)) extraAliasOwners.set(key, new Set());
    extraAliasOwners.get(key).add(ticker);
  };

  for (const row of rows) {
    if (!byTicker.has(row.ticker)) {
      byTicker.set(row.ticker, {
        ticker: row.ticker,
        name: row.name,
        baseAliases: new Set(),
        extraAliases: new Set(),
      });
    }
    const item = byTicker.get(row.ticker);
    const { base, extra } = generateAliasParts(row.name);
    for (const alias of base) item.baseAliases.add(alias);
    for (const alias of extra) {
      item.extraAliases.add(alias);
      addOwner(alias, row.ticker);
    }
  }

  return Array.from(byTicker.values())
    .map((x) => {
      const aliases = new Set();
      for (const a of x.baseAliases) {
        if (a !== x.name) aliases.add(a);
      }
      for (const a of x.extraAliases) {
        const owners = extraAliasOwners.get(a);
        if (owners && owners.size === 1 && a !== x.name) aliases.add(a);
      }
      return {
        ticker: x.ticker,
        name: x.name,
        aliases: Array.from(aliases).sort(),
      };
    })
    .sort((a, b) => a.ticker.localeCompare(b.ticker));
}

async function main() {
  const html = await fetchText(LIST_URL);
  const rows = parseRows(html);
  const aliasData = buildAliasJson(rows);

  const outPath = path.join(__dirname, 'stock_aliases.generated.json');
  fs.writeFileSync(outPath, JSON.stringify(aliasData, null, 2), 'utf8');

  console.log(`[done] rows=${rows.length} aliases=${aliasData.length}`);
  console.log(`[done] wrote=${outPath}`);
}

main().catch((err) => {
  console.error('[fatal]', err);
  process.exit(1);
});
