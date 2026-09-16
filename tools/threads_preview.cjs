'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const {createThreadsDraft} = require('../functions/threads_content');

async function main() {
  const [input, destination, editorialPath] = process.argv.slice(2);
  if (!input || !destination) throw new Error('Usage: node tools/threads_preview.cjs analysis.json output-directory');
  const analysis = JSON.parse(await fs.readFile(path.resolve(input), 'utf8'));
  const editorial = editorialPath ? JSON.parse(await fs.readFile(path.resolve(editorialPath), 'utf8')) : undefined;
  const draft = await createThreadsDraft(analysis, {editorial});
  const output = path.resolve(destination);
  await fs.mkdir(output, {recursive: true});
  const images = await require('../functions/threads_visual').renderThreadsImages(analysis, draft);
  for (let i=0;i<images.length;i++) await fs.writeFile(path.join(output, `${i+1}.jpg`), images[i]);
  await fs.writeFile(path.join(output, 'caption.txt'), draft.body + '\n');
  await fs.writeFile(path.join(output, 'posts.json'), JSON.stringify(draft.posts, null, 2) + '\n');
  await fs.writeFile(path.join(output, 'draft.json'), JSON.stringify(draft, null, 2) + '\n');
  await fs.writeFile(path.join(output, 'README.txt'),
    `쓰레드 초안: 이미지 두 장 + 장문 설명\n분석 원본: ${path.resolve(input)}\n기준: ${draft.asOf}\n본문: ${draft.characterCount}자\n${draft.publishingNote}\n사진은 실제 기업 시설 사진이 아닌 사업 분야 콘셉트 이미지입니다.\n`);
  console.log(JSON.stringify({output, name: draft.name, imageCount: images.length, characters: draft.characterCount}));
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
