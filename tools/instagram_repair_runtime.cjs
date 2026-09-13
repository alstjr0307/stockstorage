const auth=require('C:/Users/alswp/AppData/Roaming/npm/node_modules/firebase-tools/lib/auth');
(async()=>{
const account=auth.getGlobalDefaultAccount();const token=await auth.getAccessToken(account.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform']);
const api=async(url,method='GET',body)=>{const r=await fetch(url,{method,headers:{Authorization:`Bearer ${token.access_token}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();if(!r.ok)throw Error(`GOOGLE_API_${r.status}_${d.error?.status||''}`);return d;};
const project='stockstorage-13828';const f=await api(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/asia-northeast3/functions/generateDailyInstagramAnalysis`);
const member=`serviceAccount:${f.serviceConfig.serviceAccountEmail}`;
const resource=`https://secretmanager.googleapis.com/v1/projects/${project}/secrets/INSTAGRAM_ACCESS_TOKEN`;
const policy=await api(resource+':getIamPolicy');policy.bindings ||= [];
for(const role of ['roles/secretmanager.secretAccessor','roles/secretmanager.secretVersionAdder']){let b=policy.bindings.find(b=>b.role===role&&!b.condition);if(!b){b={role,members:[]};policy.bindings.push(b);}if(!b.members.includes(member))b.members.push(member);}
await api(resource+':setIamPolicy','POST',{policy});
const verified=await api(resource+':getIamPolicy');
console.log(JSON.stringify({runtime:f.serviceConfig.serviceAccountEmail,secretPermissions:verified.bindings.filter(b=>b.members.includes(member)).map(b=>b.role)}));
const jobs=await api(`https://cloudscheduler.googleapis.com/v1/projects/${project}/locations/asia-northeast3/jobs`);
const job=jobs.jobs.find(j=>j.name.includes('generateDailyInstagramAnalysis'));if(!job)throw Error('SCHEDULER_NOT_FOUND');
console.log(JSON.stringify({scheduler:job.name,schedule:job.schedule,timeZone:job.timeZone,state:job.state,lastAttemptTime:job.lastAttemptTime}));
if(process.argv.includes('--run')){await api('https://cloudscheduler.googleapis.com/v1/'+job.name+':run','POST',{});console.log('SCHEDULER_RUN_REQUESTED');}
})().catch(e=>{console.error(e.message);process.exitCode=1});
