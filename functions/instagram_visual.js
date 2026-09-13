'use strict';
const sharp=require('sharp');
const path=require('node:path');
const {candleGeometry}=require('./instagram_charts');
const C={paper:'#FFFCF3',ink:'#3C2D22',blue:'#487DA5',accent:'#86562A',muted:'#776D61',rule:'#E8DFD0',red:'#C65C50'};
const esc=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const fmt=v=>Math.round(v).toLocaleString('ko-KR');
// Match the app's score thresholds; use darker shades on the cream background.
const scoreColor=value=>!Number.isFinite(value)?'#64748B':value>=70?'#16845B':value>=50?'#B87308':'#C8414F';
async function centeredText(value,cx,cy,w,h,size,color,bold=false) {
  const input=await sharp(await type(value,w,h,size,color,bold)).trim().png().toBuffer();
  const {width,height}=await sharp(input).metadata();
  return {input,left:Math.round(cx-width/2),top:Math.round(cy-height/2)};
}
async function type(value,w,h,size,color,bold=false) {
  const font=bold?'Bold':'Regular';
  const headline=bold&&size>=54;
  const family=headline?'Gmarket Sans TTF Bold':`SUIT ${font}`;
  const file=headline?'GmarketSansTTFBold.ttf':`SUIT-${font}.ttf`;
  const joined=String(value).split(/(\s+)/).map(v=>/^\s+$/.test(v)?v:[...v].join('\u2060')).join('');
  for(let n=size;n>=Math.max(size>=66?54:size-4,Math.min(size,20));n-=2) {
    const {data,info}=await sharp({text:{text:`<span foreground="${color}">${esc(joined)}</span>`,font:`${family} ${n}`,fontfile:path.join(__dirname,'instagram_assets',file),width:w,dpi:72,rgba:true,wrap:'word-char',spacing:Math.round(n*.28)}}).png().toBuffer({resolveWithObject:true});
    if(info.width<=w&&info.height<=h)return data;
  }
  throw new Error('CARD_TEXT_OVERFLOW');
}
async function render(draft) {
  const images=[];
  for(const [i,c] of draft.cards.entries()) {
    const dark=c.cta,fg=dark?C.paper:C.ink,muted=dark?'#A9ADA8':C.muted;
    const overlays=[];let svg='';
    const put=async(t,x,y,w,h,size,color=fg,bold=false)=>{if(t)overlays.push({input:await type(t,w,h,size,color,bold),left:Math.round(x),top:Math.round(y)});};
    const line=(x,y,w,color=C.rule)=>{svg+=`<path d="M${x} ${y}h${w}" stroke="${color}"/>`;};
    const rect=(x,y,w,h,color)=>{svg+=`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${color}"/>`;};
    const panel=(x,y,w,h,color='#F3EEE5',radius=24)=>{svg+=`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${radius}" fill="${color}"/>`;};
    rect(60,57,7,28,'#E4B23C');
    await put('주식저장소',85,52,600,50,26,fg,true);
    await put(`${String(i+1).padStart(2,'0')} / 10`,864,59,156,34,24,muted);
    if(!c.cover&&!c.cta)line(60,120,960);
    const prices=draft.charts?.prices||[];
    const candles=draft.charts?.candles||[];
    const photo=async(file,x,y,w,h,fit='cover')=>{
      if(!file||path.basename(file)!==file)return;
      overlays.push({input:await sharp(path.join(__dirname,'instagram_assets','companies',file)).resize(w,h,{fit,background:'#FFFFFF'}).png().toBuffer(),left:x,top:y});
    };
    const sectorPhoto=async(file,x,y,w,h,fit='cover')=>{
      if(!file||path.basename(file)!==file)return false;
      overlays.push({input:await sharp(path.join(__dirname,'instagram_assets','sectors',file)).resize(w,h,{fit}).png().toBuffer(),left:x,top:y});
      return true;
    };
    const drawCandles=async(y,h)=>{
      const g=candleGeometry(candles,{x:60,y,width:814,height:h});
      if(!g){await put('가격 자료가 없어 캔들을 표시하지 않았어요.',60,y+70,950,100,30,muted);return;}
      for(let k=0;k<3;k++) {
        const yy=y+k*h/2;line(60,yy,820,'#D5D7D0');
        await put(fmt(g.max-k*(g.max-g.min)/2),892,Math.round(yy-12),128,34,22,muted);
      }
      for(const v of g.items){const color=v.up?C.red:C.blue;svg+=`<path d="M${v.x} ${v.high}V${v.low}" stroke="${color}" stroke-width="2"/><rect x="${v.x-v.width/2}" y="${v.top}" width="${v.width}" height="${v.height}" fill="${color}"/>`;}
      const date=d=>d.slice(4,6)+'.'+d.slice(6,8);
      await put(date(candles[0].date),60,y+h+16,180,36,24,muted);
      await put(date(candles.at(-1).date),760,y+h+16,160,36,24,muted);
    };
    const points=async(y,height,grid=false)=>{
      if(grid) {
        const rows=Math.ceil(c.points.length/2),rh=height/rows;
        for(const [n,p] of c.points.entries()) {
          const x=60+(n%2)*494,yy=y+Math.floor(n/2)*rh;
          panel(x,yy,466,rh-18);
          await put(p.headline,x+24,yy+24,418,70,32,fg,true);
          await put(p.body,x+24,yy+100,418,rh-126,32,muted);
        }
      } else {
        const rh=height/c.points.length;
        for(const [n,p] of c.points.entries()) {
          const yy=y+n*rh;
          panel(60,yy,960,rh-18);
          panel(84,yy+28,56,56,'#F6DE9A',18);
          await put(String(n+1).padStart(2,'0'),95,yy+39,46,42,26,C.blue,true);
          await put(p.headline,170,yy+29,810,68,36,fg,true);
          await put(p.body,170,yy+104,810,rh-130,32,muted);
        }
      }
    };
    if(c.cover) {
      panel(60,161,298,60,'#F7D979',30);
      await put('오늘의 종목 분석',84,176,850,44,28,C.ink,true);
      await put(draft.name,60,270,960,188,100,fg,true);
      await put(c.title.replace(/\n/g,' '),60,477,945,210,72,fg,true);
      panel(60,722,960,488,'#F3EEE5',32);
      if(draft.brand?.heroFile)await photo(draft.brand.heroFile,84,746,912,440,draft.ticker==='035420'?'cover':'contain');
      await put('이 회사, 숫자와 이야기로 살펴보기',60,1260,840,48,28,muted);
      await put('→',945,1244,75,75,48,C.blue,true);
    } else if(c.cta) {
      await put('내가 보는 종목도',60,204,950,76,44,'#F7D979');
      await put('더 많은 종목 분석이\n궁금하다면?',60,335,960,300,80,fg,true);
      line(60,765,960,'#5A605B');
      await put('주식저장소에서\n관심 종목을 찾아보세요.',60,828,950,190,52,fg,true);
      await put('프로필에서 앱 다운로드  ↗',60,1086,950,90,44,'#F7D979',true);
      await put('@tf_stockstorage',60,1180,950,42,26,muted);
    } else {
      panel(60,156,Math.min(920,[...c.label].length*25+52),64,'#F7D979',32);
      await put(c.label,84,172,900,42,26,C.ink,true);
      await put(c.layout==='score'?'AI 분석 점수':c.title,60,251,960,156,64,fg,true);
      if(c.layout==='flow') {
        const flow=draft.charts?.flow,rows=flow?.rows||[];
        await put(`확인된 ${rows.length}거래일 · 단위 주`,60,420,960,54,30,muted);
        await put('+ 순매수  /  − 순매도',60,482,960,46,28,muted);
        const cap=Math.max(1,...rows.flatMap(r=>[r.foreign,r.institution]).filter(Number.isFinite).map(Math.abs));
        for(const [n,key] of ['foreign','institution'].entries()) {
          const y=652+n*380,zero=y+100,color=n===0?C.blue:'#BD6228';
          await put(n===0?'외국인':'기관',60,y-62,900,56,40,color,true);
          line(60,zero,820,C.ink);
          for(const sign of [-1,1]){line(60,zero-sign*100,820);await put(`${sign>0?'+':'−'}${fmt(cap)}`,890,zero-sign*100-13,130,40,21,muted);}
          await put('0',900,zero-14,110,38,22,muted);
          const slot=820/Math.max(rows.length,1);
          for(const [j,r] of rows.entries()) {
            const x=60+(j+.5)*slot,v=r[key];
            if(v===null)await put('×',Math.round(x-10),zero-15,32,34,23,muted);
            else {const h=Math.abs(v)/cap*100;rect(x-slot*.31,v>=0?zero-h:zero,slot*.62,Math.max(h,1),color);}
            if(j%2===0||j===rows.length-1)await put(r.date.slice(4,6)+'.'+r.date.slice(6,8),Math.round(x-26),zero+122,64,36,18,muted);
          }
        }
        if(!rows.length)await put('일별 매매 자료가 없어요.',60,704,940,80,40,fg);
        else if(rows.some(r=>r.foreign===null||r.institution===null))await put('× 표시는 확인되지 않은 값이에요.',60,1310,950,32,22,muted);
      } else if(c.layout==='candles') {
        await put(`최근 ${candles.length||'—'}거래일 · 일봉 · 원${draft.intraday?' · 오늘은 장중 값':''}`,60,420,950,48,28,muted);
        await put('빨강: 종가 ≥ 시가    파랑: 종가 < 시가',60,480,950,42,25,muted);
        await drawCandles(565,287);
        const f=draft.charts?.facts;
        if(f){
          const signed=v=>(v>=0?'+':'')+v.toFixed(1)+'%';
          const items=[[draft.intraday?'분석 시점 현재가':'마지막 종가',`${fmt(f.close)}원 · 전일 대비 ${signed(f.changeRate)}`],['20일 평균과 비교',`${fmt(f.ma20)}원 대비 ${signed(f.distanceToMa20)}`],['최근 20거래일 가격 범위',`${fmt(f.low20)} ~ ${fmt(f.high20)}원`],[draft.intraday?'장중 누적 거래량':'마지막 거래량',f.volumeRatio===null?'거래량 비교 자료가 없어요.':`${fmt(f.volume)}주 · 앞선 20일 평균의 ${f.volumeRatio.toFixed(2)}배`]];
          for(const [n,[title,body]] of items.entries()){
            const x=60+n%2*494,y=945+Math.floor(n/2)*184;line(x,y,454,C.ink);
            await put(title,x,y+22,454,62,30,fg,true);await put(body,x,y+91,454,86,29,muted);
          }
        }
      } else if(c.layout==='valuation' && draft.charts?.peers?.length) {
        await put('동종 기업 PER',60,418,610,52,36,fg,true);
        await put('배 · 같은 업종도 차이가 있어요',550,426,470,40,24,muted);
        const peers=draft.charts.peers,max=Math.max(...peers.map(p=>p.value));
        const step=Math.min(58,278/peers.length);
        for(const [n,p] of peers.entries()) {
          const yy=492+n*step;
          await put(p.name,60,yy,235,40,26,fg);
          rect(310,yy+7,p.value/max*540,20,C.blue);
          await put(p.value.toFixed(2),884,yy-1,136,40,26,fg,true);
        }

        await points(790,530,true);
      } else if(c.layout==='company') {
        if(draft.sectorArt?.file) {
          await sectorPhoto(draft.sectorArt.file,60,414,960,238,'cover');
          panel(76,430,Math.min(466,[...draft.sectorArt.label].length*25+54),52,'#FFFCF3',26);
          await put(draft.sectorArt.label,100,443,420,34,23,C.ink,true);
        } else if(draft.brand?.heroFile) {
          await photo(draft.brand.heroFile,60,420,960,190,draft.ticker==='035420'?'cover':'contain');
        }
        await points(692,618);
      } else if(c.layout==='score') {
        panel(60,425,960,584);
        const color=scoreColor(c.score),score=Number.isFinite(c.score)?Math.max(0,Math.min(100,c.score)):0;
        svg+=`<circle cx="278" cy="662" r="139" fill="none" stroke="#E7DECE" stroke-width="18"/>`;
        if(score>0)svg+=`<circle cx="278" cy="662" r="139" fill="none" stroke="${color}" stroke-width="18" stroke-linecap="round" stroke-dasharray="${score/100*873.36} 873.36" transform="rotate(-90 278 662)"/>`;
        overlays.push(await centeredText(Number.isFinite(c.score)?String(c.score):'—',278,662,230,122,100,color,true));
        overlays.push(await centeredText('/ 100점',278,741,180,40,25,muted));
        const scores=[['차트',c.subScores?.priceTrend],['뉴스',c.subScores?.newsImpact],['재무',c.subScores?.fundamentals],['매매 흐름',c.subScores?.momentumFlow],['위험 평가',c.subScores?.riskLevel]].filter(([,v])=>Number.isFinite(v));
        for(const [n,[label,value]] of scores.entries()){
          const y=493+n*87;await put(label,512,y,310,42,28,fg,true);
          await put(String(value),917,y,65,42,28,scoreColor(value),true);
          panel(512,y+49,468,9,'#E7DECE',4);panel(512,y+49,Math.max(0,Math.min(100,value))*4.68,9,scoreColor(value),4);
        }
        await put('위험 평가는 높을수록 위험이 낮다는 뜻이에요.',94,942,880,44,24,muted);
        await points(1052,268,true);
      } else if(c.layout==='watch') {
        for(const [section,group] of [c,c.checklist].entries()) {
          const y=420+section*454;
          await put(section?'다음에 확인할 것':'걸리는 점',60,y,960,56,38,section?C.blue:C.red,true);
          const rows=Math.ceil(group.points.length/2),rh=370/rows;
          for(const [n,p] of group.points.entries()) {
            const x=60+n%2*494,yy=y+74+Math.floor(n/2)*rh;
            line(x,yy,454);
            await put(p.headline,x,yy+12,454,58,30,fg,true);
            await put(p.body,x,yy+74,454,rh-78,27,muted);
          }
        }
      } else if(c.layout==='scenario') {
        const colors=[C.blue,C.ink,C.red];
        for(const [n,p] of c.points.entries()) {
          const y=444+n*276;panel(60,y,960,250);rect(60,y+34,5,180,colors[n]);
          await put(['오른다면','제자리라면','내린다면'][n],88,y+35,255,85,38,colors[n],true);
          await put(p.headline,385,y+35,605,78,32,fg,true);
          await put(p.body,385,y+125,605,108,30,muted);
        }

      } else if(c.layout==='news') {
        if(draft.brand?.detailFile){
          await photo(draft.brand.detailFile,60,420,960,286,'cover');
          await points(754,566,true);
        }else if(draft.sectorArt?.file){
          await sectorPhoto(draft.sectorArt.file,60,420,960,286,'cover');
          await points(754,566,true);
        }else{
          panel(60,418,960,175,'#FFF0C5');
          await put(c.metric,90,447,900,64,46,C.blue,true);
          await put(c.metricLabel,90,524,900,44,28,muted);
          await points(630,690,true);
        }
      } else {
        const display=c.layout==='checklist'?'':c.metric;
        if(display){await put(display,60,414,960,112,76,c.layout==='risks'?C.red:C.blue,true);await put(c.metricLabel,60,543,950,58,26,muted);}
        await points(display?644:449,display?666:861,c.points.length===4);

      }
    }
    const bg=Buffer.from(`<svg width="1080" height="1350"><rect width="1080" height="1350" fill="${dark?C.ink:C.paper}"/>${svg}</svg>`);
    images.push(await sharp(bg).composite(overlays).jpeg({quality:94}).toBuffer());
  }
  return images;
}
module.exports={render,scoreColor,centeredText};
