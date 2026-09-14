'use strict';
// Historical saved analysis, no API keys, uploads or publication.
const path=require('node:path');
const {createEditorialSeries}=require('../functions/instagram_editorial');
const {renderReel}=require('../functions/instagram_reel');
(async()=>{
 const analysis=require('./instagram_chart_sample.json');
 const [draft]=await createEditorialSeries(analysis,new Date(analysis.updatedAt),{editorial:require('./instagram_human_sample.json')});
 const outputDir=path.resolve(process.argv[2]||'output/instagram-auto-reel-preview');
 const {metadata}=await renderReel(draft,analysis,{outputDir});
 console.log(JSON.stringify({outputDir,...metadata}));
})().catch(e=>{console.error(e.message);process.exitCode=1});
