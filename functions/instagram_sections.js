'use strict';

// Explicit mapping of the app's analysis fields. No rewriting, sentence
// selection or array slicing: pagination, not omission, controls length.
function analysisSections(a) {
  const sections = [];
  const value = v => v == null ? '' : String(v).trim();
  const add = (id, title, body) => {
    if (value(body)) sections.push({id, label:title, title, body:value(body)});
  };
  const fields = (obj, labels) => Object.entries(labels)
    .filter(([key]) => value(obj?.[key]))
    .map(([key,label]) => `${label}: ${value(obj[key])}`).join('\n');
  add('companyOverview','기업 소개',a.companyOverview);
  add('profile','업종과 테마',fields(a,{sector:'업종',theme:'테마'}) +
    (a.themePeers?.length ? '\n\n관련 기업: '+a.themePeers.join(' · ') : ''));
  add('score','AI 점수와 평가',[
    Number.isFinite(a.score) ? `종합 ${a.score} / 100` : '',a.scoreLabel,
    fields(a.subScores,{priceTrend:'차트',newsImpact:'뉴스',fundamentals:'재무',momentumFlow:'모멘텀',riskLevel:'리스크 방어 점수'}),
    a.subScores ? '각 항목은 100점 만점. 리스크 점수는 높을수록 위험이 낮다는 AI 평가입니다.' : '',
    Number.isFinite(a.scorePercentileTop) ? `최근 전체 분석 중 상위 ${a.scorePercentileTop}%` : '',
  ].filter(Boolean).join('\n\n'));
  for (const [key,title] of Object.entries({summary:'전체 요약',todayReason:'오늘 주가가 움직인 이유',fundamentals:'실적과 재무',technical:'차트 흐름',news:'뉴스 흐름',momentum:'수급과 모멘텀'})) add(key,title,a[key]);
  (a.catalysts||[]).forEach((c,i)=>add(`catalysts.${i}`,'주요 재료',[
    c.title, fields(c,{kind:'분류',impact:'영향',timeline:'시점',confidence:'확신도'}),c.detail,
  ].filter(Boolean).join('\n\n')));
  add('valuation','밸류에이션',fields(a.valuation,{perVerdict:'PER 평가',pbrVerdict:'PBR 평가',forwardPer:'선행 PER',sectorAveragePer:'업종 평균 PER',reasoning:'평가 근거'}));
  add('peerComparison','동종 기업 비교',[
    a.peerPerAverage,
    ...(a.valuation?.peerComparison||[]).map(p=>`${p.name} · PER ${p.per ?? '미제공'} · PBR ${p.pbr ?? '미제공'}`),
  ].filter(Boolean).join('\n\n'));
  add('technicalDetail','기술 지표 상세',fields(a.technicalDetail,{maPosition:'이동평균',rsiVerdict:'RSI',bollingerVerdict:'볼린저밴드',support:'지지선',resistance:'저항선',pattern:'패턴',reasoning:'해석'}));
  for(const [key,title] of Object.entries({bull:'상승 시나리오',base:'기본 시나리오',bear:'하락 시나리오'})) {
    const s=a.scenarios?.[key];
    if(s) add(`scenarios.${key}`,title,fields(s,{trigger:'조건',priceTarget:'예상 범위',probability:'AI 추정 확률 (0~1)',narrative:'시나리오 해설'})+'\n\nAI가 제시한 조건부 가정이며 실제 수익률이나 확률을 보장하지 않습니다.');
  }
  add('risks','위험 요인',(a.risks||[]).map(v=>'• '+v).join('\n\n'));
  (a.risksDetailed||[]).forEach((r,i)=>add(`risksDetailed.${i}`,'상세 리스크',fields(r,{category:'분류',severity:'심각도',probability:'발생 가능성',description:'위험 내용',mitigant:'확인·대응 포인트'})));
  add('timing','기간별 전망과 판단',fields(a.timing,{shortTerm:'단기 전망',midTerm:'중기 전망',action:'앱 AI 판단',actionReason:'판단 근거'}));
  (a.sections||[]).forEach((s,i)=>add(`sections.${i}`,s.title||'추가 분석',s.body));
  return sections;
}

module.exports = {analysisSections};
