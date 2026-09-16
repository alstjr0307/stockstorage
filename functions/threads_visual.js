'use strict';
const sharp=require('sharp');
const path=require('node:path');
const {textImage}=require('./instagram_content');
const {sectorArtForAnalysis}=require('./instagram_sector_art');
const labels=[['priceTrend','차트 흐름'],['newsImpact','뉴스 영향'],['fundamentals','실적·재무'],['momentumFlow','매매 흐름'],['riskLevel','리스크 방어']];
const scoreColor=value=>value>=80?'#00876B':value>=60?'#3979B7':value>=40?'#BA811B':value>=20?'#CC6838':'#BD4747';
function scoreHeading(label) {
  const heading=String(label||'').split(/[:：—–\n]/)[0].trim();
  return heading&&Array.from(heading).length<=16?heading:'AI 평가';
}
async function renderThreadsImages(analysis,draft) {
  if(!Number.isFinite(analysis.score)||analysis.score<0||analysis.score>100||labels.some(([k])=>!Number.isFinite(analysis.subScores?.[k])||analysis.subScores[k]<0||analysis.subScores[k]>100))throw new Error('THREADS_SCORES_REQUIRED');
  const output=[],ink='#103D2D',muted='#50705D';
  const artPath=analysis.ticker==='035420'?path.join(__dirname,'threads_assets/naver.png'):path.join(__dirname,'instagram_assets/sectors',sectorArtForAnalysis(analysis).file);
  const date=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(draft.asOf));
  for(let page=0;page<2;page++) {
    let svg='<svg width="1080" height="1350" xmlns="http://www.w3.org/2000/svg"><rect width="1080" height="1350" fill="#F5F3E9"/><path d="M64 111H1016M64 1256H1016" stroke="#B5C5B2" stroke-width="2"/>';
    const overlays=[];
    const put=async(text,x,y,w,h,size,color=ink,bold=false)=>overlays.push({input:await textImage(text,w,h,size,Math.max(20,size-8),color,bold),left:x,top:y});
    await put('주식저장소 / AI 종목분석',64,47,950,46,30);
    await put(analysis.name,64,145,950,120,86,ink,true);
    if(page===0) {
      overlays.push({input:await sharp(artPath).resize(1080,590,{fit:'cover'}).png().toBuffer(),left:0,top:318});
      await put('이 기업, 지금 무엇을 봐야 할까?',64,250,950,55,34,ink,true);
      const sentences=draft.editorial.paragraphs[0].text.match(/[^.!?]+[.!?]?/g)||[];
      await put(sentences.slice(0,2).join('').trim(),64,932,950,230,42);
      await put('자세한 해설은 본문에서 이어갈게',64,1190,950,45,28,muted);
    } else {
      await put('AI 분석 점수',64,276,950,70,44);
      overlays.push({input:await sharp(artPath).resize(414,276,{fit:'cover'}).png().toBuffer(),left:602,top:352});
      await put(`${analysis.score}`,64,354,370,176,154,scoreColor(analysis.score),true);
      await put('/ 100',354,436,220,70,52,muted);
      await put(scoreHeading(analysis.scoreLabel),68,545,510,64,40,ink,true);
      for(const [i,[key,label]]of labels.entries()) {
        const y=659+i*92,value=analysis.subScores[key];
        await put(label,64,y,260,52,33);
        svg+=`<rect x="326" y="${y+7}" width="490" height="30" rx="15" fill="#DDE4D7"/><rect x="326" y="${y+7}" width="${490*value/100}" height="30" rx="15" fill="${scoreColor(value)}"/>`;
        await put(`${value}`,858,y-3,158,55,42,scoreColor(value),true);
      }
      await put('리스크 방어는 높을수록 위험이 낮다는 AI 평가야.\n점수는 수익률이나 상승 확률이 아니야.',64,1144,950,88,27,muted);
    }
    await put(`${date} 기준 · AI 분석 참고 자료`,64,1280,950,40,26,muted);
    svg+='</svg>';
    output.push(await sharp(Buffer.from(svg)).composite(overlays).jpeg({quality:94}).toBuffer());
  }
  return output;
}
module.exports={renderThreadsImages,scoreHeading};
