const fs=require('node:fs/promises');
const sharp=require('../functions/node_modules/sharp');
const {editAnalysis,createEditorialSeries}=require('../functions/instagram_editorial');
const {renderCards}=require('../functions/instagram_content');
(async()=>{
const a=require('./instagram_ai_full_sample.json');const out='output/instagram-visual-editorial';await fs.mkdir(out,{recursive:true});
let e;if(process.argv.includes('--saved'))e=JSON.parse(await fs.readFile('tools/instagram_editorial_sample.json','utf8'));else {try{e=await editAnalysis(a);}catch(error){if(error.editorialResult)await fs.writeFile(out+'/rejected.json',JSON.stringify(error.editorialResult,null,2));throw error;}await fs.writeFile(out+'/editorial.json',JSON.stringify(e,null,2));}
const series=await createEditorialSeries(a,new Date(a.updatedAt),{editorial:e});await fs.writeFile(out+'/series.json',JSON.stringify(series,null,2));
const cards=await renderCards(series[0]);for(const [i,c] of cards.entries())await fs.writeFile(`${out}/${i+1}.jpg`,c);
await sharp({create:{width:1620,height:810,channels:3,background:'#eee'}}).composite(await Promise.all(cards.map(async(c,i)=>({input:await sharp(c).resize(324,405).toBuffer(),left:i%5*324,top:Math.floor(i/5)*405})))).jpeg().toFile(out+'/overview.jpg');console.log('Rendered 10 editorial cards');
})();
