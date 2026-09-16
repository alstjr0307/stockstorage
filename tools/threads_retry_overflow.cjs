'use strict';
// Requeue only known pre-publication image failures after deploying the renderer fix.
const admin=require('../functions/node_modules/firebase-admin');
const {googleRequest}=require('./threads_setup.cjs');
admin.initializeApp({credential:admin.credential.cert(require('../functions/serviceAccountKey.json')),projectId:'stockstorage-13828'});
(async()=>{
  const db=admin.firestore();
  for(const key of process.argv.slice(2)){
    if(!/^\d{4}-\d{2}-\d{2}_KS_\d{6}$/.test(key))throw Error('INVALID_JOB');
    const ref=db.doc('_admin/threadsAutomation/jobs/'+key);
    await db.runTransaction(async tx=>{
      const d=(await tx.get(ref)).data();
      if(d?.status!=='failed'||d.error!=='CARD_TEXT_OVERFLOW'||d.mediaId||d.mediaIds?.length||d.containerId)throw Error('NOT_A_PREPUBLISH_OVERFLOW');
      tx.set(ref,{attempts:0,previousAttempts:d.attempts||0,recoveryReason:'score_label_overflow_fixed',recoveryRequestedAt:new Date(),leaseUntil:new Date(0)},{merge:true});
    });
    console.log(JSON.stringify({key,requeued:true}));
  }
  await googleRequest('https://cloudscheduler.googleapis.com/v1/projects/stockstorage-13828/locations/asia-northeast3/jobs/firebase-schedule-generateDailyThreadsAnalysis-asia-northeast3:run','POST',{});
  console.log('THREADS_RECOVERY_RUN_REQUESTED');
})().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message)?e.message:e.code||'RECOVERY_FAILED');process.exitCode=1;});
