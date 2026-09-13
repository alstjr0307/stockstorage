'use strict';

const day=v=>String(v||'').replace(/[^0-9]/g,'').slice(0,8);
function priceSeries(a) {
  const cutoff=day(a.marketDate),byDate=new Map();
  for(const c of a.sourceCandles||[]) {
    const date=day(c.date);
    if(/^\d{8}$/.test(date)&&(!cutoff||date<=cutoff)&&Number.isFinite(c.close)&&c.close>0)byDate.set(date,{date,value:c.close});
  }
  return [...byDate.values()].sort((x,y)=>x.date.localeCompare(y.date)).slice(-60);
}
function peerSeries(a) {
  const items=(a.valuation?.peerComparison||[]).map(p=>({name:p.name,value:Number(String(p.per).replace(/,/g,''))}));
  return items.filter(p=>p.name&&Number.isFinite(p.value)&&p.value>0).slice(0,6);
}
function flowSeries(a) {
  const cutoff=day(a.marketDate);
  const unique=new Map();
  for(const d of a.sourceDailyInvestorFlow?.days||[])if(/^\d{8}$/.test(day(d.date))&&day(d.date)<=cutoff)unique.set(day(d.date),d);
  const rows=[...unique.values()].sort((x,y)=>day(x.date).localeCompare(day(y.date))).slice(-20);
  const sum=key=>rows.length && rows.every(r=>Number.isFinite(r[key]))?rows.reduce((n,r)=>n+r[key],0):null;
  return {from:rows[0]?.date||'',to:rows.at(-1)?.date||'',days:rows.length,rows:rows.map(r=>({date:day(r.date),foreign:Number.isFinite(r.foreignNet)?r.foreignNet:null,institution:Number.isFinite(r.institutionNet)?r.institutionNet:null})),
    values:[{name:'외국인',value:sum('foreignNet')},{name:'기관',value:sum('institutionNet')}].filter(v=>v.value!==null)};
}
function candleSeries(a) {
  const byDate=new Map(),cutoff=day(a.marketDate);
  for(const c of a.sourceCandles||[]) {
    if(!/^\d{8}$/.test(day(c.date))||(cutoff&&day(c.date)>cutoff))continue;
    if(!['open','high','low','close'].every(k=>Number.isFinite(c[k])&&c[k]>0)||c.high<Math.max(c.open,c.close)||c.low>Math.min(c.open,c.close))continue;
    byDate.set(day(c.date),{date:day(c.date),open:c.open,high:c.high,low:c.low,close:c.close,volume:Number.isFinite(c.volume)&&c.volume>=0?c.volume:null});
  }
  return [...byDate.values()].sort((x,y)=>x.date.localeCompare(y.date)).slice(-60);
}
function candleFacts(candles) {
  if(candles.length<21)return null;
  const last=candles.at(-1),recent=candles.slice(-20),prior=candles.slice(-21,-1);
  const ma20=recent.reduce((n,c)=>n+c.close,0)/20;
  const averageVolume=prior.every(c=>c.volume!==null)?prior.reduce((n,c)=>n+c.volume,0)/20:null;
  return {close:last.close,changeRate:(last.close/candles.at(-2).close-1)*100,ma20,distanceToMa20:(last.close/ma20-1)*100,
    low20:Math.min(...recent.map(c=>c.low)),high20:Math.max(...recent.map(c=>c.high)),volume:last.volume,averageVolume,
    volumeRatio:averageVolume>0&&last.volume!==null?last.volume/averageVolume:null};
}
function chartData(a) {const candles=candleSeries(a);return {prices:priceSeries(a),candles,facts:candleFacts(candles),peers:peerSeries(a),flow:flowSeries(a),marketDate:day(a.marketDate)};}

function candleGeometry(candles,{x,y,width,height}) {
  if(candles.length<2)return null;
  const low=Math.min(...candles.map(c=>c.low)),high=Math.max(...candles.map(c=>c.high));
  const step=10**Math.floor(Math.log10(Math.max((high-low)/3,high*.01)));
  const min=Math.floor(low/step)*step-step*.2,max=Math.ceil(high/step)*step+step*.2;
  const scale=v=>y+height-(v-min)/(max-min)*height;
  const slot=width/candles.length;
  return {min,max,items:candles.map((c,i)=>({x:x+(i+.5)*slot,high:scale(c.high),low:scale(c.low),top:scale(Math.max(c.open,c.close)),height:Math.max(2,Math.abs(scale(c.open)-scale(c.close))),width:Math.max(2,slot*.62),up:c.close>=c.open}))};
}

// Chart primitives contain no invented observations or interpolated forecasts.
function priceGeometry(points,{x,y,width,height}) {
  if(points.length<2)return null;
  const values=points.map(p=>p.value),lo=Math.min(...values),hi=Math.max(...values);
  const pad=Math.max((hi-lo)*0.12,hi*0.01),min=lo-pad,max=hi+pad;
  const coords=points.map((p,i)=>({x:x+i/(points.length-1)*width,y:y+height-(p.value-min)/(max-min)*height}));
  return {min,max,coords,path:coords.map((p,i)=>`${i?'L':'M'}${p.x.toFixed(2)} ${p.y.toFixed(2)}`).join(' ')};
}
module.exports={priceSeries,peerSeries,flowSeries,candleSeries,candleFacts,candleGeometry,chartData,priceGeometry};
