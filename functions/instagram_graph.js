'use strict';

const ACCOUNT = 'tf_stockstorage';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

class InstagramGraph {
  constructor(token, version = 'v23.0', transport = fetch) {
    if (!token || !/^v\d+\.\d+$/.test(version)) throw new Error('INSTAGRAM_CONFIG_MISSING');
    this.token = token;
    this.base = `https://graph.instagram.com/${version}`;
    this.transport = transport;
  }
  async request(path, method = 'GET', params = {}) {
    const url = new URL(`${this.base}/${path}`);
    const options = {method, headers:{Authorization:`Bearer ${this.token}`}, signal:AbortSignal.timeout(60000)};
    if(method === 'GET') Object.entries(params).forEach(([k,v]) => url.searchParams.set(k,String(v)));
    else options.body = new URLSearchParams(params);
    let response;
    try { response = await this.transport(url, options); }
    catch (_) { throw new Error('INSTAGRAM_NETWORK_ERROR'); }
    let data;
    try { data = await response.json(); } catch (_) { throw new Error('INSTAGRAM_INVALID_RESPONSE'); }
    // Do not log request objects, tokens, or provider messages containing secrets.
    if(!response.ok || data.error) throw new Error(`INSTAGRAM_API_${data.error?.code || response.status}`);
    return data;
  }
  async identity() {
    const me = await this.request('me','GET',{fields:'user_id,username'});
    if(me.username !== ACCOUNT || !/^\d+$/.test(String(me.user_id || me.id || ''))) throw new Error('INSTAGRAM_ACCOUNT_MISMATCH');
    this.userId = String(me.user_id || me.id);
    return me;
  }
  async ready(id, attempts=24) {
    for(let i=0;i<attempts;i++) {
      const state = await this.request(id,'GET',{fields:'status_code'});
      if(state.status_code === 'FINISHED') return;
      if(['ERROR','EXPIRED','PUBLISHED'].includes(state.status_code)) throw new Error(`INSTAGRAM_CONTAINER_${state.status_code}`);
      await pause(5000);
    }
    throw new Error('INSTAGRAM_CONTAINER_TIMEOUT');
  }
  async reel(videoUrl, caption, save) {
    if(!this.userId) await this.identity();
    const url=new URL(videoUrl);
    if(url.protocol!=='https:'||url.hostname!=='firebasestorage.googleapis.com')throw Error('INVALID_VIDEO_HOST');
    const container=await this.request(`${this.userId}/media`,'POST',{
      media_type:'REELS',video_url:videoUrl,caption,share_to_feed:'true',thumb_offset:'1000',
    });
    if(!container.id)throw Error('MISSING_CONTAINER_ID');
    await save({containerId:container.id,mediaType:'REELS',status:'processing'});
    await this.ready(container.id,120);
    await save({status:'publishing',publishStartedAt:new Date()});
    const media=await this.request(`${this.userId}/media_publish`,'POST',{creation_id:container.id});
    if(!media.id)throw Error('MISSING_PUBLISHED_MEDIA_ID');
    await save({status:'published',mediaId:media.id,mediaIds:[media.id],publishedAt:new Date()});
    try {
      const result=await this.request(media.id,'GET',{fields:'permalink,media_product_type'});
      if(result.permalink)await save({permalink:result.permalink});
    } catch (_) { /* Confirmed publication must not replay for metadata failure. */ }
    return media.id;
  }
  async carousel(urls, caption, save) {
    if(!this.userId) await this.identity();
    if(urls.length < 2 || urls.length > 10) throw new Error('INVALID_CAROUSEL_SIZE');
    const children = [];
    for(const image_url of urls) {
      if(!image_url.startsWith('https://firebasestorage.googleapis.com/')) throw new Error('INVALID_IMAGE_HOST');
      const child = await this.request(`${this.userId}/media`,'POST',{image_url,is_carousel_item:'true'});
      if(!child.id) throw new Error('MISSING_CONTAINER_ID');
      children.push(child.id);
      await save({childContainerIds:[...children]});
      await this.ready(child.id);
    }
    const parent = await this.request(`${this.userId}/media`,'POST',{media_type:'CAROUSEL',children:children.join(','),caption});
    if(!parent.id) throw new Error('MISSING_CONTAINER_ID');
    await save({containerId:parent.id});
    await this.ready(parent.id);
    // Persist before the irreversible publish POST. An ambiguous response MUST
    // remain blocked from automatic replay even after the worker lease expires.
    await save({status:'publishing',publishStartedAt:new Date()});
    const media = await this.request(`${this.userId}/media_publish`,'POST',{creation_id:parent.id});
    if(!media.id) throw new Error('MISSING_PUBLISHED_MEDIA_ID');
    await save({status:'published',mediaId:media.id,publishedAt:new Date()});
    try {
      const result = await this.request(media.id,'GET',{fields:'permalink'});
      if(result.permalink) await save({permalink:result.permalink});
    } catch (_) { /* Publishing already succeeded. Never replay for a link failure. */ }
    return media.id;
  }
}

// Keep the stock job non-replayable throughout a multi-post series. If a later
// part fails, never republish earlier confirmed parts on an automatic retry.
async function publishSeries(graph, posts, save) {
  const parts = posts.map((_,i)=>({part:i+1,status:'pending'}));
  await save({status:'publishing',parts});
  const mediaIds=[];
  for(let i=0;i<posts.length;i++) {
    const id=await graph.carousel(posts[i].urls,posts[i].caption,async fields=>{
      parts[i]={...parts[i],...fields};
      await save({status:'publishing',parts:parts.map(p=>({...p}))});
    });
    mediaIds.push(id);
  }
  await save({status:'published',parts,mediaIds,mediaId:mediaIds.at(-1),publishedAt:new Date()});
  return mediaIds;
}

module.exports = {InstagramGraph,publishSeries};
