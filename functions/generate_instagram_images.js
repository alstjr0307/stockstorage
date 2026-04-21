/**
 * 주식저장소 — 인스타그램 이미지 자동 생성기
 *
 * 사용법:
 *   node generate_instagram_images.js              → 활성 추천주 이미지 생성
 *   node generate_instagram_images.js --completed  → 완료 종목 이미지 생성
 *   node generate_instagram_images.js --all        → 전체 이미지 생성
 *
 * 결과물: instagram_images/ 폴더에 PNG 파일로 저장
 */

const admin = require('firebase-admin');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const FONT_DIR = path.join(__dirname, '..', 'assets', 'fonts');
const OUT_DIR = path.join(__dirname, 'instagram_images');
if (!fs.existsSync(OUT_DIR)) fs.mkdirSync(OUT_DIR);

function formatPrice(price) {
  if (!price && price !== 0) return '-';
  if (price >= 100000000) return `${(price / 100000000).toFixed(1)}억`;
  if (price >= 10000) return `${(price / 10000).toFixed(0)}만원`;
  return `${price.toLocaleString()}원`;
}

function formatRate(from, to) {
  if (!from || !to) return null;
  const rate = ((to - from) / from) * 100;
  return `${rate >= 0 ? '+' : ''}${rate.toFixed(1)}%`;
}

function formatDate(ts) {
  if (!ts) return '';
  const d = ts.toDate ? ts.toDate() : new Date(ts);
  return `${d.getFullYear()}.${String(d.getMonth() + 1).padStart(2, '0')}.${String(d.getDate()).padStart(2, '0')}`;
}

function marketLabel(market) {
  const m = (market || '').toUpperCase();
  if (m === 'KS') return 'KOSPI';
  if (m === 'KQ') return 'KOSDAQ';
  return market || '';
}

function holdingDays(createdAt, closedAt) {
  if (!createdAt || !closedAt) return null;
  const from = createdAt.toDate ? createdAt.toDate() : new Date(createdAt);
  const to = closedAt.toDate ? closedAt.toDate() : new Date(closedAt);
  return Math.round((to - from) / (1000 * 60 * 60 * 24));
}

// Python 스크립트로 이미지 생성
function generateImagePython(pick, type) {
  const data = JSON.stringify(pick).replace(/'/g, "\\'");
  const script = buildPythonScript(pick, type);
  const tmpScript = path.join(OUT_DIR, '_tmp_gen.py');
  fs.writeFileSync(tmpScript, script, 'utf8');

  try {
    execSync(`python3 ${tmpScript}`, { stdio: 'pipe' });
    console.log(`✅ 이미지 생성: ${pick.name}`);
  } catch (e) {
    console.error(`❌ 실패 (${pick.name}):`, e.stderr?.toString() || e.message);
  }
  fs.unlinkSync(tmpScript);
}

function buildPythonScript(pick, type) {
  const fontDir = FONT_DIR.replace(/\\/g, '/');
  const outDir = OUT_DIR.replace(/\\/g, '/');

  const name = (pick.name || '').replace(/'/g, "\\'");
  const ticker = pick.ticker || '';
  const market = marketLabel(pick.market);
  const category = pick.category || '추천';
  const reason = (pick.reason || '').replace(/'/g, "\\'").replace(/\n/g, '\\n');
  const isPremium = pick.isPremium ? 'True' : 'False';

  const buyPrice = formatPrice(pick.buyPrice);
  const targetPrice = formatPrice(pick.targetPrice);
  const targetRate = formatRate(pick.buyPrice, pick.targetPrice) || '';
  const createdDate = formatDate(pick.createdAt);

  if (type === 'active') {
    const currentPrice = pick.currentPrice ? formatPrice(pick.currentPrice) : null;
    const currentRate = pick.currentPrice ? formatRate(pick.buyPrice, pick.currentPrice) : null;
    const isUp = currentRate ? !currentRate.startsWith('-') : true;

    return `
import sys
sys.path.insert(0, '.')
from PIL import Image, ImageDraw, ImageFont
import textwrap

# ── 설정 ──
W, H = 1080, 1080
BG_COLOR      = (10, 14, 26)       # #0A0E1A 다크
CARD_COLOR    = (19, 25, 41)       # #131929
ACCENT        = (16, 185, 129)     # #10B981
UP_COLOR      = (240, 68, 82)      # #F04452
DOWN_COLOR    = (22, 119, 255)     # #1677FF
TEXT_PRIMARY  = (255, 255, 255)
TEXT_SECONDARY= (255, 255, 255, 122)
TEXT_TERTIARY = (255, 255, 255, 61)
BORDER        = (255, 255, 255, 15)

# ── 폰트 ──
def font(name, size):
    try:
        return ImageFont.truetype(f'${fontDir}/{name}', size)
    except:
        return ImageFont.load_default()

f_eb   = font('Pretendard-ExtraBold.ttf', 52)
f_bold = font('Pretendard-Bold.ttf', 36)
f_bold_sm = font('Pretendard-Bold.ttf', 28)
f_semi = font('Pretendard-SemiBold.ttf', 28)
f_semi_sm = font('Pretendard-SemiBold.ttf', 24)
f_med  = font('Pretendard-Medium.ttf', 24)
f_med_sm = font('Pretendard-Medium.ttf', 22)
f_reg  = font('Pretendard-Regular.ttf', 22)
f_tag  = font('Pretendard-SemiBold.ttf', 20)
f_small= font('Pretendard-Regular.ttf', 19)

img = Image.new('RGB', (W, H), BG_COLOR)
d   = ImageDraw.Draw(img, 'RGBA')

def text(x, y, txt, fnt, color=TEXT_PRIMARY, anchor='la'):
    d.text((x, y), txt, font=fnt, fill=color, anchor=anchor)

def pill(x, y, w, h, color, radius=12):
    d.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=color)

def hrule(y, color=(255,255,255,20), pad=48):
    d.line([(pad, y), (W-pad, y)], fill=color, width=1)

# ── 배경 그라데이션 느낌 (상단 accent glow) ──
for i in range(120):
    alpha = int(18 * (1 - i/120))
    d.line([(0, i), (W, i)], fill=(16, 185, 129, alpha))

# ── 앱 이름 ──
text(48, 54, '주식저장소', f_semi_sm, (16, 185, 129, 200))

# ── 카테고리 배지 ──
badge_label = '${category}' if '${category}' else '추천'
badge_color = (16, 185, 129, 30)
badge_border= (16, 185, 129, 80)
bw = 90 if badge_label == '단기' else 80
pill(W-48-bw, 46, bw, 36, badge_color, radius=18)
d.rounded_rectangle([W-48-bw, 46, W-48, 82], radius=18, outline=badge_border, width=1)
text(W-48-bw//2, 64, badge_label, f_tag, ACCENT, anchor='mm')

# ── 프리미엄 배지 ──
if ${isPremium}:
    pill(W-48-bw-82, 46, 74, 36, (255, 180, 0, 20), radius=18)
    d.rounded_rectangle([W-48-bw-82, 46, W-48-bw-8, 82], radius=18, outline=(255,180,0,80), width=1)
    text(W-48-bw-45, 64, '⭐ 프리미엄', font('Pretendard-SemiBold.ttf', 18), (255, 180, 0), anchor='mm')

# ── 종목명 ──
text(48, 116, '${name}', f_eb, TEXT_PRIMARY)

# ── 시장/티커 ──
market_str = '${market}  ·  ${ticker}'
text(48, 185, market_str, f_med_sm, (255,255,255,140))

hrule(226)

# ── 추천 이유 ──
text(48, 254, '추천 이유', f_semi_sm, ACCENT)
reason_raw = '${reason}'
reason_lines = reason_raw.replace('\\\\n', '\\n').split('\\n')
wrapped = []
for line in reason_lines:
    if len(line) > 28:
        wrapped += textwrap.wrap(line, width=28)
    else:
        wrapped.append(line)
max_lines = 7
display_lines = wrapped[:max_lines]
if len(wrapped) > max_lines:
    display_lines[-1] = display_lines[-1][:22] + '...'

y_reason = 298
for line in display_lines:
    text(48, y_reason, line, f_reg, (255,255,255,200))
    y_reason += 34

# ── 구분선 ──
hrule(590)

# ── 수치 카드 ──
card_y = 616
card_h = 130
card_x1, card_x2 = 48, W//2 + 12
card_w = W//2 - 60

# 매수가 카드
d.rounded_rectangle([card_x1, card_y, card_x1+card_w, card_y+card_h], radius=16, fill=CARD_COLOR)
text(card_x1+24, card_y+22, '매수가', f_semi_sm, (255,255,255,140))
text(card_x1+24, card_y+62, '${buyPrice}', f_bold, TEXT_PRIMARY)

# 목표가 카드
d.rounded_rectangle([card_x2, card_y, card_x2+card_w, card_y+card_h], radius=16, fill=CARD_COLOR)
text(card_x2+24, card_y+22, '목표가', f_semi_sm, (255,255,255,140))
text(card_x2+24, card_y+62, '${targetPrice}', f_bold, UP_COLOR)
text(card_x2+24, card_y+98, '${targetRate}', f_semi_sm, UP_COLOR)

# ── 현재가 (있을 때만) ──
${currentPrice ? `
cur_y = card_y + card_h + 16
d.rounded_rectangle([48, cur_y, W-48, cur_y+76], radius=16, fill=CARD_COLOR)
cur_color = (${isUp ? '240, 68, 82' : '22, 119, 255'})
text(72, cur_y+24, '현재가', f_semi_sm, (255,255,255,140))
text(72+100, cur_y+24, '${currentPrice}', f_semi, cur_color)
text(72+100+160, cur_y+24, '${currentRate}', f_semi, cur_color)
` : ''}

# ── 추천일 ──
hrule(820)
text(48, 844, '추천일  ${createdDate}', f_med_sm, (255,255,255,120))

# ── 하단 CTA ──
pill(48, 898, W-96, 64, ACCENT, radius=16)
text(W//2, 930, '주식저장소 앱에서 더 보기', f_semi, (255,255,255), anchor='mm')

# ── 저장 ──
safe_name = '${name}'.replace('/', '_').replace(' ', '_')
out_path = '${outDir}/active_${ticker}_${name}.png'.replace('${name}', safe_name)
img.save(f'${outDir}/active_${ticker}_{safe_name}.png', 'PNG')
print(f'saved: active_${ticker}_{safe_name}.png')
`;
  }

  // completed 타입
  const closedPrice = formatPrice(pick.closedPrice);
  const closedRate = formatRate(pick.buyPrice, pick.closedPrice) || '';
  const tRate = formatRate(pick.buyPrice, pick.targetPrice) || '';
  const days = holdingDays(pick.createdAt, pick.closedAt);
  const closedDate = formatDate(pick.closedAt);
  const exceeded = pick.closedPrice > pick.targetPrice;
  const isPositive = !closedRate.startsWith('-');

  return `
import sys
from PIL import Image, ImageDraw, ImageFont
import textwrap

W, H = 1080, 1080
BG_COLOR     = (10, 14, 26)
CARD_COLOR   = (19, 25, 41)
ACCENT       = (16, 185, 129)
UP_COLOR     = (240, 68, 82)
DOWN_COLOR   = (22, 119, 255)
GOLD         = (255, 180, 0)
TEXT_PRIMARY = (255, 255, 255)

def font(name, size):
    try:
        return ImageFont.truetype(f'${fontDir}/{name}', size)
    except:
        return ImageFont.load_default()

f_eb    = font('Pretendard-ExtraBold.ttf', 72)
f_bold  = font('Pretendard-Bold.ttf', 38)
f_bold_sm = font('Pretendard-Bold.ttf', 30)
f_semi  = font('Pretendard-SemiBold.ttf', 28)
f_semi_sm = font('Pretendard-SemiBold.ttf', 24)
f_med   = font('Pretendard-Medium.ttf', 24)
f_reg   = font('Pretendard-Regular.ttf', 22)
f_tag   = font('Pretendard-SemiBold.ttf', 20)
f_small = font('Pretendard-Regular.ttf', 19)

img = Image.new('RGB', (W, H), BG_COLOR)
d   = ImageDraw.Draw(img, 'RGBA')

def text(x, y, txt, fnt, color=TEXT_PRIMARY, anchor='la'):
    d.text((x, y), txt, font=fnt, fill=color, anchor=anchor)

def pill(x, y, w, h, color, radius=12):
    d.rounded_rectangle([x, y, x+w, y+h], radius=radius, fill=color)

def hrule(y, color=(255,255,255,20), pad=48):
    d.line([(pad, y), (W-pad, y)], fill=color, width=1)

# 배경 glow
rate_val = float('${closedRate}'.replace('%','').replace('+',''))
glow_color = (240, 68, 82) if rate_val >= 0 else (22, 119, 255)
for i in range(160):
    alpha = int(22 * (1 - i/160))
    d.line([(0, i), (W, i)], fill=(*glow_color, alpha))

# 앱 이름
text(48, 54, '주식저장소', font('Pretendard-SemiBold.ttf', 20), (16, 185, 129, 200))

# 수익 실현 배지
pill(W-48-130, 44, 130, 38, (240, 68, 82, 30), radius=19)
d.rounded_rectangle([W-48-130, 44, W-48, 82], radius=19, outline=(240,68,82,100), width=1)
text(W-48-65, 63, '${'수익 실현 완료'}', f_tag, UP_COLOR, anchor='mm')

# 종목명
text(48, 116, '${name}', f_eb, TEXT_PRIMARY)

# 시장/티커
text(48, 210, '${market}  ·  ${ticker}', f_med, (255,255,255,140))

hrule(256)

# 수익률 큰 숫자
rate_color = UP_COLOR if rate_val >= 0 else DOWN_COLOR
text(48, 284, '${closedRate}', font('Pretendard-ExtraBold.ttf', 96), rate_color)
exceed_note = '${'목표가 초과 달성 🚀' if exceeded else '목표 달성 ✅'}'
text(48, 400, exceed_note, f_semi, (255,255,255,160))

hrule(456)

# 3단 수치 카드
cw = (W - 96 - 32) // 3
cy = 478
for i, (label, val, color) in enumerate([
    ('매수가', '${buyPrice}', (255,255,255,200)),
    ('목표가', '${targetPrice}  (${tRate})', UP_COLOR),
    ('실현가', '${closedPrice}', rate_color),
]):
    cx = 48 + i * (cw + 16)
    d.rounded_rectangle([cx, cy, cx+cw, cy+110], radius=14, fill=CARD_COLOR)
    text(cx+20, cy+18, label, f_tag, (255,255,255,120))
    text(cx+20, cy+52, val, f_semi_sm, color)

# 보유기간
${days !== null ? `
d.rounded_rectangle([48, 614, W-48, 670], radius=14, fill=CARD_COLOR)
text(W//2, 642, f'보유기간  ${days}일', f_semi, (255,255,255,160), anchor='mm')
` : ''}

hrule(692)

# 추천 근거
text(48, 716, '추천 근거', f_semi_sm, ACCENT)
reason_raw = '${reason}'
reason_lines = reason_raw.replace('\\\\n', '\\n').split('\\n')
wrapped = []
for line in reason_lines:
    if len(line) > 28:
        wrapped += textwrap.wrap(line, width=28)
    else:
        wrapped.append(line)
max_lines = 4
display_lines = wrapped[:max_lines]
if len(wrapped) > max_lines:
    display_lines[-1] = display_lines[-1][:22] + '...'

yr = 758
for line in display_lines:
    text(48, yr, line, f_reg, (255,255,255,190))
    yr += 34

# 날짜
hrule(894)
text(48, 918, '${createdDate}  →  ${closedDate}', f_med, (255,255,255,100))

# CTA
pill(48, 966, W-96, 64, ACCENT, radius=16)
text(W//2, 998, '주식저장소 앱에서 더 보기', f_semi, (255,255,255), anchor='mm')

# 저장
safe_name = '${name}'.replace('/', '_').replace(' ', '_')
img.save(f'${outDir}/completed_${ticker}_{safe_name}.png', 'PNG')
print(f'saved: completed_${ticker}_{safe_name}.png')
`;
}

async function main() {
  const args = process.argv.slice(2);
  const showAll = args.includes('--all');
  const showCompleted = args.includes('--completed') || showAll;
  const showActive = !args.includes('--completed') || showAll;

  console.log('🔍 Firestore에서 추천주 로딩 중...\n');
  const snapshot = await db.collection('stock_picks').orderBy('createdAt', 'desc').get();

  if (snapshot.empty) {
    console.log('❌ 데이터 없음');
    process.exit(0);
  }

  const picks = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  const activePicks = picks.filter(p => p.status === 'active' || p.status === 'open');
  const completedPicks = picks.filter(p => p.status === 'completed');

  console.log(`진행 중: ${activePicks.length}개  |  완료: ${completedPicks.length}개\n`);

  if (showActive) {
    console.log('📸 활성 추천주 이미지 생성 중...');
    for (const pick of activePicks) generateImagePython(pick, 'active');
  }

  if (showCompleted) {
    console.log('\n📸 완료 종목 이미지 생성 중...');
    for (const pick of completedPicks) generateImagePython(pick, 'completed');
  }

  console.log(`\n✅ 완료! 이미지 저장 위치: functions/instagram_images/`);
  process.exit(0);
}

main().catch(e => { console.error(e.message); process.exit(1); });
