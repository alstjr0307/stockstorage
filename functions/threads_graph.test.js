'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {ThreadsGraph}=require('./threads_graph');
const {eligible,fresh}=require('./threads_daily');
const urls=['https://firebasestorage.googleapis.com/a','https://firebasestorage.googleapis.com/b'];
const draft={posts:[{text:'오늘의 AI종목분석은 NAVER이야'},{text:'설명이 이어져.'},{text:'앱 설치 링크야.'}],imageAlt:'NAVER'};
test('API 24 retries the same confirmed unpublished container; ambiguity never retries',async()=>{
  for(const status of ['FINISHED','PUBLISHED']){
    let publishes=0;
    const g=new ThreadsGraph('test','tf_stockstorage',{pause:async()=>{},transport:async(url,options)=>{
      if(url.pathname.endsWith('/threads_publish')){
        assert.equal(options.body.get('creation_id'),'123');publishes++;
        return publishes===1?{ok:false,json:async()=>({error:{code:24}})}:{ok:true,json:async()=>({id:'456'})};
      }
      return {ok:true,json:async()=>({status})};
    }});g.userId='12';
    if(status==='FINISHED'){assert.equal((await g.publishContainer('123')).id,'456');assert.equal(publishes,2);}
    else{await assert.rejects(g.publishContainer('123'),/API_24/);assert.equal(publishes,1);}
  }
});
function mock(failAt=0,account='tf_stockstorage') {
  const calls=[],saves=[];let count=0,published=0;
  const graph=new ThreadsGraph('secret','tf_stockstorage',{pause:async()=>{},transport:async(url,options)=>{
    const path=url.pathname,params=Object.fromEntries(options.body||[]);calls.push({path,params});
    let data;
    if(path.endsWith('/me'))data={id:'12',username:account};
    else if(path.endsWith('/threads_publish')){published++;assert.equal(saves.at(-1).status,'publishing');if(published===failAt)throw new Error('network');data={id:String(900+published)};}
    else if(path.endsWith('/threads'))data={id:String(++count)};
    else data=url.searchParams.get('fields')==='permalink'?{permalink:'https://www.threads.com/@tf_stockstorage/post/test'}:{status:'FINISHED'};
    return {ok:true,json:async()=>data};
  }});
  return {graph,calls,saves,save:async fields=>saves.push(fields)};
}
test('two images become one carousel, replies chain in order, state saved before publish',async()=>{
  const m=mock(),ids=await m.graph.publish(draft,urls,m.save);
  assert.deepEqual(ids,['901','902','903']);
  const creations=m.calls.filter(c=>c.path.endsWith('/threads'));
  assert.equal(creations.filter(c=>c.params.is_carousel_item==='true').length,2);
  assert.equal(creations[2].params.media_type,'CAROUSEL');
  assert.equal(creations[2].params.children,'1,2');
  assert.equal(creations[3].params.reply_to_id,'901');
  assert.equal(creations[4].params.reply_to_id,'902');
  assert.ok(m.saves.some(s=>s.status==='published'));
});
test('ambiguous reply failure retains non-replayable state and confirmed ids',async()=>{
  const m=mock(2);await assert.rejects(m.graph.publish(draft,urls,m.save),/NETWORK/);
  assert.equal(m.saves.at(-1).status,'publishing');assert.deepEqual(m.saves.at(-1).mediaIds,['901']);
  const before=m.calls.length;
  await assert.rejects(m.graph.publish(draft,urls,m.save,{status:'publishing'}),/REPLAY_BLOCKED/);
  assert.equal(m.calls.length,before);
});
test('wrong account and wrong media count never publish',async()=>{
  const m=mock(0,'other');await assert.rejects(m.graph.publish(draft,urls,m.save),/ACCOUNT_MISMATCH/);
  assert.equal(m.calls.length,1);await assert.rejects(m.graph.publish(draft,urls.slice(0,1),m.save),/TWO_PUBLIC_IMAGES/);
});
test('stale market data and live or uncertain jobs are excluded',()=>{
  const now=new Date('2026-09-15T03:00:00Z');
  assert.equal(fresh({updatedAt:'2026-09-15T02:00:00Z',marketDate:'20260915'},now),true);
  assert.equal(fresh({updatedAt:'2026-09-15T02:00:00Z',marketDate:'20260914'},now),false);
  assert.equal(fresh({updatedAt:'2026-09-16T02:00:00Z',marketDate:'20260915'},now),false);
  for(const status of ['publishing','publish_uncertain','published'])assert.equal(eligible({status},now),false);
  assert.equal(eligible({status:'generating',leaseUntil:new Date(now.getTime()+1000)},now),false);
  assert.equal(eligible({status:'failed',leaseUntil:new Date(0)},now),true);
  assert.equal(eligible({status:'failed',attempts:3,leaseUntil:new Date(0)},now),false);
});
