'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const sharp=require('sharp');
const {InstagramGraph}=require('./instagram_graph');
const {eligibleJob}=require('./instagram_daily');
const {annualRows,reelDraft,numeric}=require('./instagram_reel');
const {createEditorialSeries}=require('./instagram_editorial');
const {render}=require('./instagram_reel_frames');
const fixture=require('../tools/instagram_chart_sample.json');
test('annual figures retain missing values, estimates and actual year-over-year changes',()=>{
  const data={financeInfo:{trTitleList:[{key:'202412',isConsensus:'N'},{key:'202512',isConsensus:'N'},{key:'202612',isConsensus:'Y'}],rowList:[{title:'매출액',columns:{202412:{value:'1,000'},202512:{value:'1,200'},202612:{value:'1,500'}}},{title:'영업이익',columns:{202412:{value:'100'},202512:{value:'0'},202612:{value:'-'}}}]}};
  const rows=annualRows(data,'20260915');
  assert.deepEqual(rows.map(r=>r.year),[2021,2022,2023,2024,2025,2026,2027]);
  assert.equal(rows[0].revenue,null);assert.equal(rows[4].revenueGrowth,'+20.0%');assert.equal(rows[4].profitGrowth,'-100.0%');
  assert.equal(rows[5].estimate,true);assert.equal(rows[5].operatingProfit,null);assert.equal(rows[6].revenue,null);
  for(const value of [null,undefined,'','—','-','적자'])assert.equal(numeric(value),null);
});
test('every Reel cut is native 1080x1920 with the bottom 370 pixels clear',async()=>{
  const [draft]=await createEditorialSeries(fixture,new Date(fixture.updatedAt),{editorial:require('../tools/instagram_human_sample.json')});
  const prepared=reelDraft(draft,fixture);
  assert.equal(prepared.cards[2].layout,'score');assert.equal(prepared.charts.flow.rows.length,8);
  assert.equal(prepared.reelPeers[0].pbr,1.36);assert.equal(prepared.reelHigh52,null);
  const frames=await render(prepared);assert.equal(frames.length,11);
  for(const frame of frames){const m=await sharp(frame).metadata();assert.equal(m.width,1080);assert.equal(m.height,1920);
    const blank=await sharp(frame).extract({left:0,top:1550,width:1080,height:370}).png().toBuffer();
    const stats=await sharp(blank).stats();assert.ok(stats.channels.every(c=>c.min===c.max));}
});
function fakeGraph({publishError=false,readyError=false}={}) {
  const states=[],calls=[];
  const graph=new InstagramGraph('test','v23.0',async(url,options)=>{
    const pathname=new URL(url).pathname;calls.push({pathname,params:options.body?Object.fromEntries(options.body):{}});
    if(pathname.endsWith('/media_publish')){assert.equal(states.at(-1).status,'publishing');if(publishError)throw Error('timeout');return {ok:true,json:async()=>({id:'published-reel'})};}
    if(pathname.endsWith('/published-reel'))throw Error('metadata unavailable');
    const data=pathname.endsWith('/me')?{user_id:'123',username:'tf_stockstorage'}:pathname.endsWith('/media')?{id:'reel-container'}:{status_code:readyError?'ERROR':'FINISHED'};
    return {ok:true,json:async()=>data};
  });return {graph,states,calls,save:async v=>states.push(v)};
}
test('publishes a REELS container with persisted intent, no carousel children, and no retry for permalink failure',async()=>{
  const t=fakeGraph();assert.equal(await t.graph.reel('https://firebasestorage.googleapis.com/reel.mp4','caption',t.save),'published-reel');
  const creates=t.calls.filter(c=>c.pathname.endsWith('/media'));assert.equal(creates.length,1);assert.equal(creates[0].params.media_type,'REELS');assert.equal(creates[0].params.share_to_feed,'true');
  assert.equal(t.states.at(-1).status,'published');assert.equal(eligibleJob(t.states.at(-1)),false);
});
test('uncertain Reel publish stays blocked; failed processing never calls publish',async()=>{
  const t=fakeGraph({publishError:true});await assert.rejects(t.graph.reel('https://firebasestorage.googleapis.com/reel.mp4','caption',t.save),/NETWORK/);
  assert.equal(t.states.at(-1).status,'publishing');assert.equal(eligibleJob(t.states.at(-1)),false);
  const r=fakeGraph({readyError:true});await assert.rejects(r.graph.reel('https://firebasestorage.googleapis.com/reel.mp4','caption',r.save),/CONTAINER_ERROR/);
  assert.equal(r.calls.some(c=>c.pathname.endsWith('/media_publish')),false);
});
