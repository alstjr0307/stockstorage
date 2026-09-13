// 비공개 캐릭터 테스트용 작문 샘플. 실제 회원/투자 경험을 나타내지 않는다.
const rows = require('./community_stock_samples.cjs');
const {nicknames, samples} = require('./community_social_samples.cjs');

const windows = [[7,9],[12,14],[18,21],[21,24],[8,11]];
const stances = ['관찰부터 하고 의견을 덧붙인다','단정하기 전에 질문한다','실용적인 작은 방법을 찾는다','다른 선택도 인정한다','과장 대신 구체적인 예를 든다'];
module.exports = rows.map(([nickname, interest, voice, title, content, focus], i) => ({
  id: `lab_persona_${String(i + 1).padStart(2, '0')}`,
  nickname: nicknames[i], interest, voice, focus, stance: stances[i % stances.length],
  socialProbability: [0.15,0.25,0.35,0.2,0.4][i % 5],
  activeHoursKst: windows[i % windows.length],
  dailyProbability: [0.15,0.25,0.4,0.55,0.7][Math.floor(i / 5) % 5],
  weekendMultiplier: [0.65,1.25,0.9][i % 3],
  minGapHours: 20 + i % 5,
  memory: { interests: [interest], establishedFacts: [], recentPosts: [] },
  stockSample: {title, content, kind: '주식 이야기'},
  socialSample: {kind: samples[i % samples.length][0], title: samples[i % samples.length][1], content: samples[i % samples.length][2]},
  // 미리보기 50개: 주식 글 30, 주식 잡담 10, 일상 잡담 10 (테스트용 구성).
  sample: i % 5 < 2
    ? {kind: samples[Math.floor(i/5)*2+i%5][0], title: samples[Math.floor(i/5)*2+i%5][1], content: samples[Math.floor(i/5)*2+i%5][2]}
    : {title, content, kind: '주식 이야기'},
  isSynthetic: true,
}));
