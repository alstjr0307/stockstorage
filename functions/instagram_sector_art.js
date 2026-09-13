'use strict';

const SECTOR_ART = {
  semiconductor: {
    label: '반도체·AI 인프라',
    file: 'semiconductor-ai.png',
  },
  battery: {
    label: '배터리·에너지',
    file: 'battery-energy.png',
  },
  bio: {
    label: '바이오·제약',
    file: 'bio-pharma.png',
  },
  finance: {
    label: '금융·보험',
    file: 'finance-insurance.png',
  },
  mobility: {
    label: '자동차·물류',
    file: 'mobility-logistics.png',
  },
  platform: {
    label: '플랫폼·콘텐츠',
    file: 'platform-commerce.png',
  },
  industrial: {
    label: '산업재·방산',
    file: 'industrial-aerospace.png',
  },
  consumer: {
    label: '통신·소비재',
    file: 'telecom-consumer.png',
  },
};

const TICKER_SECTOR = {
  '000660': 'semiconductor',
  '005930': 'semiconductor',
  '003670': 'battery',
  '006400': 'battery',
  '051910': 'battery',
  '096770': 'battery',
  '373220': 'battery',
  '068270': 'bio',
  '207940': 'bio',
  '000810': 'finance',
  '032830': 'finance',
  '055550': 'finance',
  '086790': 'finance',
  '105560': 'finance',
  '316140': 'finance',
  '000270': 'mobility',
  '005380': 'mobility',
  '012330': 'mobility',
  '086280': 'mobility',
  '035420': 'platform',
  '035720': 'platform',
  '005490': 'industrial',
  '012450': 'industrial',
  '015760': 'industrial',
  '028260': 'industrial',
  '047810': 'industrial',
  '066570': 'consumer',
  '017670': 'consumer',
  '030200': 'consumer',
  '033780': 'consumer',
};

function sectorArtForAnalysis(analysis = {}) {
  const direct = TICKER_SECTOR[String(analysis.ticker || '').padStart(6, '0')];
  const text = [
    analysis.name,
    analysis.companyOverview,
    ...(Array.isArray(analysis.themePeers) ? analysis.themePeers : []),
  ].filter(Boolean).join(' ');
  const fallback =
    /반도체|HBM|메모리|파운드리|AI|데이터센터/.test(text) ? 'semiconductor'
    : /배터리|2차전지|전지|양극재|ESS|에너지/.test(text) ? 'battery'
    : /바이오|제약|의약|항체|임상/.test(text) ? 'bio'
    : /은행|금융|보험|증권|카드/.test(text) ? 'finance'
    : /자동차|모빌리티|부품|물류|글로비스/.test(text) ? 'mobility'
    : /플랫폼|커머스|콘텐츠|검색|광고|클라우드|웹툰/.test(text) ? 'platform'
    : /통신|소비재|담배|미디어|가전/.test(text) ? 'consumer'
    : 'industrial';
  const slug = direct || fallback;
  return { slug, ...SECTOR_ART[slug] };
}

module.exports = { SECTOR_ART, TICKER_SECTOR, sectorArtForAnalysis };
