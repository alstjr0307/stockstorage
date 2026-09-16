'use strict';
const admin=require('../functions/node_modules/firebase-admin');
const {googleRequest}=require('./threads_setup.cjs');
const {ThreadsGraph}=require('../functions/threads_graph');
admin.initializeApp({credential:admin.credential.cert(require('../functions/serviceAccountKey.json')),projectId:'stockstorage-13828'});
(async()=>{
  const key=process.argv[2];if(!/^\d{4}-\d{2}-\d{2}_KS_\d{6}$/.test(key))throw Error('INVALID_JOB');
  const ref=admin.firestore().doc('_admin/threadsAutomation/jobs/'+key),d=(await ref.get()).data();
  if(d.status!=='publish_uncertain'||d.error!=='THREADS_API_24'||d.activePart>=d.draft.posts.length||d.mediaIds.length!==d.activePart)throw Error('NOT_A_CONFIRMED_API_24');
  const s=await googleRequest('https://secretmanager.googleapis.com/v1/projects/stockstorage-13828/secrets/THREADS_ACCESS_TOKEN/versions/latest:access');
  const graph=new ThreadsGraph(Buffer.from(s.payload.data,'base64').toString().trim(),'tf_stockstorage');await graph.identity();
  const status=await graph.request(d.containerId,'GET',{fields:'id,status'});if(status.status!=='FINISHED')throw Error('CONTAINER_NOT_UNPUBLISHED_FINISHED');
  await admin.firestore().runTransaction(async tx=>{const current=(await tx.get(ref)).data();if(current.status!==d.status||current.containerId!==d.containerId)throw Error('JOB_CHANGED');tx.set(ref,{status:'publishing',resumeStartedAt:new Date()},{merge:true});});
  try{
    // Reuse the confirmed unpublished container; never create another reply.
    const ids=[...d.mediaIds];
    for(let i=d.activePart;i<d.draft.posts.length;i++){
      const container=i===d.activePart?d.containerId:await graph.container({media_type:'TEXT',text:d.draft.posts[i].text,reply_to_id:ids.at(-1)});
      await ref.set({status:'publishing',activePart:i,containerId:container,mediaIds:[...ids]},{merge:true});
      const result=await graph.publishContainer(container);
      if(!/^\d+$/.test(String(result.id||'')))throw Error('MISSING_PUBLISHED_ID');
      ids.push(String(result.id));await ref.set({mediaIds:[...ids],completedParts:ids.length},{merge:true});
    }
    await ref.set({status:'published',mediaIds:ids,mediaId:ids[0],completedParts:ids.length,publishedAt:new Date(),error:null},{merge:true});
    const root=await graph.request(ids[0],'GET',{fields:'id,permalink'});await ref.set({permalink:root.permalink},{merge:true});
    console.log(JSON.stringify({key,status:'published',parts:ids.length,permalink:root.permalink}));
  }catch(e){if((await ref.get()).data().status!=='published')await ref.set({status:'publish_uncertain',error:/^[A-Z0-9_]+$/.test(e.message)?e.message:'RESUME_UNCERTAIN'},{merge:true});throw e;}
})().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message)?e.message:'RESUME_FAILED');process.exitCode=1;});
