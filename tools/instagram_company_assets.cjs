const fs=require('node:fs/promises'),sharp=require('../functions/node_modules/sharp'),cheerio=require('../functions/node_modules/cheerio');
const entries={
'005930':{page:'https://www.samsung.com/sec/',hero:'https://images.samsung.com/kdp/aboutsamsung/brand_identity/logo/720_600_1.png?$720_N_PNG$'},
'000660':{page:'https://www.skhynix.com/',hero:'https://mis-prod-koce-skhynixhomepage-cdn-01-ep.azureedge.net/img/common/img_logo.png'},
'005380':{page:'https://www.hyundai.com/worldwide/en',hero:'https://www.hyundai.com/content/dam/hyundai/ww/en/images/main/hyundai-open-graph-image-pc.jpg'},
'000270':{page:'https://worldwide.kia.com/en',hero:'https://worldwide.kia.com/asset/image/og-thumbnail/og-thumbnail.jpg'},
'373220':{page:'https://www.lgensol.com/kr/index',hero:'https://www.lgensol.com/inc/images/symbol/ci_en.svg'},
'068270':{page:'https://www.celltrion.com/en-us',hero:'https://www.celltrion.com/front/assets/common/images/img_header_logo-419fea837abc03d84e05929fca178e6f.png'},
'005490':{page:'https://www.posco-inc.com/hs91a1-front/app/index.html',hero:'https://www.posco-inc.com/hs91a1-front/app/assets/img/og-image.png'},
'035720':{page:'https://www.kakaocorp.com/page/',hero:'https://t1.kakaocdn.net/kakaocorp/kakaocorp/service/og/img_og_main.png'},
'028260':{page:'https://www.samsungcnt.com/index.do',hero:'https://www.samsungcnt.com/assets/img/common/meta.jpg'},
'035420':{page:'https://navercorp.com/company/gallery',logo:'https://1784.navercorp.com/assets/img/naver.svg'}
};
(async()=>{const dir='functions/instagram_assets/companies';await fs.mkdir(dir,{recursive:true});
const t=await(await fetch(entries['035420'].page)).text(),$=cheerio.load(t);const photos=$('img').toArray().map(e=>$(e).attr('src')).filter(u=>u?.includes('corp-homepage-phinf'));
entries['035420'].hero=photos[1];entries['035420'].detail=photos[2];
await Promise.all(Object.entries(entries).map(async([id,e])=>{for(const field of ['hero','logo','detail']){if(!e[field])continue;const r=await fetch(e[field],{signal:AbortSignal.timeout(20000)});if(!r.ok)throw new Error(id+' '+r.status);const data=Buffer.from(await r.arrayBuffer());const file=`${id}-${field}.png`;await sharp(data,{density:200}).resize({width:1200,height:850,fit:'inside',withoutEnlargement:true}).png().toFile(dir+'/'+file);e[field+'File']=file;}console.log('Saved',id);}));
await fs.writeFile(dir+'/manifest.json',JSON.stringify(entries,null,2));
})();
