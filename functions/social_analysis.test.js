'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {ensureSharedAnalysis,isThreadsSource,analysisHash}=require('./social_analysis');
const {runDailyThreads}=require('./threads_daily');
const now=new Date('2026-09-15T03:00:00Z');
const analysis={ticker:'035420',name:'NAVER',updatedAt:'2026-09-15T02:00:00Z',marketDate:'20260915',score:64,summary:'same source'};
const key='2026-09-15_KS_035420';
test('render failure and retry keep one shared analysis for both channels',async()=>{
  let calls=0,job={status:'generating'};
  const create=async()=>{calls++;return structuredClone(analysis);};
  const save=async fields=>Object.assign(job,fields);
  await ensureSharedAnalysis({key,create,save,now});
  assert.equal(isThreadsSource(key,job,now),true);
  job.status='failed'; // Instagram render failed after shared data was saved.
  const threadHash=analysisHash(job.analysis);
  assert.equal(isThreadsSource(key,job,now),true);
  const retried=await ensureSharedAnalysis({prior:job,key,create,save,now});
  assert.equal(calls,1);assert.equal(analysisHash(retried),threadHash);
  assert.equal(job.analysisId,key);
});
test('stale, altered and preview snapshots cannot cross-publish',async()=>{
  const job={status:'draft',analysis,analysisHash:analysisHash(analysis)};
  assert.equal(isThreadsSource(key+'_draft',job,now),false);
  assert.equal(isThreadsSource(key,job,new Date('2026-09-16T03:00:00Z')),false);
  const altered={...job,analysis:{...analysis,score:90}};
  assert.equal(isThreadsSource(key,altered,now),false);
  await assert.rejects(ensureSharedAnalysis({prior:altered,key,now,save:async()=>{throw Error('must not write');}}),/CHANGED/);
  await assert.rejects(ensureSharedAnalysis({prior:job,key,now:new Date('2026-09-16T03:00:00Z'),save:async()=>{throw Error('must not write');}}),/STALE/);
  assert.equal(analysisHash({score:64,summary:'x'}),analysisHash({summary:'x',score:64}));
});
test('Threads consumes the saved source even when Instagram failed, with matching identity',async()=>{
  const documents=new Map();
  const configPath='_admin/threadsAutomation';
  documents.set(configPath,{enabled:true,account:'tf_stockstorage'});
  const source={status:'failed',day:'2026-09-15',sharedAnalysisReady:true,analysis,analysisId:key,analysisHash:analysisHash(analysis)};
  const ref=path=>({path,collection:name=>({doc:id=>ref(`${path}/${name}/${id}`),where:()=>({get:async()=>({docs:[{id:key,data:()=>source}]})})}),get:async()=>({data:()=>documents.get(path)}),set:async fields=>documents.set(path,{...documents.get(path),...fields})});
  const db={collection:name=>({doc:id=>ref(`${name}/${id}`)}),runTransaction:async fn=>fn({get:r=>r.get(),set:(r,fields)=>documents.set(r.path,{...documents.get(r.path),...fields})})};
  let received;
  const result=await runDailyThreads({db,now,draftOnly:true,createDraft:async a=>{received=a;return {body:'test',editorialVersion:require('./threads_editorial').VERSION};},render:async()=>[Buffer.from('a'),Buffer.from('b')]});
  assert.deepEqual(received,analysis);
  assert.equal(result.results[0].status,'preview_complete');
  const saved=documents.get(`${configPath}/jobs/${key}_preview`);
  assert.equal(saved.analysisId,key);assert.equal(saved.analysisHash,source.analysisHash);
  Object.assign(saved,{status:'failed',leaseUntil:new Date(0)});
  await runDailyThreads({db,now,draftOnly:true,createDraft:async()=>assert.fail('cached copy must not call AI again'),render:async()=>[Buffer.from('a'),Buffer.from('b')]});
});
