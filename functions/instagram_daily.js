'use strict';

const {randomUUID} = require('node:crypto');
const {getFirestore} = require('firebase-admin/firestore');
const {getStorage} = require('firebase-admin/storage');
const {getApp} = require('firebase-admin/app');
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');
const cheerio = require('cheerio');
const {renderCards, ACCOUNT} = require('./instagram_content');
const {createEditorialSeries}=require('./instagram_editorial');
const {InstagramGraph,publishSeries} = require('./instagram_graph');
const DEFAULT_STOCKS = [
  ['005930','삼성전자','KS',['삼성전자','Samsung Electronics','005930']],
  ['000660','SK하이닉스','KS',['SK하이닉스','하이닉스','SK hynix','000660']],
  ['005380','현대차','KS',['현대차','현대자동차','Hyundai Motor','005380']],
  ['035420','NAVER','KS',['NAVER','네이버','035420']],
  ['000270','기아','KS',['기아','Kia','000270']],
  ['373220','LG에너지솔루션','KS',['LG에너지솔루션','LG엔솔','LG Energy Solution','373220']],
  ['068270','셀트리온','KS',['셀트리온','Celltrion','068270']],
  ['005490','POSCO홀딩스','KS',['POSCO홀딩스','포스코홀딩스','POSCO Holdings','005490']],
  ['035720','카카오','KS',['카카오','Kakao','035720']],
  ['028260','삼성물산','KS',['삼성물산','Samsung C&T','028260']],
].map(([ticker,name,market,keywords]) => ({ticker,name,market,keywords})).concat(require('./instagram_extra_stocks.json'));
const dateKey = date => new Date(date.getTime()+9*3600000).toISOString().slice(0,10);
const secretId = 'INSTAGRAM_ACCESS_TOKEN';
// Wire tags that mark notices and press releases rather than reporting.
const NOTICE_TAG = /^\s*[\[(](게시판|알림|공고|인사|부고|동정|포토|화보|영상|카드뉴스|신간|기고|칼럼|사고|정정|르포)[\])]/;
// Promotional copy routinely names a company without being news about it.
const PROMO = /적립|캐시백|페이백|쿠폰|할인|특가|증정|경품|사은품|응모|추천인|프로모션|이벤트\s*진행|가입\s*(시|하면|만)|무료\s*체험|혜택\s*(제공|드려|받)|출시\s*기념|런칭\s*기념|선착순|한정\s*판매|구독\s*시/;
// User-generated platforms syndicate into Google News but are not reporting,
// and their names ("네이버 블로그") falsely match a stock keyword.
const UGC_SOURCE = /naver\s*blog|네이버\s*(블로그|카페|포스트|프리미엄콘텐츠)|티스토리|tistory|브런치|brunch|다음\s*(블로그|카페)|daum\s*(blog|cafe)|블로그$/i;
// Google News appends " - Publisher"; blog syndication also appends " : 플랫폼".
const platformSuffix = title => title.replace(/\s*[:|]\s*(네이버\s*(블로그|카페|포스트|프리미엄콘텐츠)|티스토리|브런치)\s*$/i, '').trim();
function isMarketNews(title, publisher = '') {
  const clean = platformSuffix(title);
  return Boolean(clean) && !UGC_SOURCE.test(publisher) && !UGC_SOURCE.test(clean)
    && !NOTICE_TAG.test(clean) && !PROMO.test(clean);
}

async function getText(url) {
  const res = await fetch(url,{headers:{'User-Agent':'Mozilla/5.0',Referer:'https://finance.naver.com'},signal:AbortSignal.timeout(20000)});
  if(!res.ok) throw new Error(`MARKET_HTTP_${res.status}`);
  return res.text();
}
function parseHistory(body) {
  const rows = [...body.matchAll(/\["(\d{8})",\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),\s*([\d.]+),/g)]
    .map(m=>({date:m[1],open:+m[2],high:+m[3],low:+m[4],close:+m[5],volume:+m[6]}));
  return rows.filter(r=>r.close>0 && r.open>0 && r.high>=r.low).sort((a,b)=>a.date.localeCompare(b.date)).slice(-140);
}
async function collectHistory(stock, now = new Date()) {
  if(!/^\d{6}$/.test(stock.ticker)) throw new Error('INVALID_STOCK_CONFIG');
  const start=dateKey(new Date(now.getTime()-400*86400000)).replace(/-/g,'');
  const end=dateKey(now).replace(/-/g,'');
  const historyUrl=`https://api.finance.naver.com/siseJson.naver?symbol=${stock.ticker}&requestType=1&startTime=${start}&endTime=${end}&timeframe=day`;
  const [history,basicText,liveText]=await Promise.all([
    getText(historyUrl),getText(`https://m.stock.naver.com/api/stock/${stock.ticker}/basic`),
    getText(`https://polling.finance.naver.com/api/realtime?query=SERVICE_ITEM:${stock.ticker}`),
  ]);
  const basic=JSON.parse(basicText),live=JSON.parse(liveText).result?.areas?.flatMap(a=>a.datas||[]).find(d=>d.cd===stock.ticker);
  return {historyUrl,candles:mergeCurrentCandle(parseHistory(history),basic,live,end),asOf:basic.localTradedAt||null};
}

function mergeCurrentCandle(candles,basic,live,marketDate) {
  // The server response timestamp is not a trade date. Use the exchange's
  // last-traded date, and KRX-only OHLC/volume rather than combined NXT totals.
  if(String(basic?.localTradedAt||'').slice(0,10).replace(/-/g,'')!==marketDate || !live)return candles;
  const row={date:marketDate,open:live.ov,high:live.hv,low:live.lv,close:live.nv,volume:live.aq};
  if(![row.open,row.high,row.low,row.close,row.volume].every(Number.isFinite)||row.low<=0||row.high<Math.max(row.open,row.close)||row.low>Math.min(row.open,row.close)||row.volume<=0)throw new Error('INVALID_INTRADAY_CANDLE');
  return [...candles.filter(c=>c.date<marketDate),row].slice(-140);
}

function scheduledSlot(date) {
  const hour=new Date(date.getTime()+9*3600000).getUTCHours();
  return hour>=17?'1700':hour>=14?'1400':hour>=10?'1000':null;
}

function chooseUnusedStock(ranked, jobs, reservedTickers, day, exclusionDays=7) {
  const cutoff=dateKey(new Date(Date.parse(`${day}T00:00:00+09:00`)-exclusionDays*86400000));
  const blocked=new Set(reservedTickers);
  for(const job of jobs) {
    if(!job.stock || job.status==='market_closed')continue;
    if(job.day===day || ((exclusionDays===-1 || job.day>=cutoff) && ['published','publishing','publish_uncertain'].includes(job.status)))blocked.add(job.stock.ticker);
  }
  return ranked.find(r=>!blocked.has(r.stock.ticker))?.stock||null;
}

function rankVolumeCandidates(candidates, marketDate) {
  return candidates.flatMap(({stock,candles})=>{
    const last=candles.at(-1), previous=candles.slice(-21,-1);
    if(candles.length<120 || last.date!==marketDate || !(last.volume>0) || previous.length!==20 || previous.some(c=>!Number.isFinite(c.volume)||c.volume<0)) return [];
    const averageVolume=previous.reduce((sum,c)=>sum+c.volume,0)/20;
    if(!(averageVolume>0)) return [];
    return [{stock,marketDate,volume:last.volume,averageVolume,volumeRatio:last.volume/averageVolume}];
  }).sort((a,b)=>b.volumeRatio-a.volumeRatio || a.stock.ticker.localeCompare(b.stock.ticker));
}

async function collectInput(stock, deps, now = new Date(), cachedHistory) {
  if(!/^\d{6}$/.test(stock.ticker) || !['KS','KQ'].includes(stock.market) || !stock.name) throw new Error('INVALID_STOCK_CONFIG');
  const keywords = [...new Set([stock.name, stock.ticker, ...(Array.isArray(stock.keywords)?stock.keywords:[])].filter(Boolean))];
  const newsUrl = `https://news.google.com/rss/search?q=${encodeURIComponent(`("${keywords.join('" OR "')}") 주식 when:7d`)}&hl=ko&gl=KR&ceid=KR:ko`;
  const [history, rss, quote, integration] = await Promise.all([
    cachedHistory||collectHistory(stock,now),getText(newsUrl),deps.fetchQuote(stock.ticker),deps.fetchValuation(stock.ticker),
  ]);
  const {candles,historyUrl} = history;
  if(candles.length<120) throw new Error('INSUFFICIENT_CANDLES');
  const last = candles.at(-1), prev = candles.at(-2);
  const $ = cheerio.load(rss,{xmlMode:true});
  const news = $('item').toArray().map(el=>{
    const item=$(el), publishedAt=new Date(item.find('pubDate').text());
    const publisher=item.find('source').text();
    const rawTitle=item.find('title').text();
    const stripped=publisher && rawTitle.endsWith(` - ${publisher}`) ? rawTitle.slice(0,-publisher.length-3) : rawTitle;
    return {title:platformSuffix(stripped),url:item.find('link').text(),publisher,publishedAt,rawTitle:stripped};
  }).filter(n=>n.title && n.url.startsWith('https://') && Number.isFinite(n.publishedAt.getTime()) && now-n.publishedAt>=0 && now-n.publishedAt<8*86400000)
    .filter(n=>{
      const text=n.title.toLocaleLowerCase('ko-KR');
      return keywords.some(keyword=>text.includes(String(keyword).toLocaleLowerCase('ko-KR')));
    })
    // Promo, notice and blog items name the company without reporting on it.
    .filter(n=>isMarketNews(n.rawTitle,n.publisher))
    .slice(0,8).map(({rawTitle,...n})=>({...n,publishedAt:n.publishedAt.toISOString()}));
  if(!news.length) throw new Error('NO_RECENT_NEWS');
  const val=code=>{
    const raw=integration?.totalInfos?.find(x=>x.code===code)?.value;
    const match=String(raw||'').replace(/,/g,'').match(/-?\d+(?:\.\d+)?/);
    return match?Number(match[0]):null;
  };
  const currentPrice=quote?.price>0?quote.price:last.close;
  return {stock,price:{currentPrice,change:currentPrice-prev.close,changeRate:(currentPrice/prev.close-1)*100},
    fundamentals:{per:val('per'),pbr:val('pbr'),bps:val('bps'),forwardPer:val('cnsPer')},candles,news,
    marketDate:last.date,sourcePriceUrl:historyUrl,asOf:history.asOf||null};
}

function eligibleJob(job, now = Date.now()) {
  if(['published','publishing','publish_uncertain'].includes(job?.status)) return false;
  const lease = job?.leaseUntil?.toMillis?.() ?? Number(job?.leaseUntil || 0);
  return lease<=now;
}

async function loadToken(db, projectId) {
  // Local operator runs supply the token directly; Cloud Run always sets
  // K_SERVICE and so always reads and refreshes it through Secret Manager.
  if (!process.env.K_SERVICE && process.env.INSTAGRAM_ACCESS_TOKEN) {
    return process.env.INSTAGRAM_ACCESS_TOKEN.trim();
  }
  const client = new SecretManagerServiceClient();
  const name=`projects/${projectId}/secrets/${secretId}`;
  const [version]=await client.accessSecretVersion({name:`${name}/versions/latest`});
  let token=version.payload.data.toString().trim();
  const ref=db.collection('_admin').doc('instagramTokenStatus');
  const state=(await ref.get()).data()||{};
  const refreshed=state.refreshedAt?.toMillis?.()||0;
  if(Date.now()-refreshed>7*86400000) {
    // Meta long-lived tokens must be >24h old. Setup records their initial date.
    const url=new URL('https://graph.instagram.com/refresh_access_token');
    url.searchParams.set('grant_type','ig_refresh_token');
    url.searchParams.set('access_token',token);
    const response=await fetch(url,{signal:AbortSignal.timeout(30000)});
    const result=await response.json();
    if(!response.ok || !result.access_token) throw new Error('INSTAGRAM_TOKEN_REFRESH_FAILED');
    await client.addSecretVersion({parent:name,payload:{data:Buffer.from(result.access_token)}});
    token=result.access_token;
    await ref.set({refreshedAt:new Date(),expiresAt:new Date(Date.now()+Number(result.expires_in)*1000)},{merge:true});
  }
  return token;
}

async function runDailyInstagram(deps, options = {}) {
  const db=getFirestore(), now=options.now||new Date(), day=dateKey(now);
  const configRef=db.collection('_admin').doc('instagramAutomation');
  const config=(await configRef.get()).data()||{};
  if(!config.enabled && !options.draftOnly) return {status:'disabled'};
  if(config.account && config.account!==ACCOUNT) throw new Error('INSTAGRAM_ACCOUNT_MISMATCH');
  const universe=config.stocks||DEFAULT_STOCKS;
  if(!Array.isArray(universe)||!universe.length||universe.length>100) throw new Error('INVALID_STOCK_LIST');
  const slot=options.slot||scheduledSlot(now);
  if(!slot)return {status:'outside_schedule',results:[]};
  const selectionRef=configRef.collection('selections').doc(`${day}_${slot}${options.draftOnly?'_draft':''}`);
  let selection=(await selectionRef.get()).data();
  const histories=new Map();
  if(!selection) {
    const candidates=[],failures=[];
    // Bound upstream traffic, and do not pay for AI analysis until ranking is final.
    for(let i=0;i<universe.length;i+=5) {
      const batch=universe.slice(i,i+5);
      const fetched=await Promise.allSettled(batch.map(stock=>collectHistory(stock,now)));
      fetched.forEach((result,j)=>{
        const stock=batch[j];
        if(result.status==='rejected'){failures.push(stock.ticker);return;}
        histories.set(stock.ticker,result.value);
        candidates.push({stock,candles:result.value.candles});
      });
    }
    if(failures.length) throw new Error('VOLUME_SCREEN_INCOMPLETE');
    const marketDate=options.allowPriorMarketDay?candidates.flatMap(c=>c.candles.at(-1)?.date||[]).sort().at(-1):day.replace(/-/g,'');
    const ranked=rankVolumeCandidates(candidates,marketDate);
    if(!ranked.length)return {status:'market_closed_or_no_candidates',results:[]};
    selection=await db.runTransaction(async tx=>{
      const saved=(await tx.get(selectionRef)).data();
      if(saved)return saved;
      const prior=await tx.get(configRef.collection('jobs'));
      const reservations=await tx.get(configRef.collection('selections').where('day','==',day));
      const jobs=prior.docs.filter(d=>!d.id.endsWith('_draft')).map(d=>d.data());
      const reserved=reservations.docs.filter(d=>!d.id.endsWith('_draft')).flatMap(d=>(d.data().stocks||[]).map(s=>s.ticker));
      const stock=chooseUnusedStock(ranked,options.draftOnly?[]:jobs,options.draftOnly?[]:reserved,day,Number.isInteger(config.repeatExclusionDays)?config.repeatExclusionDays:7);
      const value={day,slot,marketDate,method:'relative_volume_20d',count:1,stocks:stock?[stock]:[],ranking:ranked,createdAt:new Date()};
      tx.set(selectionRef,value);
      return value;
    });
  }
  const stocks=selection.stocks;
  if(!stocks.length) {
    await configRef.set({lastRunAt:new Date(),lastRunDay:day,lastRunSlot:slot,lastRunStatus:'no_unused_candidates'},{merge:true});
    throw new Error('NO_UNUSED_INSTAGRAM_CANDIDATES');
  }
  const projectId=getApp().options.projectId||process.env.GCLOUD_PROJECT;
  let graph;
  if(!options.draftOnly) {
    graph=new InstagramGraph(await loadToken(db,projectId),config.apiVersion||'v23.0');
    await graph.identity(); // Fail before paying for analysis if connection is invalid.
  }
  const results=[];
  for(const stock of stocks) {
    const key=`${day}_${stock.market}_${stock.ticker}${options.draftOnly?'_draft':''}`;
    const ref=db.collection('_admin').doc('instagramAutomation').collection('jobs').doc(key);
    const owner=randomUUID();
    const claimed=await db.runTransaction(async tx=>{
      const prior=(await tx.get(ref)).data();
      if(!eligibleJob(prior)) return false;
      tx.set(ref,{status:'generating',owner,stock,day,selection:selection.ranking.find(r=>r.stock.ticker===stock.ticker)||null,startedAt:new Date(),leaseUntil:new Date(Date.now()+35*60000)},{merge:true});
      return true;
    });
    if(!claimed) {results.push({key,status:'already_handled'});continue;}
    let phase='generating';
    const save=async fields=>{
      await db.runTransaction(async tx=>{
        const current=(await tx.get(ref)).data();
        if(current?.owner!==owner) throw new Error('JOB_LEASE_LOST');
        tx.set(ref,{...fields,updatedAt:new Date()},{merge:true});
      });
      if(fields.status) phase=fields.status;
    };
    try {
      const input=await collectInput(stock,deps,now,histories.get(stock.ticker));
      // Weekend/holiday/stale feeds never masquerade as today's market analysis.
      if(input.marketDate!==day.replace(/-/g,'') && !options.allowPriorMarketDay) {
        await save({status:'market_closed',marketDate:input.marketDate,leaseUntil:new Date(0)});
        results.push({key,status:'market_closed'});continue;
      }
      const payload=await deps.analyze({...input,requestId:`ig_${key}`});
      const analysis={...payload,...stock,updatedAt:new Date().toISOString(),analysisPrice:input.price.currentPrice,marketDate:input.marketDate,sourceCandles:input.candles,sourcePriceUrl:input.sourcePriceUrl,intraday:['1000','1400'].includes(slot),marketAsOf:input.asOf};
      const drafts=await createEditorialSeries(analysis);
      const imageSets=[];
      for(const draft of drafts) imageSets.push(await renderCards(draft));
      await save({status:'draft',analysis,draft:drafts[0],drafts,leaseUntil:new Date(Date.now()+30*60000)});
      if(options.draftOnly) {
        if(options.outputDir) {
          const fs=require('node:fs/promises'),path=require('node:path');
          await fs.mkdir(options.outputDir,{recursive:true});
          await fs.writeFile(path.join(options.outputDir,'analysis.json'),JSON.stringify(analysis,null,2));
          await fs.writeFile(path.join(options.outputDir,'series.json'),JSON.stringify(drafts,null,2));
          for(let p=0;p<drafts.length;p++) {
            const dir=path.join(options.outputDir,`part-${String(p+1).padStart(2,'0')}`);
            await fs.mkdir(dir,{recursive:true});
            await fs.writeFile(path.join(dir,'draft.json'),JSON.stringify(drafts[p],null,2));
            await fs.writeFile(path.join(dir,'caption.txt'),drafts[p].caption);
            for(let i=0;i<imageSets[p].length;i++) await fs.writeFile(path.join(dir,`${i+1}.jpg`),imageSets[p][i]);
          }
        }
        await save({leaseUntil:new Date(0)});
        results.push({key,status:'draft',parts:drafts.length});continue;
      }
      const bucket=getStorage().bucket(config.storageBucket||'stockstorage-13828.firebasestorage.app');
      const posts=[];
      for(let p=0;p<drafts.length;p++) {
        const urls=[];
        for(let i=0;i<imageSets[p].length;i++) {
          const name=`instagram/${key}/part-${p+1}/${i+1}.jpg`, token=randomUUID();
          await bucket.file(name).save(imageSets[p][i],{resumable:false,contentType:'image/jpeg',metadata:{metadata:{firebaseStorageDownloadTokens:token},cacheControl:'public,max-age=86400'}});
          urls.push(`https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(name)}?alt=media&token=${token}`);
        }
        posts.push({urls,caption:drafts[p].caption});
      }
      await save({posts,status:'uploading'});
      const mediaIds=await publishSeries(graph,posts,save);
      await configRef.set({lastPublishedAt:new Date(),lastJob:key,lastMediaId:mediaIds.at(-1),lastMediaIds:mediaIds},{merge:true});
      results.push({key,status:'published',mediaIds});
    } catch(error) {
      const code=/^[A-Z0-9_]+$/.test(error.message||'')?error.message:'INSTAGRAM_JOB_FAILED';
      // Never downgrade a confirmed publication or clear an uncertain publish.
      if(phase!=='published') await save({status:phase==='publishing'?'publish_uncertain':'failed',error:code,leaseUntil:new Date(0)});
      console.error('[instagramAutomation]',key,code);
      results.push({key,status:phase==='publishing'?'publish_uncertain':'failed',error:code});
    }
  }
  await configRef.set({lastRunAt:new Date(),lastRunDay:day,lastRunResults:results},{merge:true});
  if(results.some(r=>['failed','publish_uncertain'].includes(r.status)))throw new Error('INSTAGRAM_DAILY_PARTIAL_FAILURE');
  return {status:'complete',results};
}

module.exports={DEFAULT_STOCKS,dateKey,parseHistory,collectHistory,mergeCurrentCandle,scheduledSlot,chooseUnusedStock,rankVolumeCandidates,collectInput,eligibleJob,isMarketNews,runDailyInstagram};
