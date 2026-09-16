const {test,before,beforeEach,after}=require('node:test');
const assert=require('node:assert/strict');
if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8787') throw new Error('Local emulator required; never run against production');
const functionRequire=require('node:module').createRequire(require('node:path').resolve(__dirname,'../../functions/package.json'));
const {initializeApp,deleteApp}=functionRequire('firebase-admin/app');
const {getFirestore}=functionRequire('firebase-admin/firestore');
const bots=require('../../functions/community_bots');
let app,db;
before(()=>{app=initializeApp({projectId:'demo-journal'},'bot-runtime-tests');db=getFirestore(app);});
beforeEach(async()=>{
  for(const collection of ['community_bot_config','community_bot_jobs','community_bot_state','users','user_public','posts','trading_journal']) {
    await db.recursiveDelete(db.collection(collection));
  }
});
after(()=>deleteApp(app));
function eventOf(kind) {
  for(let day=1;day<=28;day++) {
    const plan=bots.planDay(`2026-09-${String(day).padStart(2,'0')}`);
    const event=plan.find(e=>e.kind===kind);
    if(event) return {event,now:new Date(event.scheduledAt+1000)};
  }
  throw new Error('No fixture');
}
async function configure(mode) {await db.doc('community_bot_config/main').set({enabled:true,mode,dailyCap:10});}
const generateText=async(_,prompt)=>({title:'연습 기록',content:'공부용으로 기록하는 가정입니다. '+require('node:crypto').createHash('sha256').update(prompt).digest('hex').slice(0,12)});
test('draft mode produces review material without posts or XP',async()=>{
  await configure('draft');const {event,now}=eventOf('post');
  await bots.runCommunityBots({db,now,generateText});
  assert.equal((await db.doc(`community_bot_jobs/${event.id}`).get()).data().status,'draft');
  assert.equal((await db.collection('posts').get()).size,0);
  assert.equal((await db.collection('users').get()).size,0);
});
test('concurrent ticks publish once and award XP once',async()=>{
  await configure('live');const {event,now}=eventOf('post');
  await Promise.all([bots.runCommunityBots({db,now,generateText}),bots.runCommunityBots({db,now,generateText})]);
  const job=(await db.doc(`community_bot_jobs/${event.id}`).get()).data();
  assert.equal(job.status,'published');
  assert.equal((await db.doc(job.path).get()).data().isBot,true);
  const profile=(await db.doc(`users/${event.personaId}`).get()).data();
  assert.equal(profile.postCount,1);assert.equal(profile.xp,3);
  await bots.runCommunityBots({db,now,generateText});
  assert.equal((await db.doc(`users/${event.personaId}`).get()).data().xp,3);
});
test('shared paper journal and portfolio/XP commit together',async()=>{
  await configure('live');const {event,now}=eventOf('journal');
  await bots.runCommunityBots({db,now,generateText});
  const doc=(await db.doc(`trading_journal/${event.id}`).get()).data();
  assert.equal(doc.isPublic,true);assert.equal(doc.isSimulated,true);
  assert.equal((await db.doc(`users/${event.personaId}`).get()).data().xp,8);
  assert.ok((await db.doc(`community_bot_state/${event.personaId}`).get()).data().portfolio.cash<10000000);
});
test('comment replies to disclosed bot posts and earns comment XP',async()=>{
  await configure('live');const {event,now}=eventOf('comment');
  await db.doc('posts/target').set({uid:'another-bot',isBot:true,automation:'community-v1',title:'기록 기준',content:'매수 전에 기준을 적는 가상 캐릭터입니다.',createdAt:now});
  await bots.runCommunityBots({db,now,generateText});
  assert.equal((await db.doc(`posts/target/comments/${event.id}`).get()).data().uid,event.personaId);
  assert.equal((await db.doc(`users/${event.personaId}`).get()).data().commentCount,1);
});
test('pause during generation prevents publishing and XP',async()=>{
  await configure('live');const {event,now}=eventOf('post');
  await bots.runCommunityBots({db,now,generateText:async(...args)=>{
    await db.doc('community_bot_config/main').update({enabled:false});return generateText(...args);
  }});
  assert.equal((await db.doc(`posts/${event.id}`).get()).exists,false);
  assert.equal((await db.doc(`users/${event.personaId}`).get()).exists,false);
});
