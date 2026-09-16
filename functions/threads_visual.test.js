'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),sharp=require('sharp');
const {renderThreadsImages,scoreHeading}=require('./threads_visual');
const base=require('../tools/instagram_ai_full_sample.json');
test('long colon-delimited analysis labels render both images without overflowing the score heading',async()=>{
  for(const [ticker,name]of [['012450','한화에어로스페이스'],['003670','포스코퓨처엠']]){
    const analysis={...base,ticker,name,scoreLabel:'중립: 재무·수주와 같은 펀더멘털 신호가 우호적이지만 단기 기술적 약점 및 공시·수급 변수로 주의 요인이 있어서 우호 구간으로 평가합니다.'};
    assert.equal(scoreHeading(analysis.scoreLabel),'중립');
    const images=await renderThreadsImages(analysis,{asOf:base.updatedAt,editorial:{paragraphs:[{text:'회사 실적과 주가 흐름을 함께 살펴볼게.'}]}});
    assert.equal(images.length,2);
    for(const image of images){const m=await sharp(image).metadata();assert.equal(m.width,1080);assert.equal(m.height,1350);}
  }
  assert.equal(scoreHeading('중립：설명'),'중립');
  assert.equal(scoreHeading('중립 — 설명'),'중립');
  assert.equal(scoreHeading('아주 긴 설명문만 있고 평가 구분 기호는 없는 경우'),'AI 평가');
});
