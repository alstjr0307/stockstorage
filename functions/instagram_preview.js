// Local smoke run through the same scheduler callback, with publishing disabled.
'use strict';
const path=require('node:path');
const {SecretManagerServiceClient}=require('@google-cloud/secret-manager');
async function main() {
  if(process.env.K_SERVICE) throw new Error('LOCAL_ONLY');
  const credentials=process.env.GOOGLE_APPLICATION_CREDENTIALS||path.join(__dirname,'serviceAccountKey.json');
  const projectId=require(credentials).project_id;
  process.env.GOOGLE_APPLICATION_CREDENTIALS=credentials;
  process.env.GCLOUD_PROJECT=projectId;
  process.env.FIREBASE_CONFIG=JSON.stringify({projectId,storageBucket:`${projectId}.firebasestorage.app`});
  process.env.INSTAGRAM_LOCAL_PREVIEW='1';
  if(process.argv.includes('--publish')) process.env.INSTAGRAM_LOCAL_PUBLISH='1';
  process.env.INSTAGRAM_PREVIEW_DIR=path.resolve(process.argv.filter(a=>!a.startsWith('--'))[2]||path.join(__dirname,'../output/instagram-ai-live-preview'));
  const client=new SecretManagerServiceClient({keyFilename:credentials});
  for(const name of ['OPENAI_API_KEY','DART_API_KEY']) {
    if(process.env[name]) continue;
    const [secret]=await client.accessSecretVersion({name:`projects/${projectId}/secrets/${name}/versions/latest`});
    process.env[name]=secret.payload.data.toString();
  }
  const result=await require('./index').generateDailyInstagramAnalysis.run({});
  console.log(JSON.stringify(result));
  console.log('Preview directory: '+process.env.INSTAGRAM_PREVIEW_DIR);
}
main().catch(error=>{console.error('Preview failed:',error.code||error.message);process.exitCode=1;});
