'use strict';
const {createHash}=require('node:crypto');
const dayKey=date=>new Date(date.getTime()+9*3600000).toISOString().slice(0,10);
function canonical(value) {
  if(Array.isArray(value))return value.map(canonical);
  if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().filter(k=>value[k]!==undefined).map(k=>[k,canonical(value[k])]));
  return value;
}
const analysisHash=analysis=>createHash('sha256').update(JSON.stringify(canonical(analysis))).digest('hex');
function fresh(analysis,now=new Date()) {
  const at=Date.parse(analysis?.updatedAt||'');
  return Number.isFinite(at)&&at<=now.getTime()&&now.getTime()-at<12*3600000&&String(analysis.marketDate)===dayKey(now).replace(/-/g,'');
}
async function ensureSharedAnalysis({prior={},key,create,save,now,allowPriorMarketDay=false}) {
  // Once either channel can consume the snapshot, retries must never replace it.
  const analysis=prior.analysis||await create();
  if(!allowPriorMarketDay&&!fresh(analysis,now||new Date()))throw Error('SOCIAL_ANALYSIS_STALE');
  const hash=analysisHash(analysis);
  if(prior.analysisHash&&prior.analysisHash!==hash)throw Error('SOCIAL_ANALYSIS_CHANGED');
  await save({analysis,analysisId:key,analysisHash:hash,sharedAnalysisReady:true});
  return analysis;
}
function isThreadsSource(id,job,now=new Date()) {
  if(id.endsWith('_draft')||!fresh(job.analysis,now))return false;
  // The new readiness flag is independent of Instagram rendering/publication.
  // Legacy saved drafts remain consumable during rollout.
  if(!job.sharedAnalysisReady&&!['draft','uploading','published','publishing','publish_uncertain','failed'].includes(job.status))return false;
  return !job.analysisHash||job.analysisHash===analysisHash(job.analysis);
}
module.exports={analysisHash,ensureSharedAnalysis,isThreadsSource,fresh};
