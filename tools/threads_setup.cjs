'use strict';
// Local-only credential bridge. Never logs, persists locally, or echoes tokens.
const path=require('node:path'),http=require('node:http'),{randomUUID}=require('node:crypto');
const PROJECT='stockstorage-13828';
async function googleToken() {
  const root=path.dirname(require.resolve('firebase-tools',{paths:[path.join(process.env.APPDATA,'npm/node_modules')]}));
  const auth=require(path.join(root,'auth'));
  const account=auth.getGlobalDefaultAccount();
  if(!account?.tokens?.refresh_token)throw new Error('FIREBASE_LOGIN_REQUIRED');
  return auth.getAccessToken(account.tokens.refresh_token,['https://www.googleapis.com/auth/cloud-platform']);
}
async function googleRequest(url,method='GET',body) {
  const token=await googleToken();
  const response=await fetch(url,{method,headers:{Authorization:`Bearer ${token.access_token}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(60000)});
  const data=await response.json();
  if(!response.ok)throw new Error(`GOOGLE_HTTP_${response.status}`);
  return data;
}
async function saveToken(token) {
  const response=await fetch('https://graph.threads.net/v1.0/me?fields=id,username',{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(30000)});
  const me=await response.json();
  if(!response.ok||me.username!=='tf_stockstorage')throw new Error('THREADS_ACCOUNT_MISMATCH');
  const base=`https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets`;
  try{await googleRequest(`${base}/THREADS_ACCESS_TOKEN`);}catch(e){if(e.message!=='GOOGLE_HTTP_404')throw e;await googleRequest(`${base}?secretId=THREADS_ACCESS_TOKEN`,'POST',{replication:{automatic:{}}});}
  await googleRequest(`${base}/THREADS_ACCESS_TOKEN:addVersion`,'POST',{payload:{data:Buffer.from(token).toString('base64')}});
  await googleRequest(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/_admin/threadsAutomation?updateMask.fieldPaths=account&updateMask.fieldPaths=enabled&updateMask.fieldPaths=tokenRefreshedAt&updateMask.fieldPaths=userId`,'PATCH',{fields:{account:{stringValue:me.username},enabled:{booleanValue:false},userId:{stringValue:String(me.id)},tokenRefreshedAt:{timestampValue:new Date().toISOString()}}});
  return me.username;
}
if(require.main===module) {
  const nonce=randomUUID(),port=18739;
  const server=http.createServer(async(req,res)=>{
    res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','text/html; charset=utf-8');
    res.setHeader('Content-Security-Policy',"default-src 'none'; form-action 'self'; frame-ancestors 'none'");
    if(req.url!==`/${nonce}`){res.writeHead(404);res.end();return;}
    if(req.method==='GET'){res.end('<h1>주식저장소 Threads 연결</h1><p>토큰은 Google Secret Manager에만 저장돼.</p><form method="post"><label>Threads 토큰 <input name="token" type="password" autocomplete="off" required></label><button>안전하게 연결 저장</button></form>');return;}
    if(req.method!=='POST'||req.headers.origin!==`http://127.0.0.1:${port}`){res.writeHead(403);res.end();return;}
    let body='';for await(const chunk of req){body+=chunk;if(body.length>20000){res.writeHead(413);res.end();return;}}
    try{const token=new URLSearchParams(body).get('token')?.trim();if(!token)throw new Error('TOKEN_REQUIRED');const account=await saveToken(token);body='';res.end(`<h1>연결 저장 완료</h1><p>${account} 토큰을 Secret Manager에 저장했어. 게시 활성화는 배포 검증 후 진행해.</p>`);console.log('THREADS_ACCOUNT_CONNECTED');setTimeout(()=>server.close(),1000);}
    catch(error){body='';res.writeHead(400);res.end(`<h1>연결 실패</h1><p>${/^[A-Z0-9_]+$/.test(error.message)?error.message:'SETUP_FAILED'}</p>`);}
  });
  server.listen(port,'127.0.0.1',()=>console.log(`http://127.0.0.1:${port}/${nonce}`));
  setTimeout(()=>server.close(),15*60000).unref();
}
module.exports={googleRequest,googleToken,saveToken,PROJECT};
