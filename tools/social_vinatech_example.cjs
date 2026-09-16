'use strict';
// Explicit local operator workflow. Does not change the scheduled stock universe.
const path=require('node:path'),fs=require('node:fs/promises');
const {randomUUID}=require('node:crypto');
const {googleRequest,googleToken,PROJECT}=require('./threads_setup.cjs');
const dir=path.resolve('output/social-vinatech-20260916');
async function secret(name){const s=await googleRequest(`https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/${name}/versions/latest:access`);return Buffer.from(s.payload.data,'base64').toString().trim();}
async function upload(file,name,type){
  const bucket=PROJECT+'.firebasestorage.app',token=randomUUID(),credential=await googleToken();
  const r=await fetch(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=media&name=${encodeURIComponent(name)}`,{method:'POST',headers:{Authorization:`Bearer ${credential.access_token}`,'Content-Type':type},body:await fs.readFile(file),signal:AbortSignal.timeout(120000)});
  if(!r.ok)throw Error(`STORAGE_UPLOAD_${r.status}`);
  await googleRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(name)}`,'PATCH',{metadata:{firebaseStorageDownloadTokens:token}});
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(name)}?alt=media&token=${token}`;
}
async function main(){
  if(process.env.K_SERVICE)throw Error('LOCAL_ONLY');
  const mode=process.argv[2];if(!['prepare','publish'].includes(mode))throw Error('MODE_REQUIRED');
  process.env.GOOGLE_APPLICATION_CREDENTIALS=path.resolve('functions/serviceAccountKey.json');
  process.env.GCLOUD_PROJECT=PROJECT;process.env.FIREBASE_CONFIG=JSON.stringify({projectId:PROJECT,storageBucket:PROJECT+'.firebasestorage.app'});
  const admin=require('../functions/node_modules/firebase-admin');
  if(mode==='prepare'){
    for(const name of ['OPENAI_API_KEY','DART_API_KEY'])process.env[name]=await secret(name);
    process.env.INSTAGRAM_LOCAL_PREVIEW='1';process.env.INSTAGRAM_PREVIEW_DIR=path.join(dir,'instagram');process.env.INSTAGRAM_LOCAL_SLOT='manual_vinatech_20260916';
    const fn=require('../functions/index').generateDailyInstagramAnalysis,db=admin.firestore();
    const {dateKey,collectHistory,DEFAULT_STOCKS}=require('../functions/instagram_daily');
    const stock={ticker:'126340',name:'비나텍',market:'KQ',keywords:['비나텍','VINATech','126340']},day=dateKey(new Date());
    const history=await collectHistory(stock),marketDate=history.candles.at(-1).date;
    const ref=db.doc(`_admin/instagramAutomation/selections/${day}_manual_vinatech_20260916_draft`);
    await ref.set({day,slot:'manual_vinatech_20260916',marketDate,stocks:[stock],ranking:[],method:'user_requested_example',createdAt:new Date()});
    console.log(JSON.stringify({event:'prepare',stock:stock.name,marketDate}));
    await fn.run({});
    const a=JSON.parse(await fs.readFile(path.join(dir,'instagram/analysis.json'),'utf8'));
    if(a.ticker!=='126340')throw Error('WRONG_STOCK');
    const {createThreadsDraft}=require('../functions/threads_content');
    const {renderThreadsImages}=require('../functions/threads_visual');
    console.log('THREADS_EDITORIAL_START');
    const draft=await createThreadsDraft(a),images=await renderThreadsImages(a,draft);
    await fs.mkdir(path.join(dir,'threads'),{recursive:true});
    await fs.writeFile(path.join(dir,'threads/draft.json'),JSON.stringify(draft,null,2));
    for(let i=0;i<images.length;i++)await fs.writeFile(path.join(dir,`threads/${i+1}.jpg`),images[i]);
    console.log(JSON.stringify({event:'prepared',name:a.name,marketDate:a.marketDate,posts:draft.posts.length}));
    return;
  }
  admin.initializeApp({credential:admin.credential.cert(require('../functions/serviceAccountKey.json')),projectId:PROJECT});
  const db=admin.firestore(),a=JSON.parse(await fs.readFile(path.join(dir,'instagram/analysis.json'),'utf8'));
  if(a.ticker!=='126340'||Date.now()-Date.parse(a.updatedAt)>2*3600000)throw Error('EXAMPLE_NOT_FRESH');
  const day=require('../functions/instagram_daily').dateKey(new Date()),key=`${day}_KQ_126340`;
  const {analysisHash}=require('../functions/social_analysis'),hash=analysisHash(a);
  const {InstagramGraph}=require('../functions/instagram_graph'),{ThreadsGraph}=require('../functions/threads_graph');
  const ig=new InstagramGraph(await secret('INSTAGRAM_ACCESS_TOKEN'),'v23.0'),th=new ThreadsGraph(await secret('THREADS_ACCESS_TOKEN'),'tf_stockstorage');
  await ig.identity();await th.identity();
  for(const [channel,graph]of [['instagram',ig],['threads',th]]){
    const ref=db.doc(`_admin/${channel}Automation/jobs/${key}`),owner=randomUUID();
    const claimed=await db.runTransaction(async tx=>{const previous=(await tx.get(ref)).data();if(previous&&(['published','publishing','publish_uncertain'].includes(previous.status)||previous.leaseUntil?.toMillis?.()>Date.now()))return false;tx.set(ref,{status:'generating',owner,day,stock:{ticker:a.ticker,name:a.name,market:'KQ'},analysis:a,analysisId:key,analysisHash:hash,manualExample:true,startedAt:new Date(),leaseUntil:new Date(Date.now()+30*60000)},{merge:true});return true;});
    if(!claimed){console.log(JSON.stringify({channel,status:'already_handled'}));continue;}
    let phase='generating';
    const save=async fields=>{await db.runTransaction(async tx=>{if((await tx.get(ref)).data()?.owner!==owner)throw Error('LEASE_LOST');tx.set(ref,{...fields,updatedAt:new Date()},{merge:true});});if(fields.status)phase=fields.status;};
    try{
      if(channel==='instagram'){
        const url=await upload(path.join(dir,'instagram/reel.mp4'),`instagram/${key}/${owner}/reel.mp4`,'video/mp4');
        await save({status:'uploading',mediaType:'REELS',videoUrl:url});
        await graph.reel(url,await fs.readFile(path.join(dir,'instagram/caption.txt'),'utf8'),save);
      }else{
        const draft=JSON.parse(await fs.readFile(path.join(dir,'threads/draft.json'),'utf8'));
        const urls=[];for(let i=1;i<=2;i++)urls.push(await upload(path.join(dir,`threads/${i}.jpg`),`threads/${key}/${owner}/${i}.jpg`,'image/jpeg'));
        await save({status:'uploading',draft,imageUrls:urls});await graph.publish(draft,urls,save);
      }
      const done=(await ref.get()).data();
      await db.doc(`_admin/${channel}Automation`).set({lastPublishedAt:new Date(),lastJob:key,lastMediaId:done.mediaId},{merge:true});
      console.log(JSON.stringify({channel,status:done.status,permalink:done.permalink,parts:done.mediaIds?.length,analysisHash:hash}));
    }catch(e){if(phase!=='published')await save({status:phase==='publishing'?'publish_uncertain':'failed',error:/^[A-Z0-9_]+$/.test(e.message)?e.message:'EXAMPLE_FAILED',leaseUntil:new Date(0)});throw e;}
  }
}
main().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message)?e.message:`EXAMPLE_FAILED_${e.code||e.name}`);process.exitCode=1;});
