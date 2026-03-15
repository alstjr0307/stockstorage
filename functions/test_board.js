const https = require('https');

https.get({
  hostname: 'finance.naver.com',
  path: '/item/board.nhn?code=005930&ordertype=&searchtype=&page=1',
  headers: { 'User-Agent': 'Mozilla/5.0', 'Referer': 'https://finance.naver.com' }
}, r => {
  let d = '';
  r.on('data', c => d += c);
  r.on('end', () => {
    // 각 게시글 행: nid → 제목 → 날짜 → 조회수
    const rowPattern = /nid=(\d+)[^"]*"[^>]*title="([^"]+)"[\s\S]{0,600}?(\d{4}\.\d{2}\.\d{2} \d{2}:\d{2})[\s\S]{0,200}?<td[^>]*>(\d+)<\/td>/g;
    const posts = [...d.matchAll(rowPattern)];
    console.log('파싱된 게시글:', posts.length);
    posts.slice(0, 5).forEach(m => {
      console.log(`[${m[3]}] ${m[2]} (조회:${m[4]})`);
    });

    // 날짜 패턴 확인
    const dateCtx = d.indexOf('이해불가');
    const section = d.slice(dateCtx, dateCtx + 1000);
    const dateMatch = section.match(/\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}/);
    console.log('\n날짜:', dateMatch?.[0]);
  });
});
