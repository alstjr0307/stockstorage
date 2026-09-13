const fs = require('node:fs');
const path = require('node:path');
const personas = require('./community_lab_personas.cjs');
const root = path.resolve(__dirname, '..');
const service = fs.readFileSync(path.join(root, 'lib/services/firestore_service.dart'), 'utf8');
const thresholds = service.match(/_levelThresholds = \[([\s\S]*?)\];/)[1]
  .replace(/\/\/[^\n]*/g, '').split(',').map(s => s.trim()).filter(Boolean).map(Number);
const postXp = Number(service.match(/_postScore = (\d+)/)[1]);
const extraStep = Number(service.match(/_afterTableStep = (\d+)/)[1]);
function levelFor(xp) {
  let level = 1;
  thresholds.forEach((threshold, index) => { if (xp >= threshold) level = index + 1; });
  return level + (xp >= thresholds.at(-1) ? Math.floor((xp - thresholds.at(-1)) / extraStep) : 0);
}
function rng(seed) {
  let n = seed >>> 0;
  return () => { n += 0x6D2B79F5; let t = n; t = Math.imul(t ^ t >>> 15, t | 1); t ^= t + Math.imul(t ^ t >>> 7, t | 61); return ((t ^ t >>> 14) >>> 0) / 4294967296; };
}
const angles = ['아직 해결하지 못한 질문','작은 습관에 대한 생각','두 방법의 장단점 비교','처음 배우며 헷갈린 점','관찰한 차이 설명','다른 의견을 구하는 글','기준을 바꾸어 생각하기','이전 질문에서 남은 의문'];
function draftPrompt(persona, event, memory) {
  return [
    '비공개 합성 캐릭터 테스트용 게시글 초안을 JSON {title, content}로 작성한다.',
    `캐릭터: ${persona.nickname}. 관심사: ${persona.interest}. 주로 보는 관점: ${persona.focus}. 말투: ${persona.voice}. 태도: ${persona.stance}.`,
    `이번 글의 목적: ${event.angle}. 이전 주제와 표현을 반복하지 않는다.`,
    `글 분류: ${event.kind}. 문체 참고(복사하지 말 것): ${event.kind === '주식 이야기' ? persona.stockSample.content : persona.socialSample.content}`,
    `이전 글의 계획: ${JSON.stringify(memory)}`,
    '실제 투자·수익·직장·가족 경험, 실시간 뉴스나 수치를 지어내지 않는다. 특정 종목 매수 유도나 다른 캐릭터와 여론을 조성하지 않는다.',
    '주식 관심사는 캐릭터 배경이지 닉네임이나 모든 글의 의무 주제가 아니다. 주식 이야기에서는 해당 관심사와 관점을 사용하고, 잡담에서는 평범한 질문·짧은 반응·일상 소재를 허용한다. 일상 글을 억지로 투자 교훈으로 끝내지 않는다.',
    '소리 내어 읽었을 때 자연스러운 1~5문장으로 쓴다. 말투 지침보다 내용의 타당성을 우선한다.',
  ].join('\n');
}
function simulate({ seed = 42, days = 7, start = '2026-09-11', dailyCap = 12 } = {}) {
  if (!Number.isInteger(seed) || seed < 0 || seed > 0xFFFFFFFF) throw new Error('seed must be uint32');
  if (!Number.isInteger(days) || days < 1 || days > 30) throw new Error('days must be 1..30');
  if (!Number.isInteger(dailyCap) || dailyCap < 1 || dailyCap > 50) throw new Error('dailyCap must be 1..50');
  const epoch = Date.parse(`${start}T00:00:00+09:00`);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !Number.isFinite(epoch) || new Date(epoch + 9*3600000).toISOString().slice(0,10) !== start) throw new Error('invalid start date');
  const random = rng(seed);
  const states = new Map(personas.map(p => [p.id, {xp: 0, level: 1, count: 0, last: -Infinity, recent: []}]));
  const events = [];
  for (let day = 0; day < days; day++) {
    const date = epoch + day * 86400000;
    const weekday = new Date(date + 9*3600000).getUTCDay();
    const candidates = [];
    for (const p of personas) {
      const multiplier = weekday === 0 || weekday === 6 ? p.weekendMultiplier : 1;
      if (random() >= Math.min(0.95, p.dailyProbability * multiplier)) continue;
      const minute = Math.floor((p.activeHoursKst[0] + random() * (p.activeHoursKst[1] - p.activeHoursKst[0])) * 60);
      const at = date + minute * 60000 + Math.floor(random() * 60) * 1000;
      if (at - states.get(p.id).last < p.minGapHours * 3600000) continue;
      candidates.push({ p, at, priority: random() });
    }
    candidates.sort((a,b) => a.priority - b.priority);
    const dayBudget = Math.max(1, Math.floor(dailyCap * (0.45 + random() * 0.55)));
    const selected = candidates.slice(0, dayBudget).sort((a,b) => a.at - b.at);
    for (const {p, at} of selected) {
      const state = states.get(p.id);
      const angle = angles[state.count % angles.length];
      const kind = random() < Math.min(0.75, p.socialProbability * (weekday === 0 || weekday === 6 ? 1.5 : 1))
        ? p.socialSample.kind : '주식 이야기';
      const event = {id: `sim_${seed}_${day}_${p.id}`, personaId: p.id, nickname: p.nickname,
        at: new Date(at).toISOString(), kst: new Date(at + 9*3600000).toISOString().slice(0,19).replace('T',' '),
        angle, kind, xpBefore: state.xp, xpAfter: state.xp + postXp,
        levelBefore: state.level, levelAfter: levelFor(state.xp + postXp),
        status: 'simulated_only', isSynthetic: true};
      event.draftPrompt = draftPrompt(p, event, state.recent);
      state.count++; state.xp = event.xpAfter; state.level = event.levelAfter; state.last = at;
      state.recent = [...state.recent, {angle, kind, at: event.at}].slice(-5);
      events.push(event);
    }
  }
  return { mode: 'private_simulation', seed, days, start, dailyCap, postXp,
    personas: personas.map(p => ({...p, simulation: {postCount: states.get(p.id).count, xp: states.get(p.id).xp, level: states.get(p.id).level}})),
    events, totals: {personas: personas.length, plannedPosts: events.length,
      activePersonas: new Set(events.map(e => e.personaId)).size,
      firestoreWrites: 0, apiCalls: 0},
  };
}
function render(data) {
  const payload = JSON.stringify(data).replace(/</g, '\\u003c');
  return `<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>자유게시판 캐릭터 실험실</title>
<style>*{box-sizing:border-box}body{margin:0;background:#0e1420;color:#e9edf5;font:15px/1.7 system-ui,sans-serif}main{max-width:1160px;margin:auto;padding:36px 24px}h1{font-size:32px;margin:8px 0}h2{font-size:21px}p{margin:8px 0}.muted{color:#a9b6ca}.label{color:#6ce1be;font-size:12px;letter-spacing:1px}.stats{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}.stat{background:#192336;padding:14px 22px;border-radius:14px}.stat strong{font-size:25px;display:block}.controls{display:flex;gap:8px;flex-wrap:wrap;margin:18px 0}input,select,button{background:#1c2940;color:inherit;border:1px solid #33465e;border-radius:9px;padding:10px 14px;font:inherit}button{cursor:pointer}button.active{background:#126751}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:15px}.card{background:#172031;border:1px solid #29374c;border-radius:15px;padding:20px}.card h3{margin:12px 0 6px;font-size:17px}.badge{font-size:11px;padding:3px 7px;background:#27354d;border-radius:6px;margin-left:8px}.card p{white-space:pre-line}.meta{font-size:12px;color:#a9b6ca}details{margin-top:14px;border-top:1px solid #304057;padding-top:9px}summary{cursor:pointer;color:#6ce1be}pre{white-space:pre-wrap;font:12px/1.6 system-ui}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;white-space:nowrap}th,td{text-align:left;border-bottom:1px solid #304057;padding:12px}th{color:#a9b6ca}#empty{padding:30px}a{color:#6ce1be}</style>
<main><div class="label">PRIVATE CHARACTER LAB · 합성 캐릭터 테스트</div><h1>같은 게시판, 50개의 목소리</h1><p class="muted">주식 관심사는 배경으로 두고 주식 이야기·주식 잡담·일상을 섞은 테스트입니다. 아래 레벨은 모의 글 작성에 따른 계산이며 실제 계정이나 게시물이 아닙니다.</p>
<div class="stats"><div class="stat"><strong>50</strong>캐릭터 / 문체 샘플</div><div class="stat"><strong>${data.events.length}</strong>${data.days}일 모의 게시 계획</div><div class="stat"><strong>${data.totals.activePersonas}</strong>기간 내 활동 캐릭터</div><div class="stat"><strong>0</strong>DB 쓰기 · 유료 API 호출</div></div>
<div class="controls"><button class="active" id="samples">문체 샘플</button><button id="schedule">활동 · 레벨</button><input id="search" placeholder="닉네임·주제·말투 검색" aria-label="캐릭터 검색"><select id="interest" aria-label="관심사"><option value="">모든 관심사</option></select></div>
<p class="meta">기간 ${data.start}부터 ${data.days}일 · KST · 시드 ${data.seed} · 전체 하루 최대 ${data.dailyCap}글 · 캐릭터별 하루 최대 1글 · 글당 ${data.postXp}XP</p>
<section id="content"></section><p class="muted">샘플은 이번 테스트를 위해 작성된 고정 예시입니다. 활동 계획의 작성 지침에는 말투와 최근 주제 기억이 들어 있으며, 아직 생성 API·실시간 게시 기능은 연결하지 않았습니다.</p></main>
<script>const data=${payload};let tab='samples';const content=document.getElementById('content');const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));const filter=document.getElementById('interest');for(const topic of [...new Set(data.personas.map(p=>p.interest))]){const o=document.createElement('option');o.value=topic;o.textContent=topic;filter.append(o)}
function draw(){const q=document.getElementById('search').value.trim().toLowerCase();const ps=data.personas.filter(p=>(!filter.value||filter.value===p.interest)&&[p.nickname,p.interest,p.focus,p.voice,p.sample.kind,p.sample.title,p.sample.content].join(' ').toLowerCase().includes(q));const ids=new Set(ps.map(p=>p.id));if(tab==='samples'){content.className='grid';content.innerHTML=ps.map(p=>'<article class="card"><b>'+esc(p.nickname)+'</b><span class="badge">테스트 캐릭터</span><div class="meta">'+esc(p.sample.kind)+' · 관심: '+esc(p.interest)+' · '+esc(p.focus)+'<br>'+esc(p.voice)+'</div><h3>'+esc(p.sample.title)+'</h3><p>'+esc(p.sample.content)+'</p><details><summary>성격 · 활동 · 모의 성장</summary><p class="meta">'+esc(p.stance)+'<br>'+p.activeHoursKst[0]+'~'+p.activeHoursKst[1]+'시 KST · 기본 일 활동확률 '+Math.round(p.dailyProbability*100)+'%<br>최소 간격 '+p.minGapHours+'시간 · 주말 가중치 '+p.weekendMultiplier+'<br>모의 글 '+p.simulation.postCount+'개 · '+p.simulation.xp+'XP · Lv.'+p.simulation.level+'</p></details></article>').join('')}else{content.className='table-wrap';content.innerHTML='<table><thead><tr><th>예정 시각 (KST)</th><th>캐릭터</th><th>글의 목적 / 작성 지침</th><th>모의 성장</th></tr></thead><tbody>'+data.events.filter(e=>ids.has(e.personaId)).map(e=>'<tr><td>'+esc(e.kst)+'</td><td>'+esc(e.nickname)+'</td><td>'+esc(e.kind)+' · '+esc(e.angle)+'<details><summary>프롬프트 보기</summary><pre>'+esc(e.draftPrompt)+'</pre></details></td><td>'+e.xpBefore+' → '+e.xpAfter+'XP<br>Lv.'+e.levelBefore+' → '+e.levelAfter+'</td></tr>').join('')+'</tbody></table>'}if(!ps.length)content.innerHTML='<p id="empty">검색 결과가 없습니다.</p>'}
for(const id of ['samples','schedule'])document.getElementById(id).onclick=()=>{tab=id;for(const t of ['samples','schedule'])document.getElementById(t).classList.toggle('active',t===id);draw()};document.getElementById('search').oninput=draw;filter.onchange=draw;draw();</script></html>`;
}
if (require.main === module) {
  const args = process.argv.slice(2);
  const opts = {};
  for(let i=0;i<args.length;i+=2){const key=args[i];const value=args[i+1];if(!['--seed','--days','--start','--daily-cap'].includes(key)||value===undefined)throw new Error('Usage: node tools/community_bot_lab.cjs [--seed 42] [--days 7] [--start 2026-09-11] [--daily-cap 12]');opts[key==='--daily-cap'?'dailyCap':key.slice(2)]=key==='--start'?value:Number(value)}
  const data = simulate(opts);
  const out = path.join(root, 'output/community-bot-lab');
  fs.mkdirSync(out,{recursive:true});
  fs.writeFileSync(path.join(out,'simulation.json'),JSON.stringify(data,null,2));
  fs.writeFileSync(path.join(out,'index.html'),render(data));
  console.log(JSON.stringify({ ...data.totals, preview: path.join(out,'index.html') }));
}
module.exports = {simulate, render, levelFor, personas, postXp};
