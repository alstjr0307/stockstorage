const fs=require('node:fs/promises');
const path=require('node:path');
const sharp=require('../functions/node_modules/sharp');
const {createSeries,renderCards}=require('../functions/instagram_content');
(async()=>{
const a=JSON.parse(await fs.readFile(path.resolve(process.argv[2]||'tools/instagram_ai_full_sample.json'),'utf8'));
const out=path.resolve(process.argv[3]||'output/instagram-full-preview');
await fs.mkdir(out,{recursive:true});
const series=await createSeries(a,new Date(a.updatedAt));
await fs.writeFile(path.join(out,'series.json'),JSON.stringify(series,null,2));
for(const [p,draft] of series.entries()) {
const dir=path.join(out,`part-${p+1}`);await fs.mkdir(dir,{recursive:true});
const cards=await renderCards(draft);
await fs.writeFile(path.join(dir,'caption.txt'),draft.caption);
for(const [i,card] of cards.entries()) await fs.writeFile(path.join(dir,`${i+1}.jpg`),card);
const tiles=await Promise.all(cards.map(async(c,i)=>({input:await sharp(c).resize(216,270).toBuffer(),left:(i%5)*216,top:Math.floor(i/5)*270})));
await sharp({create:{width:1080,height:Math.ceil(cards.length/5)*270,channels:3,background:'#e5e5df'}}).composite(tiles).jpeg().toFile(path.join(out,`part-${p+1}-overview.jpg`));
}
console.log(JSON.stringify({parts:series.length,cards:series.map(s=>s.cards.length),out}));
})();
