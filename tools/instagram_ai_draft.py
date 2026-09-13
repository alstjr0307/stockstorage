"""Render a saved stock_ai_analyses document into an Instagram draft; no publishing."""

import argparse
import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
KST = timezone(timedelta(hours=9))
BG, FG, MUTED, ACCENT = '#101820', '#F7FAFC', '#A4B4C1', '#85E3BD'


def clean(value):
    return str(value or '').strip()


def build_draft(data, now=None, max_age_hours=72, sample=False):
    now = now or datetime.now(timezone.utc)
    for key in ('name', 'ticker', 'market', 'updatedAt', 'summary'):
        if not clean(data.get(key)):
            raise ValueError(f'필수 분석 필드 누락: {key}')
    if not re.fullmatch(r'[A-Za-z0-9._-]+', data['ticker']):
        raise ValueError('종목 코드 형식 오류')
    if not re.fullmatch(r'[A-Za-z0-9_-]+', data['market']):
        raise ValueError('시장 코드 형식 오류')
    stamp = datetime.fromisoformat(data['updatedAt'].replace('Z', '+00:00'))
    if stamp.tzinfo is None:
        raise ValueError('updatedAt에 시간대가 필요합니다.')
    if not sample and not timedelta(0) <= now - stamp <= timedelta(hours=max_age_hours):
        raise ValueError('분석이 오래되었거나 미래 시점입니다. 새 분석 결과를 사용하세요.')
    risks = [clean(x) for x in data.get('risks', []) if clean(x)]
    if not risks:
        risks = [clean(x.get('description')) for x in data.get('risksDetailed', [])
                 if clean(x.get('description'))]
    if not risks:
        raise ValueError('위험 요인이 없는 분석은 홍보 카드로 만들 수 없습니다.')
    # Extract complete source text, including qualifications. Never invent a claim
    # or truncate a sentence to make it fit a template.
    catalysts = data.get('catalysts', [])[:2]
    material = '\n\n'.join(
        f"{clean(c.get('title'))}\n{clean(c.get('detail'))}" for c in catalysts
        if clean(c.get('detail'))
    ) or clean(data.get('todayReason'))
    if not material:
        raise ValueError('주요 재료 또는 최근 등락 배경이 필요합니다.')
    date_label = stamp.astimezone(KST).strftime('%Y.%m.%d %H:%M KST')
    slides = [
        {'title': f"{data['name']}\n무엇을 봐야 할까?", 'body':
         'AI 분석으로 살펴보는\n주요 재료와 위험 요인', 'label': '오늘의 종목 읽기'},
        {'title': '분석 핵심 요약', 'body': clean(data['summary']), 'label': '핵심 요약'},
        {'title': '주목할 재료', 'body': material, 'label': '주요 재료'},
        {'title': '함께 볼 위험 요인', 'body': '\n\n'.join(risks[:3]), 'label': '위험 요인'},
        {'title': '더 많은 종목 분석이\n궁금하다면?', 'body':
         '주식저장소 앱 다운로드\n\n내 관심 종목의 AI 분석을 확인하세요.\n\n@tf_stockstorage 프로필 링크에서 다운로드', 'label': '주식저장소와 함께'},
    ]
    sources = []
    for group in ('sourceNews', 'sourceDisclosures', 'sourceReports'):
        for source in data.get(group, []):
            url = clean(source.get('url'))
            if url.startswith(('https://', 'http://')) and url not in sources:
                sources.append(url)
    caption = '\n\n'.join([
        ('[디자인 샘플 · 실제 종목 아님]\n' if sample else '') +
        f"{data['name']} ({data['ticker']}) AI 분석",
        clean(data['summary']),
        '함께 볼 위험 요인\n' + '\n'.join('• ' + x for x in risks[:3]),
        f'분석 기준: {date_label}',
        '더 많은 종목 분석이 궁금하다면?\n@tf_stockstorage 프로필 링크에서 주식저장소 앱을 다운로드하세요.',
        'AI 분석은 오류가 있을 수 있으며 투자 판단의 참고 자료입니다.',
        '#주식저장소 #AI종목분석 #주식공부 #종목분석',
    ])
    if len(caption) > 2200:
        raise ValueError('캡션이 2,200자를 넘습니다. 원문 의미를 유지하며 편집하세요.')
    if not sample and not sources:
        raise ValueError('출처 URL이 필요합니다.')
    return {'schemaVersion': 1, 'status': 'draft', 'sample': sample,
            'name': data['name'], 'ticker': data['ticker'], 'market': data['market'],
            'analysisAt': stamp.isoformat(), 'dateLabel': date_label,
            'slides': slides, 'caption': caption, 'sources': sources}


def font(size, bold=False):
    return ImageFont.truetype(str(ROOT / 'assets/fonts' /
                                ('Pretendard-Bold.ttf' if bold else 'Pretendard-Regular.ttf')), size)


def wrap(draw, text, face, width):
    lines = []
    for paragraph in text.split('\n'):
        line = ''
        for char in paragraph:
            if line and draw.textlength(line + char, font=face) > width:
                lines.append(line)
                line = ''
            line += char
        lines.append(line)
    return lines


def fit(draw, text, box, maximum, minimum, bold=False, color=FG):
    x, y, width, height = box
    for size in range(maximum, minimum - 1, -1):
        face = font(size, bold)
        lines = wrap(draw, text, face, width)
        spacing = round(size * 1.48)
        if len(lines) * spacing <= height:
            for line in lines:
                draw.text((x, y), line, font=face, fill=color)
                y += spacing
            return
    raise ValueError('카드에 원문이 들어가지 않습니다. 의미를 유지하며 편집해야 합니다.')


def render(draft, out):
    # Render every card before writing so a layout failure produces no partial set.
    cards = []
    for i, slide in enumerate(draft['slides']):
        im = Image.new('RGB', (1080, 1350), BG)
        draw = ImageDraw.Draw(im)
        draw.rounded_rectangle((76, 70, 280, 123), radius=26, fill=ACCENT)
        draw.text((97, 80), '주식저장소', font=font(29, True), fill=BG)
        draw.text((880, 80), f'{i + 1:02d} / 05', font=font(28), fill=MUTED)
        draw.text((76, 185), slide['label'], font=font(31), fill=ACCENT)
        fit(draw, slide['title'], (76, 250, 928, 260), 76, 42, True)
        draw.line((76, 540, 1004, 540), fill='#344550', width=2)
        fit(draw, slide['body'], (76, 590, 928, 570), 44, 29)
        footer = '디자인 샘플 · 실제 종목 아님' if draft['sample'] else draft['dateLabel']
        draw.text((76, 1220), footer, font=font(25), fill=MUTED)
        draw.text((76, 1270), 'AI 분석 · 투자 판단 참고 자료', font=font(23), fill=MUTED)
        cards.append(im)
    out.mkdir(parents=True, exist_ok=False)
    for i, im in enumerate(cards):
        im.save(out / f'{i + 1:02d}.jpg', quality=95)
    (out / 'caption.txt').write_text(draft['caption'], encoding='utf-8')
    (out / 'draft.json').write_text(json.dumps(draft, ensure_ascii=False, indent=2), encoding='utf-8')
    preview = Image.new('RGB', (1080, 540), BG)
    for i, im in enumerate(cards):
        preview.paste(im.resize((216, 270)), (i * 216, 130))
    preview.save(out / 'preview.jpg', quality=95)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--sample', action='store_true', help='모든 카드에 샘플 표시')
    args = parser.parse_args()
    data = json.loads(args.input.read_text(encoding='utf-8-sig'))
    draft = build_draft(data, sample=args.sample)
    render(draft, args.output)
    print(f'Draft created: {args.output.resolve()}')


if __name__ == '__main__':
    main()
