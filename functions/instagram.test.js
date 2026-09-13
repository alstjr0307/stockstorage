'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {createDraft,createSeries,renderCards,CTA}=require('./instagram_content');
const {eligibleJob,parseHistory,dateKey}=require('./instagram_daily');
const {InstagramGraph}=require('./instagram_graph');
const fixture=()=>({...require('../tools/instagram_ai_sample.json'),updatedAt:new Date().toISOString(),sourceNews:[{title:'테스트 출처',url:'https://example.com/source'}]});
test('preserves source paragraphs, risks and exact download CTA',()=>{
  const source=fixture(),draft=createDraft(source);
  assert.ok(draft.cards.length>=5);
  assert.equal(draft.cards.at(-1).title,CTA);
  assert.match(draft.cards.at(-1).body,/앱 다운로드/);
  assert.ok(source.summary.includes(draft.cards.find(c=>c.id==='summary').body));
  for(const risk of source.risks) assert.ok(draft.cards.find(c=>c.id==='risks').body.includes(risk));
  assert.throws(()=>createDraft({...source,risks:[]}),/INCOMPLETE/);
  assert.throws(()=>createDraft({...source,updatedAt:'2000-01-01'}),/STALE/);
  assert.throws(()=>createDraft({...source,sourceNews:[]}),/INCOMPLETE/);
});
test('lease cannot replay an uncertain or confirmed publication',()=>{
  for(const status of ['published','publishing','publish_uncertain']) assert.equal(eligibleJob({status,leaseUntil:0}),false);
  assert.equal(eligibleJob({status:'generating',leaseUntil:{toMillis:()=>Date.now()+10000}}),false);
  assert.equal(eligibleJob({status:'failed',leaseUntil:0}),true);
});
test('KST date and market history columns are correct',()=>{
  assert.equal(dateKey(new Date('2026-09-06T16:00:00Z')),'2026-09-07');
  assert.deepEqual(parseHistory('[["20260904", 100, 120, 95, 110, 500, 0]]'),[{date:'20260904',open:100,high:120,low:95,close:110,volume:500}]);
});
test('carousel saves publishing before POST; link failure never republishes',async()=>{
  const calls=[],states=[];let n=0;
  const api=new InstagramGraph('test','v23.0',async(url,options)=>{
    const pathname=new URL(url).pathname;calls.push(pathname);
    let result;
    if(pathname.endsWith('/me')) result={user_id:'123',username:'tf_stockstorage'};
    else if(pathname.endsWith('/media_publish')) {assert.equal(states.at(-1).status,'publishing');result={id:'posted'};}
    else if(pathname.endsWith('/media')) result={id:String(++n)};
    else if(pathname.endsWith('/posted')) throw new Error('offline');
    else result={status_code:'FINISHED'};
    return {ok:true,json:async()=>result};
  });
  const id=await api.carousel(Array(5).fill('https://firebasestorage.googleapis.com/card'),'caption',async state=>states.push(state));
  assert.equal(id,'posted');assert.equal(states.at(-1).status,'published');
  assert.equal(calls.filter(c=>c.endsWith('/media_publish')).length,1);
});
test('ambiguous publish leaves a non-replayable publishing state',async()=>{
  let n=0;const states=[];
  const api=new InstagramGraph('test','v23.0',async url=>{
    const pathname=new URL(url).pathname;
    if(pathname.endsWith('/media_publish')) throw new Error('timeout');
    const data=pathname.endsWith('/me')?{user_id:'123',username:'tf_stockstorage'}:pathname.endsWith('/media')?{id:String(++n)}:{status_code:'FINISHED'};
    return {ok:true,json:async()=>data};
  });
  await assert.rejects(api.carousel(Array(5).fill('https://firebasestorage.googleapis.com/card'),'caption',async s=>states.push(s)),/NETWORK/);
  assert.equal(states.at(-1).status,'publishing');assert.equal(eligibleJob(states.at(-1)),false);
});
test('renders every series page as a 1080 x 1350 JPEG',async()=>{
  const sharp=require('sharp');
  const series=await createSeries(fixture());
  const cards=await renderCards(series[0]);
  assert.equal(cards.length,series[0].cards.length);
  for(const card of cards) {const m=await sharp(card).metadata();assert.equal(m.width,1080);assert.equal(m.height,1350);assert.equal(m.format,'jpeg');}
});
test('promotional and notice headlines never become analysis sources',()=>{
  const {isMarketNews}=require('./instagram_daily');
  for(const junk of [
    '[게시판] 키움증권 앱에서 네이버 쇼핑하면 최대 4% 적립',
    '키움증권 경유해 네이버 쇼핑하면 최대 4% 적립',
    '[알림] 삼성전자 갤럭시 구매 시 사은품 증정',
    '카카오톡 선물하기 신규 가입하면 쿠폰 지급',
  ]) assert.equal(isMarketNews(junk),false,junk);
  for(const [junk,pub] of [
    ["[두나무 톺아보기] 떠나면 현금, 남으면 네이버…두 갈래 길 : 네이버 블로그","Naver Blog"],
    ["9월에는 주식을 매수해야 하나?","네이버 프리미엄콘텐츠"],
    ["삼성전자 급등 이유 정리","티스토리"],
  ]) assert.equal(isMarketNews(junk,pub),false,junk);
  for(const real of [
    'NAVER, 2분기 영업이익 시장 기대치 상회',
    '삼성전자 외국인 순매도 지속…반도체 업황 우려',
    'SK하이닉스 목표주가 상향, HBM 수요 견조',
  ]) assert.equal(isMarketNews(real),true,real);
});


test('full app narrative survives pagination without losing later paragraphs or items',async()=>{
  const a={...require('../tools/instagram_ai_full_sample.json')};
  const series=await createSeries(a,new Date(a.updatedAt));
  const joined=series.flatMap(p=>p.cards.slice(1,-1)).map(c=>c.body).join('');
  for(const key of ['companyOverview','summary','todayReason','fundamentals','technical','news','momentum','scoreLabel']) assert.ok(joined.includes(a[key].trim()),key);
  for(const c of a.catalysts) assert.ok(joined.includes(c.detail),c.title);
  for(const r of a.risksDetailed) for(const key of ['description','mitigant']) assert.ok(joined.includes(r[key]),key);
  for(const s of Object.values(a.scenarios)) assert.ok(joined.includes(s.narrative));
  for(const s of a.sections) assert.ok(joined.includes(s.body),s.title);
  for(const key of ['shortTerm','midTerm','actionReason']) assert.ok(joined.includes(a.timing[key]));
  for(const part of series) {
    assert.ok(part.cards.length>=2 && part.cards.length<=10);
    assert.equal(part.cards.at(-1).title,CTA);
    assert.ok([...part.caption].length<=2200);
    await renderCards(part); // Same measured font size must fit final layout.
  }
});

test('a later series failure retains confirmed earlier parts and blocks job replay',async()=>{
  const {publishSeries}=require('./instagram_graph');const states=[];let calls=0;
  const graph={carousel:async(urls,caption,save)=>{
    calls++;await save({status:'publishing'});
    if(calls===2) throw new Error('INSTAGRAM_NETWORK_ERROR');
    await save({status:'published',mediaId:'first'});return 'first';
  }};
  await assert.rejects(publishSeries(graph,[{urls:[],caption:'one'},{urls:[],caption:'two'}],async s=>states.push(structuredClone(s))));
  const state=states.at(-1);
  assert.equal(state.parts[0].mediaId,'first');
  assert.equal(state.parts[0].status,'published');
  assert.equal(state.status,'publishing');
  assert.equal(eligibleJob(state),false);
});


test('editorial carousel covers the analysis in ten scannable cards',async()=>{
  const {createEditorialSeries,validateEditorial}=require('./instagram_editorial');
  const {analysisSections}=require('./instagram_sections');
  const a=require('../tools/instagram_ai_full_sample.json');
  const e=require('../tools/instagram_editorial_sample.json');
  const series=await createEditorialSeries(a,new Date(a.updatedAt),{editorial:e});
  assert.equal(series.length,1);assert.equal(series[0].cards.length,10);
  assert.equal(series[0].cards.at(-1).title,CTA);
  assert.equal((await renderCards(series[0])).length,10);
  const bad=structuredClone(e);bad.cards[0].points[0].body='수익률 99999% 보장';
  assert.throws(()=>validateEditorial(bad,analysisSections(a)),/UNSUPPORTED_NUMBER/);
  const missing=structuredClone(e);
  for(const c of missing.cards)for(const p of c.points)p.sourceIds=p.sourceIds.filter(id=>id!=='peerComparison');
  assert.throws(()=>validateEditorial(missing,analysisSections(a)),/MISSING_TOPIC|TEXT_TOO_LONG/);
  const wrongOrder=structuredClone(e);wrongOrder.cards[5].points.reverse();
  assert.throws(()=>validateEditorial(wrongOrder,analysisSections(a)),/SCENARIO_ORDER/);
});

test('market charts preserve observed values and exclude dates beyond analysis',()=>{
  const {priceSeries,priceGeometry,flowSeries,peerSeries}=require('./instagram_charts');
  const a={marketDate:'20260904',sourceCandles:[{date:'20260907',close:999},{date:'20260904',close:105},{date:'20260903',close:100},{date:'20260902',close:NaN}],valuation:{peerComparison:[{name:'A',per:'12.5'},{name:'B',per:'-3'},{name:'C',per:'N/A'}]},sourceDailyInvestorFlow:{days:[{date:'2026.09.03',foreignNet:3,institutionNet:null},{date:'2026.09.04',foreignNet:-1,institutionNet:10}]}};
  assert.deepEqual(priceSeries(a),[{date:'20260903',value:100},{date:'20260904',value:105}]);
  assert.deepEqual(peerSeries(a),[{name:'A',value:12.5}]);
  assert.deepEqual(flowSeries(a).values,[{name:'외국인',value:2}]);
  const g=priceGeometry([{value:100},{value:100}],{x:0,y:0,width:100,height:100});
  assert.ok(g.coords.every(p=>Number.isFinite(p.y)));
  assert.equal(g.coords[0].x,0);assert.equal(g.coords[1].x,100);
});

test('journal layout renders actual history and peer comparison with new fonts',async()=>{
  const {createEditorialSeries}=require('./instagram_editorial');
  const a=require('../tools/instagram_chart_sample.json'),editorial=require('../tools/instagram_human_sample.json');
  const [draft]=await createEditorialSeries(a,new Date(a.updatedAt),{editorial});
  assert.equal(draft.charts.prices.length,60);
  assert.equal(draft.charts.prices.at(-1).date,a.marketDate);
  assert.equal(draft.charts.peers.length,4);
  assert.equal((await renderCards(draft)).length,10);
});

test('automated copy rejects report jargon and keeps plain-language drafts',()=>{
  const {validateStyle}=require('./instagram_editorial');
  const human=require('../tools/instagram_human_sample.json');
  assert.doesNotThrow(()=>validateStyle(human));
  const bad=structuredClone(human);bad.cards[0].points[0].body='거버넌스 노이즈가 하방 압력으로 작용합니다';
  assert.throws(()=>validateStyle(bad),/STIFF_COPY/);
});

test('plain wording preserves numbers and source references',()=>{
  const {plainLanguage,validateStyle}=require('./instagram_editorial');
  const original=structuredClone(require('../tools/instagram_human_sample.json'));
  original.cards[0].points[0].body='거버넌스 노이즈와 17.05배 밸류를 확인해요';
  const copy=plainLanguage(original);
  assert.equal(copy.cards[0].points[0].body,'지배구조 불확실성과 17.05배 기업가치를 확인해요');
  assert.deepEqual(copy.cards[0].points[0].sourceIds,original.cards[0].points[0].sourceIds);
  assert.doesNotThrow(()=>validateStyle(copy));
});

test('candles use actual OHLC values and facts compare the correct trading windows',()=>{
  const {candleSeries,candleFacts,candleGeometry,flowSeries}=require('./instagram_charts');
  const a=require('../tools/instagram_chart_sample.json');
  const c=candleSeries(a),f=candleFacts(c),last=c.at(-1);
  assert.equal(c.length,60);assert.equal(c.at(-1).date,a.marketDate);
  assert.equal(f.close,last.close);
  assert.equal(f.ma20,c.slice(-20).reduce((n,v)=>n+v.close,0)/20);
  assert.equal(f.averageVolume,c.slice(-21,-1).reduce((n,v)=>n+v.volume,0)/20);
  assert.equal(f.low20,Math.min(...c.slice(-20).map(v=>v.low)));
  const g=candleGeometry(c,{x:0,y:0,width:600,height:300});
  assert.equal(g.items.length,60);
  for(const [i,v] of g.items.entries()) {assert.ok(v.high<=v.low);assert.equal(v.up,c[i].close>=c[i].open);assert.ok(v.height>0);}
  const bad={...a,sourceCandles:[...a.sourceCandles,{date:'20260907',open:1,high:2,low:1,close:2},{date:'20260904',open:10,high:5,low:1,close:9}]};
  assert.deepEqual(candleSeries(bad),c);
  const flow=flowSeries(a);
  assert.equal(flow.rows.length,a.sourceDailyInvestorFlow.days.length);
  assert.ok(flow.rows.every((r,i)=>i===0||r.date>flow.rows[i-1].date));
  assert.equal(flow.rows.at(-1).foreign,a.sourceDailyInvestorFlow.days[0].foreignNet);
});

test('ten-card layout includes a separate daily flow page and company imagery',async()=>{
  const {createEditorialSeries}=require('./instagram_editorial');
  const a=require('../tools/instagram_chart_sample.json');
  const [d]=await createEditorialSeries(a,new Date(a.updatedAt),{editorial:require('../tools/instagram_human_sample.json')});
  assert.equal(d.cards.length,10);
  assert.equal(d.cards[5].layout,'candles');assert.equal(d.cards[6].layout,'flow');
  assert.ok(d.brand.logoFile);assert.ok(d.brand.heroFile);assert.ok(d.brand.detailFile);
  assert.equal(d.cards[1].layout,'company');
  assert.equal(d.cards[2].layout,'score');
  assert.equal(d.cards[2].points.length,2);
  assert.deepEqual(d.cards[8].checklist.points,require('../tools/instagram_human_sample.json').cards[7].points);
  assert.ok(d.caption.includes('https://tofusoft-software.github.io/Stockstorage/'));
  assert.ok(!d.caption.includes('회사 이미지:'));
  assert.ok(!d.caption.includes('분석 기준:'));
  assert.equal((await renderCards(d)).length,10);
});

test('sector artwork maps automated stocks to reusable image packs',()=>{
  const {sectorArtForAnalysis}=require('./instagram_sector_art');
  assert.equal(sectorArtForAnalysis({ticker:'005930'}).file,'semiconductor-ai.png');
  assert.equal(sectorArtForAnalysis({ticker:'207940'}).file,'bio-pharma.png');
  assert.equal(sectorArtForAnalysis({ticker:'105560'}).file,'finance-insurance.png');
  assert.equal(sectorArtForAnalysis({ticker:'005380'}).file,'mobility-logistics.png');
  assert.equal(sectorArtForAnalysis({ticker:'035420'}).file,'platform-commerce.png');
  assert.equal(sectorArtForAnalysis({ticker:'012450'}).file,'industrial-aerospace.png');
  assert.equal(sectorArtForAnalysis({ticker:'030200'}).file,'telecom-consumer.png');
});


test('volume selection excludes today from average and rejects stale or incomplete data',()=>{
  const {rankVolumeCandidates}=require('./instagram_daily');
  const base=require('../tools/instagram_chart_sample.json').sourceCandles.map(c=>({...c,volume:100}));
  const candidate=(ticker,volume,date=base.at(-1).date)=>({stock:{ticker},candles:base.map((c,i)=>i===base.length-1?{...c,volume,date}:c)});
  const ranked=rankVolumeCandidates([candidate('000002',250),candidate('000001',400),candidate('000003',900,'20260903'),{stock:{ticker:'000004'},candles:base.slice(-20)},candidate('000005',0)],base.at(-1).date);
  assert.deepEqual(ranked.map(r=>r.stock.ticker),['000001','000002']);
  assert.equal(ranked[0].averageVolume,100);assert.equal(ranked[0].volumeRatio,4);
});

test('scheduled slots use KST and each slot excludes reserved and recently posted stocks',()=>{
  const {scheduledSlot,chooseUnusedStock}=require('./instagram_daily');
  for(const [iso,slot] of [['2026-09-10T01:00:00Z','1000'],['2026-09-10T05:00:00Z','1400'],['2026-09-10T08:00:00Z','1700'],['2026-09-10T00:00:00Z',null]])assert.equal(scheduledSlot(new Date(iso)),slot);
  const ranked=['A','B','C','D'].map(ticker=>({stock:{ticker}}));
  const jobs=[{stock:{ticker:'A'},day:'2026-09-09',status:'published'},{stock:{ticker:'B'},day:'2026-09-10',status:'failed'}];
  assert.equal(chooseUnusedStock(ranked,jobs,['C'],'2026-09-10',7).ticker,'D');
  assert.equal(chooseUnusedStock(ranked,jobs,['C'],'2026-09-10',0).ticker,'A');
  assert.equal(chooseUnusedStock(ranked,jobs,['C','D'],'2026-09-10',7),null);
  assert.equal(chooseUnusedStock(ranked,[{stock:{ticker:'A'},day:'2020-01-01',status:'publish_uncertain'}],[],'2026-09-10',-1).ticker,'B');
});

test('intraday candle uses a verified trade date and observed KRX OHLC and volume',()=>{
  const {mergeCurrentCandle}=require('./instagram_daily');
  const history=[{date:'20260909',close:100}];
  const live={ov:101,hv:110,lv:99,nv:105,aq:500};
  assert.deepEqual(mergeCurrentCandle(history,{localTradedAt:'2026-09-09T15:30:00+09:00'},live,'20260910'),history);
  const basic={localTradedAt:'2026-09-10T10:00:00+09:00'};
  const rows=mergeCurrentCandle(history,basic,live,'20260910');
  assert.deepEqual(rows.at(-1),{date:'20260910',open:101,high:110,low:99,close:105,volume:500});
  assert.equal(mergeCurrentCandle(rows,basic,{...live,aq:600},'20260910').length,2);
  assert.throws(()=>mergeCurrentCandle(history,basic,{...live,hv:90},'20260910'),/INVALID_INTRADAY/);
});

test('score colors match app cutoffs and visible digits stay centered at every width',async()=>{
  const {scoreColor,centeredText}=require('./instagram_visual');
  const sharp=require('sharp');
  assert.equal(scoreColor(49),'#C8414F');assert.equal(scoreColor(50),'#B87308');
  assert.equal(scoreColor(69),'#B87308');assert.equal(scoreColor(70),'#16845B');
  assert.equal(scoreColor(null),'#64748B');
  for(const value of ['0','9','49','50','69','70','72','100','—']){
    const v=await centeredText(value,278,662,230,122,100,'#16845B',true);
    const m=await sharp(v.input).metadata();
    assert.ok(Math.abs(v.left+m.width/2-278)<=.5);
    assert.ok(Math.abs(v.top+m.height/2-662)<=.5);
    assert.ok(m.width<=230&&m.height<=122);
  }
});

test('editorial retries an incomplete JSON response instead of abandoning a valid analysis',async()=>{
  const {editAnalysis}=require('./instagram_editorial');let calls=0;
  const expected=require('../tools/instagram_human_sample.json');
  const result=await editAnalysis(require('../tools/instagram_chart_sample.json'),{apiKey:'test',transport:async()=>({ok:true,json:async()=>++calls===1?{output:[]}:{output:[{content:[{type:'output_text',text:JSON.stringify(expected)}]}]}})});
  assert.equal(calls,2);assert.equal(result.cards.length,8);
});
