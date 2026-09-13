'use strict';
const path=require('path');
const auth=require('C:/Users/alswp/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');
(async()=>{
 if(process.env.K_SERVICE)throw Error('LOCAL_ONLY');
 const project='stockstorage-13828';
 const account=auth.getGlobalDefaultAccount();
 const token=await auth.getAccessToken(account.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform']);
 for(const name of ['OPENAI_API_KEY','DART_API_KEY','INSTAGRAM_ACCESS_TOKEN']){
   const r=await fetch(`https://secretmanager.googleapis.com/v1/projects/${project}/secrets/${name}/versions/latest:access`,{headers:{Authorization:`Bearer ${token.access_token}`}});
   if(!r.ok)throw Error('SECRET_ACCESS_FAILED');
   const d=await r.json();process.env[name]=Buffer.from(d.payload.data,'base64').toString().trim();
 }
 process.env.GOOGLE_APPLICATION_CREDENTIALS=path.resolve('functions/serviceAccountKey.json');
 process.env.GCLOUD_PROJECT=project;process.env.FIREBASE_CONFIG=JSON.stringify({projectId:project,storageBucket:project+'.firebasestorage.app'});
 process.env.INSTAGRAM_LOCAL_PREVIEW='1';process.env.INSTAGRAM_LOCAL_PUBLISH='1';
 const fn=require('../functions/index').generateDailyInstagramAnalysis;
 const db=require('../functions/node_modules/firebase-admin').firestore();
 const {dateKey}=require('../functions/instagram_daily');
 const day=dateKey(new Date()),batch=process.argv[2];
 if(!/^[a-z0-9_-]+$/.test(batch||''))throw Error('BATCH_ID_REQUIRED');

 const suffix=process.argv[3]||'2';if(!['2','3'].includes(suffix))throw Error('INVALID_SLOT');const slot='manual_'+batch+'_'+suffix;
 const sel=(await db.doc('_admin/instagramAutomation/selections/'+day+'_'+slot).get()).data();
 const stock=sel.stocks[0];
 const cached=(await db.doc('users/instagram-automation/stock_ai_analyses/'+stock.market+'_'+stock.ticker).get()).data();
 if(!cached||Date.now()-cached.updatedAt.toMillis()>2*3600000)throw Error('CACHED_ANALYSIS_STALE');
 console.log(JSON.stringify({event:'retry_editorial',stock:stock.name}));
 await require('../functions/instagram_daily').runDailyInstagram({
   analyze:async()=>cached,
   fetchQuote:async()=>({price:cached.analysisPrice}),
   fetchValuation:async ticker=>{const r=await fetch('https://m.stock.naver.com/api/stock/'+ticker+'/integration',{headers:{'User-Agent':'Mozilla/5.0','Referer':'https://m.stock.naver.com'}});if(!r.ok)throw Error('VALUATION_FETCH_FAILED');return r.json();}
 },{slot});
 const job=(await db.doc('_admin/instagramAutomation/jobs/'+day+'_'+stock.market+'_'+stock.ticker).get()).data();
 console.log(JSON.stringify({event:'recovery_result',stock:stock.name,status:job.status,links:job.parts?.map(p=>p.permalink).filter(Boolean)}));
})().catch(e=>{console.error(e.code||e.message);process.exitCode=1});

