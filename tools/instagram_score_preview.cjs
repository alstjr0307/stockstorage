const fs=require('fs'),sharp=require('../functions/node_modules/sharp');
const {render,centeredText,scoreColor}=require('../functions/instagram_visual');
(async()=>{const draft=require('./instagram_latest_draft.json'),card=draft.cards.find(c=>c.layout==='score'),out='output/instagram-score-fix';fs.mkdirSync(out,{recursive:true});
const tiles=[];for(const [i,score] of [0,9,49,50,69,70,72,100,null].entries()){
const [b]=await render({...draft,cards:[{...card,score,subScores:{priceTrend:49,newsImpact:50,fundamentals:69,momentumFlow:70,riskLevel:100}}]});fs.writeFileSync(`${out}/${score===null?'missing':score}.jpg`,b);tiles.push({input:await sharp(b).resize(270,338).toBuffer(),left:i%3*270,top:Math.floor(i/3)*338});
const overlay=await centeredText(score===null?'—':String(score),278,662,230,122,100,scoreColor(score),true);const m=await sharp(overlay.input).metadata();if(Math.abs(overlay.left+m.width/2-278)>.5||Math.abs(overlay.top+m.height/2-662)>.5)throw Error('NOT_CENTERED');}
await sharp({create:{width:810,height:1014,channels:3,background:'#fff'}}).composite(tiles).jpeg().toFile(out+'/ranges.jpg');console.log('9 score cases centered within 0.5px');})().catch(e=>{console.error(e.message);process.exitCode=1});
