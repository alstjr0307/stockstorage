/** Manual generation uses the same pipeline as the scheduled functions.
 * OPENAI_API_KEY must be supplied via the environment. --dry-run never writes.
 * node generate_brief_now.js --slot=08 --dry-run
 */
const { initializeApp, cert } = require('firebase-admin/app');
const { runAiBriefGeneration } = require('./ai_brief');

async function main() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY 환경변수를 설정하세요.');
  initializeApp({ credential: cert(require('./serviceAccountKey.json')) });
  const hour = Number(new Intl.DateTimeFormat('en', {
    timeZone: 'Asia/Seoul', hour: 'numeric', hour12: false,
  }).format(new Date()));
  const slot = process.argv.find(arg => arg.startsWith('--slot='))?.split('=')[1]
    || (hour < 11 ? '08' : hour < 14 ? '12' : '15');
  if (!['08', '09', '12', '15'].includes(slot)) throw new Error('지원 슬롯: 08, 12, 15');
  const result = await runAiBriefGeneration(apiKey, slot, {
    dryRun: process.argv.includes('--dry-run'),
  });
  console.log(typeof result === 'string' ? result : JSON.stringify(result, null, 2));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
