const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');
const axios = require('axios');
const cheerio = require('cheerio');

const SEOUL_TZ = 'Asia/Seoul';
const NAVER_REFERER = 'https://finance.naver.com/';
const decoder = new TextDecoder('euc-kr');

const SOURCES = [
  {
    key: 'foreignTop5',
    market: 'kospi',
    marketLabel: 'KOSPI',
    investorLabel: 'foreign',
    sosok: '01',
    investorGubun: '9000',
  },
  {
    key: 'institutionTop5',
    market: 'kospi',
    marketLabel: 'KOSPI',
    investorLabel: 'institution',
    sosok: '01',
    investorGubun: '1000',
  },
  {
    key: 'foreignTop5',
    market: 'kosdaq',
    marketLabel: 'KOSDAQ',
    investorLabel: 'foreign',
    sosok: '02',
    investorGubun: '9000',
  },
  {
    key: 'institutionTop5',
    market: 'kosdaq',
    marketLabel: 'KOSDAQ',
    investorLabel: 'institution',
    sosok: '02',
    investorGubun: '1000',
  },
];

function getKstDateKey(date = new Date()) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: SEOUL_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(date);
}

function getKstDateParts(date = new Date()) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: SEOUL_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
  const parts = formatter.formatToParts(date);
  const map = {};
  for (const part of parts) {
    if (part.type !== 'literal') map[part.type] = part.value;
  }
  return {
    weekday: String(map.weekday || '').toLowerCase(),
    hour: Number(map.hour || '0'),
    minute: Number(map.minute || '0'),
  };
}

function shouldRunInvestorFlowNow(date = new Date()) {
  const { weekday, hour, minute } = getKstDateParts(date);
  const isWeekday = ['mon', 'tue', 'wed', 'thu', 'fri'].includes(weekday);
  if (!isWeekday) return false;

  // KST 기준 장마감 직후(15:35)부터 16:30까지 다중 재시도.
  const totalMinutes = hour * 60 + minute;
  const from = 15 * 60 + 35;
  const to = 16 * 60 + 30;
  return totalMinutes >= from && totalMinutes <= to;
}

function buildNaverUrl({ sosok, investorGubun }) {
  return `https://finance.naver.com/sise/sise_deal_rank_iframe.naver?sosok=${sosok}&investor_gubun=${investorGubun}&type=buy`;
}

function getNaverDateKey(date = new Date()) {
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: SEOUL_TZ,
    year: '2-digit',
    month: '2-digit',
    day: '2-digit',
  });
  return formatter.format(date).replace(/-/g, '.');
}

function parseNumber(text) {
  const value = Number(String(text || '').replace(/[^\d.-]/g, ''));
  return Number.isFinite(value) ? value : null;
}

async function fetchTop5FromNaver(config) {
  const url = buildNaverUrl(config);
  const response = await axios.get(url, {
    responseType: 'arraybuffer',
    timeout: 15000,
    headers: {
      'User-Agent': 'Mozilla/5.0',
      Referer: NAVER_REFERER,
      'Accept-Language': 'ko-KR,ko;q=0.9',
    },
  });

  const html = decoder.decode(response.data);
  const $ = cheerio.load(html);
  const expectedDate = getNaverDateKey();
  const boxes = $('div.box_type_ms').toArray();
  const targetBox =
    boxes.find((box) => {
      const dateText = $(box).find('.sise_guide_date').first().text().trim();
      return dateText === expectedDate;
    }) ??
    boxes[boxes.length - 1] ??
    null;
  const rows = [];

  if (!targetBox) {
    return [];
  }

  $(targetBox)
    .find('table.type_1 tr')
    .each((_, tr) => {
    const link = $(tr).find('a.tltle');
    if (!link.length) return;

    const href = link.attr('href') || '';
    const codeMatch = href.match(/code=(\d+)/);
    const cells = $(tr)
      .find('td')
      .map((__, td) => $(td).text().trim().replace(/\s+/g, ' '))
      .get();

    if (cells.length < 4 || !codeMatch) return;

    rows.push({
      code: codeMatch[1],
      name: link.attr('title') || link.text().trim(),
      quantity: parseNumber(cells[1]),
      amount: parseNumber(cells[2]),
      volume: parseNumber(cells[3]),
      quantityText: cells[1],
      amountText: cells[2],
      volumeText: cells[3],
    });
  });

  return rows.slice(0, 5).map((item, index) => ({
    rank: index + 1,
    ...item,
  }));
}

async function collectDailyInvestorFlow() {
  const result = {
    marketDate: getKstDateKey(),
    fetchedAt: new Date(),
    source: 'finance.naver.com',
    basis: 'market_close',
    kospi: {
      foreignTop5: [],
      institutionTop5: [],
    },
    kosdaq: {
      foreignTop5: [],
      institutionTop5: [],
    },
  };

  for (const source of SOURCES) {
    const top5 = await fetchTop5FromNaver(source);
    result[source.market][source.key] = top5;
  }

  return result;
}

async function saveDailyInvestorFlow(data) {
  const db = getFirestore();
  await db.collection('market_investor_flow').doc(data.marketDate).set(data, {
    merge: true,
  });
}

const crawlDailyInvestorFlow = onSchedule(
  {
    schedule: 'every 5 minutes',
    timeZone: SEOUL_TZ,
    region: 'asia-northeast3',
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async () => {
    if (!shouldRunInvestorFlowNow()) {
      return;
    }
    const data = await collectDailyInvestorFlow();
    await saveDailyInvestorFlow(data);
  },
);

module.exports = {
  crawlDailyInvestorFlow,
  collectDailyInvestorFlow,
  saveDailyInvestorFlow,
};
