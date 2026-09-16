'use strict';
// Uploads test media and creates unpublished containers. Never calls threads_publish.
const {googleRequest,googleToken,PROJECT}=require('./threads_setup.cjs');
const {randomUUID}=require('node:crypto'),fs=require('node:fs/promises'),path=require('node:path');
const {ThreadsGraph}=require('../functions/threads_graph');
async function main(){
  const s=await googleRequest(`https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/THREADS_ACCESS_TOKEN/versions/latest:access`);
  const graph=new ThreadsGraph(Buffer.from(s.payload.data,'base64').toString(),'tf_stockstorage');await graph.identity();
  const bucket=`${PROJECT}.firebasestorage.app`,ids=[];
  for(let i=1;i<=2;i++){
    const name=`threads/connection-check/${randomUUID()}/${i}.jpg`,token=randomUUID();
    const credentials=await googleToken();
    const upload=await fetch(`https://storage.googleapis.com/upload/storage/v1/b/${bucket}/o?uploadType=media&name=${encodeURIComponent(name)}`,{method:'POST',headers:{Authorization:`Bearer ${credentials.access_token}`,'Content-Type':'image/jpeg'},body:await fs.readFile(path.resolve('output/threads-render-final',`${i}.jpg`)),signal:AbortSignal.timeout(60000)});
    if(!upload.ok)throw new Error(`STORAGE_UPLOAD_${upload.status}`);
    await googleRequest(`https://storage.googleapis.com/storage/v1/b/${bucket}/o/${encodeURIComponent(name)}`,'PATCH',{metadata:{firebaseStorageDownloadTokens:token}});
    const url=`https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(name)}?alt=media&token=${token}`;
    ids.push(await graph.container({media_type:'IMAGE',image_url:url,is_carousel_item:'true',alt_text:'주식저장소 비공개 연결 검증용 이미지'}));
  }
  const id=await graph.container({media_type:'CAROUSEL',children:ids.join(','),text:'연결 검증용 미게시 초안'});
  console.log(JSON.stringify({account:graph.account,images:2,containerId:id,status:'FINISHED',published:false}));
}
main().catch(e=>{console.error(/^[A-Z0-9_]+$/.test(e.message)?e.message:`CONTAINER_CHECK_FAILED_${e.code||e.name}`);process.exitCode=1;});
