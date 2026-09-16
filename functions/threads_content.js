'use strict';

const {sectorArtForAnalysis} = require('./instagram_sector_art');
const {VERSION, validateThreadsEditorial, editThreadsAnalysis} = require('./threads_editorial');
function readableParagraph(text) {
  const sentences=Array.from(new Intl.Segmenter('ko',{granularity:'sentence'}).segment(text),s=>s.segment.trim());
  const blocks=[];let current='';
  for(const sentence of sentences){
    if(current&&(current.length>=70||current.length+sentence.length+1>110)){blocks.push(current);current='';}
    current=current?`${current} ${sentence}`:sentence;
  }
  if(current)blocks.push(current);
  return blocks.join('\n\n');
}

function splitPosts(paragraphs, limit = 480) {
  const parts = [];
  let current = '';
  for (const paragraph of paragraphs) {
    if (paragraph.length > limit) throw new Error('THREADS_POST_TOO_LONG');
    const next = current ? `${current}\n\n${paragraph}` : paragraph;
    if (next.length > limit) { parts.push(current); current = paragraph; }
    else current = next;
  }
  if (current) parts.push(current);
  return parts.map((text, index) => ({text, mediaType:index === 0 ? 'CAROUSEL' : 'TEXT', replyToPrevious:index > 0}));
}

// Keep the long analysis outside the two-image carousel.
async function createThreadsDraft(analysis, options = {}) {
  if (!analysis?.name || !analysis?.ticker || !analysis?.summary?.trim()) {
    throw new Error('THREADS_ANALYSIS_REQUIRED');
  }
  const asOf = analysis.updatedAt || analysis.generatedAt;
  if (!asOf || !Number.isFinite(Date.parse(asOf))) throw new Error('THREADS_DATE_REQUIRED');
  const editorial = options.editorial ? validateThreadsEditorial(options.editorial, analysis) : await editThreadsAnalysis(analysis, options);
  const last=analysis.name.charCodeAt(analysis.name.length-1);
  const ending=last>=0xAC00&&last<=0xD7A3&&(last-0xAC00)%28===0?'야':'이야';
  const intro = `오늘의 AI종목분석은 ${analysis.name}${ending}`;
  const riskIndex=editorial.paragraphs.findIndex(p=>p.sourceIds[0]==='risks');
  const copy=editorial.paragraphs.map((p,i)=>`${i===0?'🔎 ':i===riskIndex?'⚠️ ':''}${readableParagraph(p.text)}`);
  const paragraphs = [intro, ...copy];
  const body = paragraphs.join('\n\n');
  // Keep two short paragraphs per entry instead of packing a dense wall of text.
  const groups=[`${intro}\n\n${copy.slice(0,2).join('\n\n')}`,copy.slice(2,4).join('\n\n'),copy.slice(4,6).join('\n\n'),copy.slice(6,8).join('\n\n')];
  if(groups.some(p=>p.length>480))throw new Error('THREADS_POST_TOO_LONG');
  const posts=groups.map((text,i)=>({text,mediaType:i===0?'CAROUSEL':'TEXT',replyToPrevious:i>0}));
  return {
    platform: 'threads', status: 'draft', editorialVersion:VERSION, name: analysis.name,
    ticker: analysis.ticker, asOf, imageCount: 2,
    images:[{kind:'overview',alt:`${analysis.name} AI 콘셉트 이미지와 핵심 분석`},{kind:'score',alt:`${analysis.name} AI 분석 점수와 항목별 평가`}],
    image: sectorArtForAnalysis(analysis),
    imageAlt: `${analysis.name}의 사업 분야를 표현한 콘셉트 이미지`,
    body, editorial, posts, characterCount: Array.from(body).length,
    publishingNote: '첫 글에 이미지 두 장을 묶고 나머지는 답글로 연결합니다. 실제 게시 상태는 서버 작업 기록에서 확인합니다.',
  };
}

module.exports = {createThreadsDraft, splitPosts};
