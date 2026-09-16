'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {createThreadsDraft, splitPosts} = require('./threads_content');
const {editThreadsAnalysis, validateThreadsEditorial} = require('./threads_editorial');
const analysis = require('../tools/instagram_ai_full_sample.json');
const editorial = require('../tools/threads_balanced_sample.json');
test('compact input preserves decimal numbers and drops duplicate detail sections',()=>{
  const {compactSources}=require('./threads_editorial');
  const input=compactSources({summary:'PER은 45.28배야. 수익률은 -2.89%야.',risks:['변동성이 커.']});
  assert.equal(input.find(s=>s.id==='summary').body,'PER은 45.28배야. 수익률은 -2.89%야.');
  assert.ok(JSON.stringify(compactSources(analysis)).length<JSON.stringify(require('./instagram_sections').analysisSections(analysis)).length);
});

test('draft has the requested opening and ends with analysis without promotion or links', async () => {
  const draft = await createThreadsDraft(analysis, {editorial});
  assert.ok(draft.body.startsWith(`오늘의 AI종목분석은 ${analysis.name}이야\n\n`));
  assert.doesNotMatch(draft.body, /https?:\/\/|더 많은 종목 분석이 궁금하다면|앱에서 확인|설치할 수/);
  assert.ok(draft.body.endsWith(editorial.paragraphs.at(-1).text.split('. ').at(-1)));
  assert.equal(draft.imageCount, 2);
  assert.ok(draft.posts.length>=4&&draft.posts.length<=5);
  assert.ok(draft.characterCount>1100&&draft.characterCount<1800);
  assert.equal(draft.posts.filter(p => p.mediaType === 'CAROUSEL').length, 1);
  assert.equal(draft.posts[0].mediaType, 'CAROUSEL');
  assert.ok(draft.posts.slice(1).every(p => p.replyToPrevious && p.mediaType === 'TEXT'));
  assert.ok(draft.posts.every(p => p.text.length <= 480));
  assert.equal(draft.posts.map(p => p.text).join('\n\n'), draft.body);
});

test('editorial rejects fabricated numbers, missing risks, and formal copy', () => {
  const copy = () => structuredClone(editorial);
  const number = copy(); number.paragraphs[0].text += ' 수익률은 999.9%야.';
  assert.throws(() => validateThreadsEditorial(number, analysis), /UNSUPPORTED_NUMBER/);
  const risk = copy(); risk.paragraphs.forEach(p => {p.sourceIds = p.sourceIds.filter(id => id !== 'risks');});
  assert.throws(() => validateThreadsEditorial(risk, analysis), /MISSING_risks/);
  const formal = copy(); formal.paragraphs[0].text += ' 확인하세요.';
  assert.throws(() => validateThreadsEditorial(formal, analysis), /THREADS_STYLE/);
  assert.throws(() => splitPosts(['가'.repeat(481)]), /POST_TOO_LONG/);
});

test('AI editor retries invalid prose and accepts validated structured response', async () => {
  let calls = 0;
  const output = await editThreadsAnalysis(analysis, {apiKey:'test', transport:async (_url, options) => {
    const request = JSON.parse(options.body);
    assert.match(request.instructions, /반말/);
    assert.equal(request.model,'gpt-5.4');
    assert.equal(request.reasoning.effort,'medium');
    assert.equal(request.max_output_tokens,7000);
    assert.ok(JSON.parse(request.input).sources.length<=10);
    calls++;
    return {ok:true, json:async () => ({output:[{content:[{type:'output_text',text:JSON.stringify(calls === 1 ? {paragraphs:[]} : editorial)}]}]})};
  }});
  assert.equal(calls, 2);
  assert.deepEqual(output, editorial);
});

test('missing credentials and invalid analysis fail without raw-prose fallback', async () => {
  await assert.rejects(createThreadsDraft({}), /ANALYSIS_REQUIRED/);
  await assert.rejects(createThreadsDraft({...analysis, updatedAt:'invalid'}, {editorial}), /DATE_REQUIRED/);
  await assert.rejects(editThreadsAnalysis(analysis, {apiKey:''}), /KEY_MISSING/);
});

test('rejects a polite or report-style sentence in the middle of an informal paragraph',()=>{
  for(const sentence of ['실적은 좋아요.','실적은 좋습니다.','실적은 긍정 요인이다.','계속 확인하세요!']){
    const copy=structuredClone(editorial);
    copy.paragraphs[0].text=`${sentence} 그래도 다음 실적은 같이 봐야 해.`;
    assert.throws(()=>validateThreadsEditorial(copy,analysis),/THREADS_STYLE/);
  }
});

test('rejects shallow copy even when all source labels and questions remain', () => {
  const short = structuredClone(editorial);
  short.paragraphs.forEach((p, i) => { p.text = i < 1 ? '왜일까? 원문을 같이 보면 돼.' : '그 의미도 같이 봐야 해.'; });
  assert.throws(() => validateThreadsEditorial(short, analysis), /THREADS_DEPTH_REQUIRED/);
});

test('rejects invisible padding used to fake a longer explanation', () => {
  const padded = structuredClone(editorial);
  padded.paragraphs[0].text += '\u200b';
  assert.throws(() => validateThreadsEditorial(padded, analysis), /ARTIFICIAL_PADDING/);
});
