const {test} = require('node:test');
const assert = require('node:assert/strict');
const {simulate, levelFor, personas, postXp, render} = require('./community_bot_lab.cjs');

test('50 distinct stable profiles and writing samples', () => {
  assert.equal(personas.length,50);
  for(const field of ['id','nickname'])assert.equal(new Set(personas.map(p=>p[field])).size,50);
  assert.equal(new Set(personas.map(p=>p.sample.content)).size,50);
  assert.ok(personas.every(p=>p.isSynthetic));
  assert.equal(new Set(personas.map(p=>p.focus)).size,50);
  assert.ok(personas.every(p=>['반도체','바이오','배당','ETF','공시','재무제표','밸류에이션','차트','매매복기','거시경제','조선·방산','배터리·소재','미국주식','리스크관리','주식기초'].includes(p.interest)));
  assert.deepEqual(Object.fromEntries(['주식 이야기','주식 잡담','일상 잡담'].map(kind=>[kind,personas.filter(p=>p.sample.kind===kind).length])), {'주식 이야기':30,'주식 잡담':10,'일상 잡담':10});
});
test('seed reproducibility and variation', () => {
  assert.deepEqual(simulate({seed:42}),simulate({seed:42}));
  assert.notDeepEqual(simulate({seed:42}).events,simulate({seed:43}).events);
});
test('schedules respect KST windows, cooldowns, daily caps, and XP', () => {
  const data=simulate({days:30});const last=new Map();const totals=new Map();const dates=new Map();const seen=new Set();
  for(const e of data.events){
    const p=personas.find(p=>p.id===e.personaId);const t=Date.parse(e.at);const kst=new Date(t+9*3600000);const date=e.kst.slice(0,10);
    assert.ok(kst.getUTCHours()>=p.activeHoursKst[0]&&kst.getUTCHours()<p.activeHoursKst[1]);
    assert.ok(!last.has(p.id)||t-last.get(p.id)>=p.minGapHours*3600000);last.set(p.id,t);
    assert.ok(!seen.has(date+p.id));seen.add(date+p.id);dates.set(date,(dates.get(date)||0)+1);
    assert.equal(e.xpBefore,totals.get(p.id)||0);assert.equal(e.xpAfter,e.xpBefore+postXp);totals.set(p.id,e.xpAfter);
    assert.equal(e.levelAfter,levelFor(e.xpAfter));assert.equal(e.status,'simulated_only');
  }
  assert.ok([...dates.values()].every(n=>n<=data.dailyCap));
  assert.ok(new Set(dates.values()).size>1);
  assert.equal(data.totals.firestoreWrites,0);assert.equal(data.totals.apiCalls,0);
  assert.equal(new Set(data.events.map(e=>e.kind)).size,3);
  assert.ok(data.events.every(e=>e.draftPrompt.includes(`글 분류: ${e.kind}`)));
});
test('app level progression is used rather than a level per post',()=>{
  assert.equal(levelFor(0),1);assert.equal(levelFor(9),1);assert.equal(levelFor(12),2);assert.equal(levelFor(25),3);
});
test('invalid simulation input is rejected',()=>{
  for(const opts of [{days:0},{days:31},{start:'2026-02-30'},{seed:-1},{dailyCap:51}])assert.throws(()=>simulate(opts));
});
test('preview embeds untrusted samples safely',()=>{
  const d=simulate();d.personas[0].sample.content='</script><script>alert(1)</script>';
  const html=render(d);assert.ok(!html.includes(d.personas[0].sample.content));assert.ok(html.includes('\\u003c/script>'));
});
