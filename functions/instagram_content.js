'use strict';

const path = require('node:path');
const sharp = require('sharp');
const {analysisSections} = require('./instagram_sections');
const CTA = '더 많은 종목 분석이 궁금하다면?';
const ACCOUNT = 'tf_stockstorage';
const text = (v) => typeof v === 'string' ? v.trim() : '';
const escape = (v) => String(v).replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&apos;'}[c]));
const WORD_JOINER = '⁠';
// Bind each run of non-space characters together so it cannot be split.
const joinWords = (v) => String(v).split('\n').map(line =>
  line.split(/(\s+)/).map(part => /^\s*$/.test(part) ? part : [...part].join(WORD_JOINER)).join('')
).join('\n');

function createDraft(analysis, now = new Date()) {
  const at = new Date(analysis.updatedAt);
  if (!Number.isFinite(at.getTime()) || now - at < 0 || now - at > 72 * 3600000) {
    throw new Error('STALE_ANALYSIS');
  }
  if (!text(analysis.name) || !/^[\w.-]+$/.test(analysis.ticker || '')) throw new Error('INVALID_STOCK');
  const sections = analysisSections(analysis);
  const sources = [...(analysis.sourceNews || []), ...(analysis.sourceReports || []), ...(analysis.sourceDisclosures || [])]
    .filter(s => /^https?:\/\//.test(s.url || '')).map(s => ({title: text(s.title), url: s.url}));
  if (!text(analysis.summary) || !analysis.risks?.length || !sections.length || !sources.length) throw new Error('INCOMPLETE_ANALYSIS');
  const dateLabel = new Intl.DateTimeFormat('ko-KR', {timeZone: 'Asia/Seoul', year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit', hour12:false}).format(at) + ' KST';
  const cards = [
    {label:'AI 종목 분석', title:analysis.name, body:'앱 분석 상세 리포트', cover:true},
    ...sections,
    {label:'주식저장소와 함께', title:CTA, body:'주식저장소 앱 다운로드', cta:true},
  ];
  const caption = [
    '기업 소개부터 재무·차트·수급·주요 재료·시나리오·리스크까지, 앱 AI 분석을 카드로 읽어보세요.',
    `${CTA}\n주식저장소 앱 다운로드\nhttps://tofusoft-software.github.io/Stockstorage/\n@${ACCOUNT} 프로필 링크에서도 확인할 수 있어요.`,
    'AI 분석은 오류가 있을 수 있으며 투자 판단의 참고 자료입니다. 차트 기준과 원문 출처는 앱 분석에서 확인할 수 있습니다.',
    '#주식저장소 #AI종목분석 #종목분석 #주식공부',
  ].join('\n\n');
  if ([...caption].length > 2000) throw new Error('CAPTION_TOO_LONG');
  return {schemaVersion:3, status:'draft', account:ACCOUNT, analysisAt:at.toISOString(), dateLabel,
    ticker:analysis.ticker, name:analysis.name, cards, caption, sources};
}

// Measure the same font/box used in the final image. Preserve every character,
// preferring a paragraph or sentence boundary when a section needs another page.
async function paginateSection(card) {
  const pages=[]; let rest=card.body;
  const fits=async value=>{
    try {await textImage(value,872,780,32,32,'#172C29');return true;}
    catch(e) {if(e.message==='CARD_TEXT_OVERFLOW')return false;throw e;}
  };
  while(rest) {
    if(await fits(rest)) {pages.push(rest);break;}
    const chars=[...rest];let low=1,high=chars.length,best=0;
    while(low<=high) {
      const mid=Math.floor((low+high)/2);
      if(await fits(chars.slice(0,mid).join(''))) {best=mid;low=mid+1;} else high=mid-1;
    }
    if(!best) throw new Error('CARD_TEXT_OVERFLOW');
    const prefix=chars.slice(0,best).join('');
    const boundaries=[...prefix.matchAll(/\n\n|[.!?]\s+/g)].map(m=>m.index+m[0].length);
    const preferred=boundaries.filter(n=>n>=prefix.length*0.4).at(-1)
      || [...prefix.matchAll(/\s+/g)].map(m=>m.index+m[0].length).at(-1);
    const split=preferred||prefix.length;
    pages.push(rest.slice(0,split));rest=rest.slice(split);
  }
  return pages.map((body,i)=>({...card,body,fragment:i+1,fragments:pages.length}));
}

async function createSeries(analysis, now = new Date()) {
  const draft=createDraft(analysis,now);
  const sections=draft.cards.slice(1,-1);
  const transcript=sections.map(c=>`[${c.title}]\n${c.body}`).join('\n\n');
  const pages=await paginateSection({id:'analysis',title:'앱 AI 분석 상세',label:'전체 분석',body:transcript});
  let offset=0;
  const ranges=sections.map(c=>{
    const start=offset;offset+=`[${c.title}]\n${c.body}`.length+2;
    return {start,end:offset,title:c.title};
  });
  offset=0;
  for(const page of pages) {
    const end=offset+page.body.length;
    page.topics=ranges.filter(r=>r.start<end && r.end>offset).map(r=>r.title);
    page.title=page.topics[0];page.label='앱 AI 분석 · 상세 리포트';
    offset=end;
  }
  const total=Math.ceil(pages.length/8), series=[];
  for(let part=0;part<total;part++) {
    const content=pages.slice(part*8,(part+1)*8);
    const topics=[...new Set(content.flatMap(c=>c.topics))].join(' · ');
    series.push({...draft,part:part+1,totalParts:total,
      cards:[{...draft.cards[0],body:topics},...content,draft.cards.at(-1)],
      caption:`[${part+1}/${total}편] ${topics}\n\n${draft.caption}`});
  }
  return series;
}

async function textImage(value, width, height, maxSize, minSize, color, bold = false) {
  // Unicode line breaking allows a break between any two Hangul syllables, so
  // `wrap` alone cannot keep a Korean word whole. Word joiners inside each
  // space-delimited token leave spaces as the only break opportunity; if that
  // cannot be laid out, fall back to the unjoined text and let it break.
  const variants=maxSize===32 && minSize===32 ? [joinWords(value)] : [joinWords(value),value];
  for (const value_ of variants) {
    for (let size = maxSize; size >= minSize; size -= 2) {
      const {data, info} = await sharp({text:{
        text:`<span foreground="${color}">${escape(value_)}</span>`,
        font:`Pretendard${bold ? ' Bold' : ''} ${size}`, fontfile:path.join(__dirname, 'instagram_assets', `Pretendard-${bold?'Bold':'Regular'}.ttf`),
        width, dpi:72, rgba:true, wrap:'word-char', spacing:Math.round(size * 0.22),
      }}).png().toBuffer({resolveWithObject:true});
      if (info.width <= width && info.height <= height) return data;
    }
  }
  throw new Error('CARD_TEXT_OVERFLOW');
}

async function renderCards(draft) {
  if(draft.editorial) return require('./instagram_visual').render(draft,textImage);
  const images = [];
  const ink = '#172C29', muted = '#63736B', lime = '#D7F77B', paper = '#F5F4ED';
  for (const [i, card] of draft.cards.entries()) {
    const cover = card.cover || i === 0, dark = cover || card.cta;
    const fg = dark ? paper : ink;
    const overlays = [];
    const put = async (value, x, y, width, height, size, min, color = fg, bold = false) => {
      overlays.push({input:await textImage(value,width,height,size,min,color,bold),left:x,top:y});
    };
    let decor = '';
    if (dark) decor += `<circle cx="1040" cy="580" r="350" fill="none" stroke="#2C443C" stroke-width="1"/><circle cx="1040" cy="580" r="270" fill="none" stroke="#2C443C" stroke-width="1"/>`;
    decor += `<rect x="64" y="62" width="44" height="44" rx="12" fill="${lime}"/><path d="M77 91V78h7v13m7 0V73h7v18" stroke="${ink}" stroke-width="4" fill="none"/>`;
    if (cover) {
      await put(`AI STOCK REPORT  /  ${draft.part||1}편`,64,185,940,44,28,28,lime,true);
      await put(draft.name,64,266,940,150,114,60,fg,true);
      await put(`${draft.ticker} · 앱 AI 분석 상세 리포트`,64,422,940,48,32,28,fg);
      overlays.push({input:await sharp(path.join(__dirname,'instagram_assets','research-ai.png')).resize(952,530,{fit:'cover'}).png().toBuffer(),left:64,top:511});
      await put('AI 콘셉트 이미지',80,1010,400,28,20,20,'#C0CDBF');
      await put(`${draft.part||1} / ${draft.totalParts||1}편 · 옆으로 넘겨 읽기 →`,64,1076,930,50,34,30,lime,true);
      await put(card.body,64,1136,930,57,23,19,'#C0CDBF');
    } else if (card.cta) {
      decor += `<rect x="64" y="752" width="952" height="196" rx="30" fill="#223D34"/><rect x="64" y="1004" width="952" height="112" rx="56" fill="${lime}"/><path d="M939 1047l14 13-14 13m-26-13h40" fill="none" stroke="${ink}" stroke-width="4"/>`;
      await put('YOUR NEXT STOCK',64,185,900,36,27,27,lime,true);
      await put('더 많은 종목 분석이\n궁금하다면?',64,265,950,215,76,64,fg,true);
      overlays.push({input:await sharp(path.join(__dirname,'instagram_assets','research-ai.png')).resize(420,250,{fit:'cover'}).png().toBuffer(),left:590,top:487});
      await put('내 관심 종목의 AI 분석을\n주식저장소에서 확인하세요.',100,800,865,120,43,36,fg);
      await put('주식저장소 앱 다운로드',107,1041,790,58,40,36,ink,true);
      await put('프로필 링크에서 시작하세요',64,1148,900,42,29,29,'#C0CDBF');
    } else {
      const accent = card.id?.startsWith('risks') ? '#B85D42' : '#527542';
      decor += `<rect x="64" y="177" width="7" height="40" rx="3" fill="${accent}"/><rect x="64" y="319" width="952" height="855" rx="28" fill="#FFFFFF"/><path d="M96 345h46" stroke="${accent}" stroke-width="5"/>`;
      await put(card.label + (card.fragments>1 ? ` · ${card.fragment}/${card.fragments}` : ''),88,184,880,40,27,27,accent,true);
      await put(card.title,64,244,952,66,48,36,ink,true);
      await put(card.body,104,365,872,780,32,32,ink);
    }
    const bg = Buffer.from(`<svg width="1080" height="1350"><rect width="1080" height="1350" fill="${dark?ink:paper}"/>${decor}<path d="M64 1210H1016" stroke="${dark?'#3B5248':'#D8DDD1'}"/>${draft.cards.map((_,j)=>`<rect x="${756+j*26}" y="77" width="19" height="5" rx="2" fill="${j===i?(dark?lime:ink):(dark?'#3B5248':'#D8DDD1')}"/>`).join('')}</svg>`);
    await put('주식저장소',122,69,380,43,31,31,fg,true);
    await put(draft.dateLabel,64,1235,840,34,22,22,dark?'#AABBAF':muted);
    await put('AI 분석 · 투자 판단 참고 자료',64,1282,820,30,21,21,dark?'#AABBAF':muted);
    await put(String(i+1).padStart(2,'0'),944,1243,72,56,37,37,fg,true);
    images.push(await sharp(bg).composite(overlays).jpeg({quality:94}).toBuffer());
  }
  return images;
}

module.exports = {CTA, ACCOUNT, createDraft, createSeries, paginateSection, renderCards};
