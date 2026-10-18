const { HttpsError } = require('firebase-functions/v2/https');
const axios = require('axios');

const ADMIN_UIDS = new Set(['1KzEXKZMoFaYOymYyoI283AR3Y32', 'v4a3ClF3FhWGXsGnZ29wyvQNSCX2']);
const ACCOUNT = 'accounts/pub-6925657557995580';
const APP_IDS = ['ca-app-pub-6925657557995580~9784755864', 'ca-app-pub-6925657557995580~9589222853'];

function dateKey(now, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  return ['year', 'month', 'day'].map(k => parts.find(p => p.type === k).value).join('');
}
function shiftDay(key, delta) {
  const date = new Date(Date.UTC(+key.slice(0, 4), +key.slice(4, 6) - 1, +key.slice(6, 8) + delta));
  return date.toISOString().slice(0, 10).replaceAll('-', '');
}
function apiDate(key) { return {year: +key.slice(0, 4), month: +key.slice(4, 6), day: +key.slice(6, 8)}; }
function period(now, timeZone) {
  const today = dateKey(now, timeZone);
  const monthStart = `${today.slice(0, 6)}01`;
  const weekStart = shiftDay(today, -6);
  return {today, yesterday: shiftDay(today, -1), monthStart, weekStart,
    start: monthStart < weekStart ? monthStart : weekStart};
}
function blank() { return {earnings: 0, impressions: 0, clicks: 0, requests: 0}; }
function total(rows) {
  const result = blank();
  for (const row of rows) for (const key of Object.keys(result)) result[key] += row[key];
  return {...result, ecpm: result.impressions ? result.earnings * 1000 / result.impressions : 0};
}
function number(value) {
  if (value === undefined || !/^\d+$/.test(String(value))) throw new Error('Invalid report metric');
  const n = Number(value);
  if (!Number.isSafeInteger(n)) throw new Error('Invalid report metric');
  return n;
}

function parseReport(messages, account, dates, now) {
  if (!Array.isArray(messages)) throw new Error('Invalid report');
  const header = messages.find(m => m.header)?.header;
  const footer = messages.find(m => m.footer)?.footer;
  if (!header || !footer || footer.warnings?.length) throw new Error('Incomplete report');
  const currency = header.localizationSettings?.currencyCode;
  if (!currency || currency !== account.currencyCode) throw new Error('Unexpected currency');
  const rows = messages.filter(m => m.row).map(m => m.row);
  if (Number(footer.matchingRowCount ?? 0) !== rows.length) throw new Error('Truncated report');
  const byDay = {};
  for (let key = dates.start; key <= dates.today; key = shiftDay(key, 1)) byDay[key] = {date: key, ...blank()};
  for (const row of rows) {
    const key = row.dimensionValues?.DATE?.value;
    const app = row.dimensionValues?.APP?.value;
    if (!APP_IDS.includes(app) || !byDay[key]) throw new Error('Unexpected report row');
    const metrics = row.metricValues;
    byDay[key].earnings += number(metrics?.ESTIMATED_EARNINGS?.microsValue) / 1e6;
    byDay[key].impressions += number(metrics?.IMPRESSIONS?.integerValue);
    byDay[key].clicks += number(metrics?.CLICKS?.integerValue);
    byDay[key].requests += number(metrics?.AD_REQUESTS?.integerValue);
  }
  const days = Object.values(byDay);
  return {
    currency, timeZone: account.reportingTimeZone, reportDate: dates.today,
    fetchedAt: now.toISOString(), source: 'AdMob Network',
    today: total([byDay[dates.today]]), yesterday: total([byDay[dates.yesterday]]),
    month: total(days.filter(d => d.date >= dates.monthStart)),
    week: days.filter(d => d.date >= dates.weekStart).reverse(),
  };
}

function createRevenueHandler({http = axios, clock = () => new Date()} = {}) {
  let cache;
  return async request => {
    // Authenticate BEFORE returning cached financial data or contacting Google.
    if (!request.auth) throw new HttpsError('unauthenticated', '관리자 로그인이 필요합니다.');
    if (!ADMIN_UIDS.has(request.auth.uid)) throw new HttpsError('permission-denied', '관리자만 조회할 수 있습니다.');
    const now = clock();
    const age = cache ? now - new Date(cache.fetchedAt) : Infinity;
    const ttl = request.data?.refresh === true ? 60000 : 300000;
    if (cache && age >= 0 && age < ttl && cache.reportDate === dateKey(now, cache.timeZone)) {
      return {...cache, cached: true};
    }
    const token = request.data?.accessToken;
    if (typeof token !== 'string' || token.length < 20 || token.length > 8192 || /\s/.test(token)) {
      throw new HttpsError('failed-precondition', '애드몹 계정을 연결해 주세요.', {reason: 'connect-required'});
    }
    const config = {headers: {Authorization: `Bearer ${token}`}, timeout: 20000};
    try {
      const {data: account} = await http.get(`https://admob.googleapis.com/v1/${ACCOUNT}`, config);
      if (account.name !== ACCOUNT || !account.reportingTimeZone || !account.currencyCode) throw new Error('Invalid account');
      const dates = period(now, account.reportingTimeZone);
      const {data: messages} = await http.post(`https://admob.googleapis.com/v1/${ACCOUNT}/networkReport:generate`, {
        reportSpec: {
          dateRange: {startDate: apiDate(dates.start), endDate: apiDate(dates.today)},
          dimensions: ['DATE', 'APP'],
          metrics: ['ESTIMATED_EARNINGS', 'IMPRESSIONS', 'CLICKS', 'AD_REQUESTS'],
          dimensionFilters: [{dimension: 'APP', matchesAny: {values: APP_IDS}}],
          maxReportRows: 1000,
          // Omit timeZone: AdMob supports the account's own default timezone.
        },
      }, config);
      cache = parseReport(messages, account, dates, now);
      return {...cache, cached: false};
    } catch (error) {
      // Never log/return Axios errors: request config contains the OAuth token.
      const status = error.response?.status;
      const disabled = error.response?.data?.error?.details?.some(d => d.reason === 'SERVICE_DISABLED');
      if (disabled) throw new HttpsError('failed-precondition', 'Google Cloud에서 AdMob API 사용 설정이 필요합니다.', {reason: 'api-disabled'});
      if (status === 401 || status === 403) throw new HttpsError('failed-precondition', '애드몹 보고서 권한이 있는 Google 계정으로 다시 연결해 주세요.', {reason: 'connect-required'});
      if (status === 429) throw new HttpsError('resource-exhausted', '조회 요청이 많습니다. 잠시 후 다시 시도해 주세요.');
      throw new HttpsError('unavailable', '애드몹 보고서를 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.');
    }
  };
}

module.exports = {createRevenueHandler, parseReport, period, dateKey, APP_IDS, ACCOUNT};
