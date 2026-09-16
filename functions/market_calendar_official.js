'use strict';

const axios = require('axios');
const cheerio = require('cheerio');

const URLS = {
  fed: 'https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm',
  ecb: 'https://www.ecb.europa.eu/press/calendars/mgcgc/html/index.en.html',
  boj: 'https://www.boj.or.jp/en/mopo/mpmsche_minu/',
  bok: 'https://www.bok.or.kr/eng/main/contents.do?menuNo=400020',
  nyse: 'https://www.nyse.com/markets/hours-calendars',
  ism: 'https://www.ismworld.org/supply-management-news-and-reports/reports/rob-report-calendar/',
};
const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
function dateString(year, month, day) {
  const value = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  const date = new Date(`${value}T12:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) throw new Error('Invalid official calendar date');
  return value;
}
function englishDate(text, year) {
  const match = text.match(/(Jan\w*|Feb\w*|Mar\w*|Apr\w*|May|Jun\w*|Jul\w*|Aug\w*|Sep\w*|Oct\w*|Nov\w*|Dec\w*)\.?\s*(\d{1,2})/i);
  return match ? dateString(year, MONTHS.indexOf(match[1].slice(0, 3).toLowerCase()) + 1, Number(match[2])) : null;
}
function event(source, kind, date, title, country = 'US', importance = 3, extra = {}) {
  return { id: `economic_${source}_${kind}_${date}`, type: 'economic', country, date,
    symbol: null, name: title, title, importance, source,
    extra: { category: kind, sourceUrl: URLS[source], dateBasis: 'local_market', ...extra } };
}

function parseFed(html) {
  const $ = cheerio.load(html), events = [];
  $('.fomc-meeting').each((_, node) => {
    const row = $(node);
    const year = Number(row.parent().find('.panel-heading').first().text().match(/(20\d{2})/)?.[1]);
    const month = row.find('.fomc-meeting__month').text().trim().split('/').pop();
    const days = row.find('.fomc-meeting__date').text().trim();
    // Exclude unscheduled notation votes, which do not imply a press conference.
    if (!year || !/^\d{1,2}\s*[-–]\s*\d{1,2}\*?$/.test(days)) return;
    const date = englishDate(`${month} ${days.match(/[-–]\s*(\d+)/)[1]}`, year);
    if (!date) throw new Error('FOMC month format changed');
    events.push(event('fed', 'rate', date, '미국 FOMC 금리 결정'));
    events.push(event('fed', 'press', date, '미국 연준 의장 기자회견'));
    if (days.includes('*')) events.push(event('fed', 'projections', date, '미국 FOMC 경제전망·점도표'));
    const released = row.find('.fomc-meeting__minutes').text().match(/Released\s+([A-Za-z]+\s+\d+,\s*(20\d{2}))/);
    const minutesDate = released ? englishDate(released[1], Number(released[2]))
      : new Date(new Date(`${date}T12:00:00Z`).getTime() + 21 * 86400000).toISOString().slice(0, 10);
    events.push(event('fed', 'minutes', minutesDate, '미국 FOMC 의사록 공개', 'US', 2,
      { scheduledByRule: !released, meetingDate: date }));
  });
  return events;
}

function parseEcb(html) {
  const $ = cheerio.load(html), events = [];
  $('dt').each((_, node) => {
    const text = $(node).next('dd').text();
    if (!/monetary policy meeting/i.test(text) || /non-monetary/i.test(text) || !/Day 2/i.test(text)) return;
    const m = $(node).text().match(/(\d{2})\/(\d{2})\/(20\d{2})/);
    if (!m) throw new Error('ECB date format changed');
    events.push(event('ecb', 'rate', dateString(+m[3], +m[2], +m[1]), '유로존 ECB 금리 결정·기자회견', 'EU'));
  });
  return events;
}

function parseBoj(html) {
  const $ = cheerio.load(html), events = [];
  $('table').each((_, table) => {
    const year = Number($(table).find('caption').text().match(/20\d{2}/)?.[0]);
    if (!year || !/Date of MPM/.test($(table).text())) return;
    $(table).find('tbody tr').each((__, row) => {
      const cells = $(row).find('td');
      const text = cells.eq(0).text();
      const lastDay = text.match(/,\s*(\d{1,2})\s*\(/)?.[1];
      const firstDate = englishDate(text, year);
      if (!firstDate || !lastDay) return;
      const date = dateString(year, +firstDate.slice(5, 7), +lastDay);
      events.push(event('boj', 'rate', date, '일본 BOJ 금리 결정', 'JP'));
      for (const [index, kind, title] of [[2, 'opinions', '일본 BOJ 주요 의견 공개'], [3, 'minutes', '일본 BOJ 의사록 공개']]) {
        const value = cells.eq(index).text();
        const releaseYear = Number(value.match(/20\d{2}/)?.[0] || year);
        const releaseDate = englishDate(value, releaseYear);
        if (releaseDate) events.push(event('boj', kind, releaseDate, title, 'JP', 2));
      }
    });
  });
  return events;
}

function parseBok(html) {
  const $ = cheerio.load(html), events = [];
  $('table').each((_, table) => {
    // Year is the preceding heading outside the table's wrapping div.
    const wrapper = $(table).parent();
    const heading = wrapper.prevAll().filter((__, el) => /^20\d{2}$/.test($(el).text().trim())).first();
    const year = Number(heading.text().trim());
    if (!year) return;
    $(table).find('td').each((__, cell) => {
      const date = englishDate($(cell).text(), year);
      if (date) events.push(event('bok', 'rate', date, '한국은행 금융통화위원회 기준금리 결정', 'KR'));
    });
  });
  return events;
}

function parseNyse(html) {
  const $ = cheerio.load(html), events = [];
  const table = $('table').filter((_, el) => /Holiday/.test($(el).find('thead').text())).first();
  const years = table.find('thead th').toArray().slice(1).map(el => Number($(el).text()));
  const labels = ['신정', '마틴 루터 킹 데이', '대통령의 날', '성금요일', '메모리얼 데이', '준틴스', '독립기념일', '노동절', '추수감사절', '크리스마스'];
  table.find('tbody tr').each((index, row) => {
    $(row).find('td').each((column, cell) => {
      const date = englishDate($(cell).text(), years[column]);
      if (date) events.push(event('nyse', 'holiday', date, `미국 증시 휴장 · ${labels[index] || $(row).find('th').text()}`, 'US', 2));
    });
  });
  // Monthly standard equity/ETF options last trading day, moved back for holidays.
  // Weekly and product-specific expirations deliberately have separate semantics.
  const holidays = new Set(events.map(e => e.date));
  for (const year of years.filter(y => y >= 2026)) {
    for (let month = 1; month <= 12; month++) {
      let d = new Date(`${dateString(year, month, 1)}T12:00:00Z`);
      d.setUTCDate(1 + (5 - d.getUTCDay() + 7) % 7 + 14);
      while ([0, 6].includes(d.getUTCDay()) || holidays.has(d.toISOString().slice(0, 10))) d.setUTCDate(d.getUTCDate() - 1);
      events.push(event('nyse', 'options', d.toISOString().slice(0, 10),
        month % 3 === 0 ? '미국 선물·옵션 동시 만기 (주요 월물)' : '미국 주식·ETF 옵션 월물 만기', 'US', month % 3 === 0 ? 3 : 2,
        { scheduledByRule: true, sourceUrl: 'https://www.nyse.com/publicdocs/nyse/ICE_NYSE_2026_Yearly_Trading_Calendar.pdf' }));
    }
  }
  // Explicit exchange-announced early closes; do not treat these as full holidays.
  if (years.includes(2026)) {
    for (const date of ['2026-11-27', '2026-12-24']) {
      events.push(event('nyse', 'early_close', date, '미국 증시 조기 폐장 (현지 13시)', 'US', 2));
    }
  }
  return events;
}

// Official 2026 release table, verified 2026-09-13. The publisher's old URL
// currently returns 404 to the server; do not extrapolate business-day rules
// (January and holiday exceptions differ). Warn explicitly when coverage expires.
function ismEvents(from) {
  if (from > '2026-12-31') throw new Error('ISM official schedule needs next-year refresh');
  const manufacturing = [5, 2, 2, 1, 1, 1, 1, 3, 1, 1, 2, 1];
  const services = [7, 4, 4, 6, 5, 3, 6, 5, 3, 5, 4, 3];
  return manufacturing.flatMap((day, i) => [
    event('ism', 'manufacturing', dateString(2026, i + 1, day), '미국 ISM 제조업 PMI 발표'),
    event('ism', 'services', dateString(2026, i + 1, services[i]), '미국 ISM 서비스업 PMI 발표'),
  ]);
}

const PARSERS = { fed: parseFed, ecb: parseEcb, boj: parseBoj, bok: parseBok, nyse: parseNyse };
async function fetchOfficialCalendars(from, to, get = axios.get) {
  const results = await Promise.all(Object.entries(PARSERS).map(async ([source, parse]) => {
    try {
      const { data } = await get(URLS[source], { timeout: 15000, maxContentLength: 5 * 1024 * 1024 });
      const events = parse(data);
      if (!events.length || !events.some(e => e.date >= from)) throw new Error('No current official calendar rows parsed');
      return { source, events: events.filter(e => e.date >= from && e.date <= to) };
    } catch (e) {
      return { source, error: e.message, events: [] };
    }
  }));
  try { results.push({ source: 'ism', events: ismEvents(from).filter(e => e.date >= from && e.date <= to) }); }
  catch (e) { results.push({ source: 'ism', error: e.message, events: [] }); }
  return results;
}

module.exports = { fetchOfficialCalendars, PARSERS, URLS, ismEvents, dateString };
