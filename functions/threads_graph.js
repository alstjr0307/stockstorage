'use strict';
const BLOCKED = new Set(['publishing','publish_uncertain','published']);
class ThreadsGraph {
  constructor(token,account,{transport=fetch,pause=ms=>new Promise(r=>setTimeout(r,ms))}={}) {
    if(!token||!account)throw new Error('THREADS_CONFIG_REQUIRED');
    Object.assign(this,{token,account,transport,pause});
  }
  async request(path,method='GET',params={}) {
    const url=new URL(`https://graph.threads.net/v1.0/${path}`);
    const options={method,headers:{Authorization:`Bearer ${this.token}`},signal:AbortSignal.timeout(60000)};
    if(method==='GET')Object.entries(params).forEach(([k,v])=>url.searchParams.set(k,String(v)));
    else options.body=new URLSearchParams(params);
    let response,data;
    try{response=await this.transport(url,options);data=await response.json();}catch{throw new Error('THREADS_NETWORK_OR_RESPONSE_ERROR');}
    if(!response.ok||data.error)throw new Error(`THREADS_API_${Number(data.error?.code||response.status)}`);
    return data;
  }
  async identity() {
    const me=await this.request('me','GET',{fields:'id,username'});
    if(me.username!==this.account||!/^\d+$/.test(String(me.id||'')))throw new Error('THREADS_ACCOUNT_MISMATCH');
    this.userId=String(me.id);return me;
  }
  async ready(id) {
    for(let i=0;i<24;i++){
      const s=await this.request(id,'GET',{fields:'id,status'});
      if(s.status==='FINISHED')return;
      if(['ERROR','EXPIRED','PUBLISHED'].includes(s.status))throw new Error(`THREADS_CONTAINER_${s.status}`);
      await this.pause(5000);
    }
    throw new Error('THREADS_CONTAINER_TIMEOUT');
  }
  async container(params) {
    const r=await this.request(`${this.userId}/threads`,'POST',params);
    if(!/^\d+$/.test(String(r.id||'')))throw new Error('THREADS_CONTAINER_ID_MISSING');
    await this.ready(r.id);return r.id;
  }
  async publishContainer(id) {
    for(let attempt=0;attempt<3;attempt++) {
      try{return await this.request(`${this.userId}/threads_publish`,'POST',{creation_id:id});}
      catch(error){
        if(error.message!=='THREADS_API_24'||attempt===2)throw error;
        await this.pause(10000);
        const state=await this.request(id,'GET',{fields:'id,status'});
        // Only retry the same container when Meta confirms it is unpublished.
        // Network ambiguity or PUBLISHED status must never replay a publication.
        if(state.status!=='FINISHED')throw error;
      }
    }
  }
  async publish(draft,urls,save,prior={}) {
    if(BLOCKED.has(prior.status))throw new Error('THREADS_REPLAY_BLOCKED');
    if(urls.length!==2||urls.some(v=>{try{const u=new URL(v);return u.protocol!=='https:'||u.hostname!=='firebasestorage.googleapis.com';}catch{return true;}}))throw new Error('THREADS_TWO_PUBLIC_IMAGES_REQUIRED');
    if(!draft.posts?.length||draft.posts.some(p=>!p.text||p.text.length>480))throw new Error('THREADS_POST_INVALID');
    await this.identity();
    const children=[];
    for(let i=0;i<urls.length;i++)children.push(await this.container({media_type:'IMAGE',image_url:urls[i],is_carousel_item:'true',alt_text:draft.images?.[i]?.alt||draft.imageAlt}));
    const ids=[];
    for(let i=0;i<draft.posts.length;i++){
      const params=i===0?{media_type:'CAROUSEL',children:children.join(','),text:draft.posts[i].text}:{media_type:'TEXT',text:draft.posts[i].text,reply_to_id:ids.at(-1)};
      const id=await this.container(params);
      // Persist before each irreversible request; remain blocked across all replies.
      await save({status:'publishing',activePart:i,containerId:id,mediaIds:[...ids],publishStartedAt:new Date()});
      const r=await this.publishContainer(id);
      if(!/^\d+$/.test(String(r.id||'')))throw new Error('THREADS_PUBLISHED_ID_MISSING');
      ids.push(String(r.id));await save({status:'publishing',mediaIds:[...ids],completedParts:ids.length});
    }
    await save({status:'published',mediaIds:ids,mediaId:ids[0],publishedAt:new Date()});
    try{const p=await this.request(ids[0],'GET',{fields:'permalink'});if(p.permalink)await save({permalink:p.permalink});}catch{/* Never replay a confirmed post for a missing link. */}
    return ids;
  }
}
module.exports={ThreadsGraph,BLOCKED};
