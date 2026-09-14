'use strict';
const fs=require('node:fs/promises'),os=require('node:os'),path=require('node:path');
const {spawn}=require('node:child_process');
const {render}=require('./instagram_reel_frames');
const STYLE=require('./instagram_reel_style.json');
const numeric=v=>{if(v===null||v===undefined||String(v).trim()==='')return null;const n=Number(String(v).replace(/,/g,'').replace(/배$/,''));return Number.isFinite(n)?n:null;};
function annualRows(data,marketDate) {
  const info=data?.financeInfo,cols=info?.trTitleList||[],rows=info?.rowList||[];
  const year=Number(String(marketDate).slice(0,4));
  if(!(year>=2020&&year<=2100))throw Error('INVALID_REEL_MARKET_DATE');
  const values=new Map(cols.map(c=>[Number(String(c.key).slice(0,4)),{estimate:c.isConsensus==='Y',revenue:numeric(rows.find(r=>r.title==='매출액')?.columns?.[c.key]?.value),operatingProfit:numeric(rows.find(r=>r.title==='영업이익')?.columns?.[c.key]?.value)}]));
  const growth=(v,p)=>v!==null&&p!==null&&p>0?`${(v/p-1)*100>=0?'+':''}${((v/p-1)*100).toFixed(1)}%`:'—';
  return Array.from({length:7},(_,i)=>{const y=year-5+i,v=values.get(y)||{estimate:y>=year,revenue:null,operatingProfit:null},p=values.get(y-1);return {year:y,...v,revenueGrowth:growth(v.revenue,p?.revenue??null),profitGrowth:growth(v.operatingProfit,p?.operatingProfit??null)};});
}
function reelDraft(draft,analysis) {
  if(!draft.editorial||!draft.cards?.length)throw Error('REEL_EDITORIAL_REQUIRED');
  const cards=draft.cards.map(c=>({...c}));
  const at=cards.findIndex(c=>c.layout==='news');
  cards.splice(at<0?3:at+1,0,{layout:'annual',label:'5년 실적 · 2년 전망',title:'매출과 이익,\n함께 볼게요'});
  const flow={...draft.charts.flow,rows:(draft.charts.flow?.rows||[]).slice(-8)};
  return {...draft,cards,charts:{...draft.charts,flow},reelHigh52:numeric(analysis.sourceHigh52),reelAnnual:annualRows(analysis.sourceAnnualFinance,analysis.marketDate),reelPeers:(analysis.valuation?.peerComparison||[]).filter(p=>p.name).slice(0,5).map(p=>({name:p.name,per:numeric(p.per),pbr:numeric(p.pbr)}))};
}
function runFfmpeg(args) {
  return new Promise((resolve,reject)=>{
    const child=spawn(require('ffmpeg-static'),args,{stdio:['ignore','ignore','pipe']});let tail='';
    child.stderr.on('data',d=>{tail=(tail+d).slice(-2000);});
    const timer=setTimeout(()=>child.kill('SIGKILL'),12*60*1000);
    child.on('error',()=>{clearTimeout(timer);reject(Error('REEL_ENCODER_UNAVAILABLE'));});
    child.on('close',code=>{clearTimeout(timer);if(code===0)resolve();else {console.error('[reel encoder]',tail);reject(Error('REEL_ENCODE_FAILED'));}});
  });
}
async function renderReel(draft,analysis,{outputDir}={}) {
  const prepared=reelDraft(draft,analysis),frames=await render(prepared);
  const durations=prepared.cards.map(c=>c.cover||c.cta?4:5),duration=durations.reduce((a,b)=>a+b,0);
  const dir=await fs.mkdtemp(path.join(os.tmpdir(),'stockstorage-reel-'));
  try {
    let list='';
    for(let i=0;i<frames.length;i++){await fs.writeFile(path.join(dir,`${i}.png`),frames[i]);list+=`file '${i}.png'\nduration ${durations[i]}\n`;}
    list+=`file '${frames.length-1}.png'\n`;await fs.writeFile(path.join(dir,'frames.txt'),list);
    const destination=path.join(dir,'reel.mp4');
    await runFfmpeg(['-y','-hide_banner','-loglevel','error','-threads','2','-f','concat','-safe','0','-i',path.join(dir,'frames.txt'),'-i',path.join(__dirname,'instagram_assets','reel-bed.wav'),'-t',String(duration),'-vf',`fps=${STYLE.fps},format=yuv420p`,'-c:v','libx264','-threads','2','-preset','fast','-crf','16','-c:a','aac','-b:a','192k','-af',`afade=t=out:st=${duration-1}:d=1`,'-movflags','+faststart',destination]);
    await runFfmpeg(['-hide_banner','-loglevel','error','-i',destination,'-f','null','-']);
    const video=await fs.readFile(destination),metadata={mediaType:'REELS',width:STYLE.width,height:STYLE.height,fps:STYLE.fps,duration,durations,safeBottomPx:STYLE.safeBottomPx,font:STYLE.fontFamily,styleVersion:STYLE.version};
    if(outputDir){await fs.mkdir(outputDir,{recursive:true});await fs.writeFile(path.join(outputDir,'reel.mp4'),video);await fs.writeFile(path.join(outputDir,'reel.json'),JSON.stringify(metadata,null,2));await fs.writeFile(path.join(outputDir,'draft.json'),JSON.stringify(prepared,null,2));for(let i=0;i<frames.length;i++)await fs.writeFile(path.join(outputDir,`scene-${i+1}.png`),frames[i]);}
    return {video,metadata};
  } finally {await fs.rm(dir,{recursive:true,force:true});}
}
module.exports={renderReel,reelDraft,annualRows,numeric};
