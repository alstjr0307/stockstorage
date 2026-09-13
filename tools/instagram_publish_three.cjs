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
 const results=[];
 for(let i=1;i<=3;i++){
   process.env.INSTAGRAM_LOCAL_SLOT=`manual_${batch}_${i}`;
   console.log(JSON.stringify({event:'start',slot:process.env.INSTAGRAM_LOCAL_SLOT}));
   try{await fn.run({});}catch(e){console.log(JSON.stringify({event:'failed',slot:process.env.INSTAGRAM_LOCAL_SLOT,code:e.code||e.message}));}
   const sel=(await db.doc(`_admin/instagramAutomation/selections/${day}_${process.env.INSTAGRAM_LOCAL_SLOT}`).get()).data();
   for(const stock of sel?.stocks||[]){const d=(await db.doc(`_admin/instagramAutomation/jobs/${day}_${stock.market}_${stock.ticker}`).get()).data()||{};results.push({stock:stock.name,status:d.status,error:d.error,links:d.parts?.map(p=>p.permalink).filter(Boolean)});}
   console.log(JSON.stringify({event:'result',results}));
 }
 require('fs').mkdirSync('output/instagram-manual',{recursive:true});require('fs').writeFileSync(`output/instagram-manual/${batch}.json`,JSON.stringify(results,null,2));
 if(results.length!==3||results.some(r=>r.status!=='published'))process.exitCode=1;
})().catch(e=>{console.error(e.code||e.message);process.exitCode=1});

