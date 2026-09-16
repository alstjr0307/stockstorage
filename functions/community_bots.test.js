const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const bots=require('./community_bots');
test('ten persistent distinct personas; reproducible schedules across retries',()=>{
  assert.equal(bots.personas.length,10);
  assert.equal(new Set(bots.personas.map(p=>p.id)).size,10);
  assert.equal(new Set(bots.personas.map(p=>p.nickname)).size,10);
  const first=bots.planDay('2026-09-14');
  assert.deepEqual(first,bots.planDay('2026-09-14'));
  assert.notDeepEqual(first,bots.planDay('2026-09-14','different'));
  assert.equal(new Set(first.map(e=>e.personaId)).size,first.length);
  for(const e of first) assert.equal(bots.dayKey(new Date(e.scheduledAt)),'2026-09-14');
});
test('posts mix stock discussion, casual stock chat and everyday topics',()=>{
  const events=Array.from({length:28},(_,i)=>bots.planDay(`2026-09-${String(i+1).padStart(2,'0')}`)).flat();
  const categories=new Set(events.filter(e=>e.kind==='post').map(e=>e.category));
  assert.deepEqual([...categories].sort(),['일상 잡담','주식 이야기','주식 잡담'].sort());
  const prompt=bots.promptFor(bots.personas[0],events.find(e=>e.category==='일상 잡담'),[],null,null);
  assert.match(prompt,/일상 소재를 투자나 차트 이야기로 비유하거나 연결하지 않는다/);
  assert.doesNotMatch(prompt,/"sample"/);
});
test('post/comment/public journal XP matches app constants and thresholds',()=>{
  const dart=fs.readFileSync(require('node:path').join(__dirname,'../lib/services/firestore_service.dart'),'utf8');
  assert.match(dart,/_postScore = 3;/); assert.match(dart,/_commentScore = 1;/);
  const thresholds=dart.match(/_levelThresholds = \[([\s\S]*?)\];/)[1].replace(/\/\/[^\n]*/g,'').split(',').map(x=>x.trim()).filter(Boolean).map(Number);
  assert.deepEqual(bots.thresholds,thresholds);
  const post=bots.growth({},'post','2026-09-14');assert.equal(post.xp,3);
  const comment=bots.growth(post,'comment','2026-09-14');assert.equal(comment.xp,4);
  const journal=bots.growth(comment,'journal','2026-09-14');assert.equal(journal.xp,12);assert.equal(journal.level,2);
  assert.equal(bots.growth(journal,'journal','2026-09-14').xp,15);
});
test('paper trades conserve cash and basis without negative holdings',()=>{
  let state={cash:10000000,positions:{},realized:0};
  for(let i=0;i<500;i++) {
    const next=bots.paperTrade({id:'test-'+i},state);if(!next)continue;
    state=next.portfolio;
    assert.ok(state.cash>=0);
    const cost=Object.values(state.positions).reduce((s,p)=>{assert.ok(p.quantity>=0);assert.ok(p.cost>=-1e-6);return s+p.cost;},0);
    assert.ok(Math.abs(state.cash+cost-state.realized-10000000)<1e-5);
  }
});
test('disabled configuration never requests content or writes',async()=>{
  const result=await bots.runCommunityBots({db:{doc:()=>({get:async()=>({data:()=>({})})})},generateText:()=>assert.fail('unexpected API')});
  assert.equal(result.status,'disabled');
});
test('incomplete generation is rejected before publication',async()=>{
  await assert.rejects(bots.generate('test','prompt',async()=>({ok:true,json:async()=>({status:'incomplete'})})),/incomplete/);
});
