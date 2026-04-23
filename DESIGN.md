# 주식저장소 Design System

> **컨셉: "Calm Finance"**
> 복잡한 금융 정보를 군더더기 없이. 토스처럼 — 보는 순간 이해되고, 쓰는 순간 편하게.
> 글씨로 압도하고, 여백으로 숨 쉬게 한다.
>
> **트렌드 레퍼런스**: 토스 커뮤니티 — 제목이 크고 bold, 탭은 pill 형태, 카드 경계 없이 배경 위에 콘텐츠 바로.

---

## 1. Color

### 원칙
- **색은 의미가 있을 때만 쓴다.** 장식용 색 금지.
- 배경과 텍스트의 대비만으로 계층을 만든다.
- 액센트는 딱 하나. 행동 유도(CTA)에만.

### Palette

| Token | Light | Dark | 용도 |
|---|---|---|---|
| `bg.primary` | `#F8F9FA` | `#0A0E1A` | 앱 전체 배경 |
| `bg.secondary` | `#FFFFFF` | `#131929` | 카드, 시트 |
| `bg.tertiary` | `#F2F4F6` | `#1A2235` | 입력창, 서브 영역 |
| `border` | `#E8EAED` | `#FFFFFF0F` | 구분선, 카드 테두리 |
| `label.primary` | `#191F28` | `#FFFFFF` | 본문, 제목 |
| `label.secondary` | `#6B7684` | `#FFFFFF7A` | 보조 텍스트 |
| `label.tertiary` | `#B0B8C1` | `#FFFFFF3D` | 힌트, 비활성 |
| `accent` | `#10B981` | `#34D399` | CTA, 링크, 포커스 |
| `up` | `#F04452` | `#F04452` | 상승 (토스 스타일 — 빨간색) |
| `down` | `#1677FF` | `#4D9BFF` | 하락 (토스 스타일 — 파란색) |
| `positive` | `#0DC99A` | `#0DC99A` | 성공, 긍정 |
| `warning` | `#FF9500` | `#FF9500` | 경고 |
| `negative` | `#F04452` | `#F04452` | 오류 |

> **참고**: 국내 증권 앱 컨벤션 — 상승은 빨간색, 하락은 파란색.

### Index 색상

| 지수 | Color |
|---|---|
| KOSPI | `#3182F6` |
| KOSDAQ | `#00C4B4` |
| S&P 500 | `#6366F1` |
| NASDAQ | `#8B5CF6` |
| USD/KRW | `#F59E0B` |
| WTI | `#EF4444` |

---

## 2. Typography

**폰트: Pretendard (없으면 Inter) + JetBrains Mono (숫자 전용)**

### Scale

| Token | Size | Weight | LineHeight | LetterSpacing | 용도 |
|---|---|---|---|---|---|
| `type.display` | 32px | 800 | 1.15 | -0.8 | 큰 숫자, 히어로 |
| `type.title1` | 26px | 700 | 1.25 | -0.6 | 페이지 제목 |
| `type.title2` | 22px | 700 | 1.3 | -0.5 | 섹션 제목, 카드 헤드라인 |
| `type.title3` | 18px | 600 | 1.4 | -0.3 | 카드 제목, 리스트 아이템 |
| `type.body1` | 16px | 400 | 1.65 | 0 | 본문 |
| `type.body2` | 15px | 400 | 1.65 | 0 | 보조 본문 |
| `type.caption1` | 13px | 500 | 1.4 | 0 | 라벨, 태그 |
| `type.caption2` | 12px | 400 | 1.4 | 0 | 타임스탬프, 힌트 |
| `type.micro` | 11px | 600 | 1.3 | 0 | 배지, 아주 작은 라벨 |
| `type.number.lg` | 34px | 700 | 1.05 | -0.6 | 주가, 총액 (Mono) |
| `type.number.md` | 20px | 700 | 1.2 | -0.3 | 지수 카드 수치 (Mono) |
| `type.number.sm` | 14px | 600 | 1.4 | 0 | 소형 수치 (Mono) |

### 원칙
- **숫자는 항상 JetBrains Mono.** 자릿수 정렬이 곧 신뢰감.
- weight는 400 / 600 / 700 / 800 네 가지.
- **title2(22px)** 를 카드 헤드라인 기본으로.

---

## 3. Spacing

**기본 단위: 4px**

| Token | Size | 용도 |
|---|---|---|
| `space.2` | 2px | 아이콘-라벨 미세 간격 |
| `space.4` | 4px | 인라인 최소 간격 |
| `space.8` | 8px | 컴포넌트 내부 간격 |
| `space.12` | 12px | 리스트 아이템 간격 |
| `space.16` | 16px | 카드 내부 패딩, 좌우 여백 |
| `space.20` | 20px | 섹션 패딩 |
| `space.24` | 24px | 섹션 간격 |
| `space.32` | 32px | 큰 섹션 간격 |
| `space.48` | 48px | 화면 상단 여백 |

### 화면 레이아웃
- 좌우 여백: `20px`
- 카드 간 간격: `12px`
- 섹션 간 간격: `28px`
- 하단 여백: FAB 있을 때 `88px`, 없으면 `34px` (safe area)

---

## 4. Border Radius

| Token | Size | 용도 |
|---|---|---|
| `radius.4` | 4px | 태그, 아주 작은 배지 |
| `radius.8` | 8px | 버튼(소), 칩, 입력창 |
| `radius.12` | 12px | 카드(소), 버튼(중) |
| `radius.16` | 16px | **카드 기본값** |
| `radius.20` | 20px | 바텀시트, 모달 |
| `radius.full` | 9999px | 아바타, 토글, FAB |

---

## 5. Shadow & Depth

```dart
// 카드 (라이트)
BoxDecoration(
  color: Color(0xFFFFFFFF),
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(color: Color(0x0D000000), blurRadius: 10, offset: Offset(0, 2)),
  ],
)

// 카드 (다크) — 그림자 대신 border
BoxDecoration(
  color: Color(0xFF131929),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: Color(0xFF1A2235), width: 1),
)
```

---

## 6. Components

### Tab Bar — ✅ 업데이트

**다크 모드에서도 가독성 보장**: 활성 탭은 흰 배경 + 다크 텍스트, 비활성은 반투명 텍스트.

```dart
TabBar(
  dividerColor: Colors.transparent,
  labelColor: isDark ? const Color(0xFF0A0E1A) : cs.surface,      // 다크텍스트
  unselectedLabelColor: cs.onSurface.withValues(alpha: 0.4),
  indicatorSize: TabBarIndicatorSize.tab,
  indicator: BoxDecoration(
    color: isDark ? Colors.white : cs.onSurface,   // ← 흰 배경 (다크) / 다크 배경 (라이트)
    borderRadius: BorderRadius.circular(9999),
  ),
  ...
)
```

> ❌ 이전: `indicator: BoxDecoration(color: cs.surface ...)` → 다크에서 배경색과 동화되어 비활성 탭 안 보임
> ✅ 현재: 흰 배경 pill + 다크 텍스트 → 어떤 테마에서도 명확한 선택 상태

### PER/PBR — ✅ 업데이트

가격 행에 float하지 않고 **별도 pill 행**으로 분리.

```dart
// 기존: 현재가 Row 오른쪽에 Column으로 float → 어색
// 개선: 현재가 아래 별도 Row로 pill 배치
Row(
  children: [
    if (f.per != null) _perPbrPill('PER', f.per!.toStringAsFixed(1), cs),
    if (f.per != null && f.pbr != null) const SizedBox(width: 8),
    if (f.pbr != null) _perPbrPill('PBR', f.pbr!.toStringAsFixed(2), cs),
  ],
)

Widget _perPbrPill(String label, String value, ColorScheme cs) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: cs.onSurface.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(9999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: GoogleFonts.inter(
          color: cs.onSurface.withValues(alpha: 0.35), fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(width: 5),
        Text(value, style: GoogleFonts.robotoMono(
          color: cs.onSurface.withValues(alpha: 0.75), fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
```

### AppBar (종목 상세) — ✅ 업데이트

종목코드만 표시 → **종목명 + 코드** 2줄 표시.

```dart
title: Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(pick.name, style: GoogleFonts.inter(
      color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
    Text(pick.ticker, style: GoogleFonts.robotoMono(
      color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11, fontWeight: FontWeight.w500)),
  ],
),
centerTitle: true,
```

### 커뮤니티 의견 (투표) — ✅ 업데이트

- 비율 바 추가 (상승:하락 시각적 비율 표현)
- flex로 버튼 크기 비율 반영 (50/50 동등 → 실제 투표 비율)

```dart
// 비율 바
ClipRRect(
  borderRadius: BorderRadius.circular(9999),
  child: SizedBox(
    height: 5,
    child: Row(children: [
      Flexible(
        flex: (upRatio * 100).round(),
        child: Container(color: const Color(0xFF10B981)),
      ),
      Flexible(
        flex: ((1 - upRatio) * 100).round(),
        child: Container(color: const Color(0xFF1677FF).withValues(alpha: 0.5)),
      ),
    ]),
  ),
),

// 버튼 flex 비율 반영
Expanded(
  flex: total > 0 ? (upRatio * 10).round().clamp(3, 7) : 5,
  child: /* 상승 버튼 */,
),
Expanded(
  flex: total > 0 ? ((1 - upRatio) * 10).round().clamp(3, 7) : 5,
  child: /* 하락 버튼 */,
),
```

### 캡처 공유 버튼 — ✅ 업데이트

Primary CTA처럼 배치되던 outline 버튼 → secondary TextButton으로 낮춤.

```dart
// ❌ 이전: SizedBox(width: double.infinity, child: OutlinedButton.icon(...))
// ✅ 개선: 덜 강조된 TextButton
Center(
  child: TextButton.icon(
    onPressed: _capturing ? null : _captureAndShare,
    icon: Icon(Icons.camera_alt_outlined, size: 16,
        color: cs.onSurface.withValues(alpha: 0.4)),
    label: Text('캡처해서 공유하기', style: GoogleFonts.inter(
        color: cs.onSurface.withValues(alpha: 0.4),
        fontWeight: FontWeight.w500, fontSize: 13)),
  ),
),
```

### 코멘트 아이템 — ✅ 업데이트

카드 Container → **borderless row** (토스 스타일). 아바타 크기 업.

```dart
// ❌ 이전: Container(margin, padding, decoration: BoxDecoration(borderRadius: 12))
// ✅ 개선: Divider로만 구분, 아바타 radius 12 → 18
Column(children: [
  Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        UserLevelAvatar(uid: comment.uid, radius: 18, ...),   // ← radius 업
        const SizedBox(width: 10),
        Expanded(child: Column(children: [
          Text(comment.nickname, style: /* w700, 13px */),
          Text(timeago.format(...), style: /* tertiary, 11px */),
        ])),
        // 삭제 버튼
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 46, top: 8),  // ← 아바타 들여쓰기
        child: Text(comment.content, style: /* 14px, h:1.55 */),
      ),
    ]),
  ),
  Divider(height: 1, thickness: 1, color: cs.onSurface.withValues(alpha: 0.05)),
])
```

---

## 7. Data Display (기존 유지)

### 주가 / 수익률 표시 규칙

```
+12.34%  →  color: up,   앞에 + 명시
-5.67%   →  color: down, 앞에 - 자동
0.00%    →  color: label.secondary
```

- 폰트: 항상 JetBrains Mono
- 소수점: 주가 2자리, 수익률 2자리, 퍼센트 1자리

### 변동 pill 배지 — ✅ 추가

수치 옆 인라인 표시보다 pill 배지로 감싸면 가독성 향상.

```dart
Container(
  decoration: BoxDecoration(
    color: isPositive
        ? _kUpColor.withValues(alpha: 0.10)
        : _kDownColor.withValues(alpha: 0.10),
    borderRadius: BorderRadius.circular(9999),
  ),
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  child: Text(changeText, style: GoogleFonts.robotoMono(
    fontSize: 13, fontWeight: FontWeight.w600,
    color: isPositive ? _kUpColor : _kDownColor)),
)
```

---

## 8. Divider (기존 유지)

```dart
Divider(height: 1, thickness: 1, color: border)
Container(height: 8, color: bg.tertiary)  // 섹션 구분
```

---

## 9. Motion (기존 유지)

| 상황 | Duration | Curve |
|---|---|---|
| 버튼 피드백 | 100ms | linear |
| 화면 전환 | 250ms | easeOutCubic |
| 바텀시트 | 300ms | easeOutQuart |
| 숫자 카운팅 | 600ms | easeOut |

---

## 10. 커뮤니티 피드 (기존 유지)

(이전 섹션 11 내용 — 변경 없음)

---

## 11. 순위 리스트 (기존 유지)

(이전 섹션 12 내용 — 변경 없음)

---

## 12. 매매일지 화면 — ✅ 신규

> 레퍼런스: 토스 스타일 — 종목명 Primary, 핵심 수치 hero, row 리스트, 날짜 섹션 헤더

### 핵심 원칙

- **정보 계층**: 종목명 > 평가손익·수익률 > 세부 수치(매수가/현재가 등)
- **날짜는 섹션 헤더로**: 카드마다 날짜 반복 금지. 거래일 기준 내림차순 섹션 헤더.
- **그리드 금지**: 2×N 격자 레이아웃 대신 `좌:라벨 / 우:값` row 리스트.
- **매수/매도 이유는 별도 블록**: 핵심 정보이므로 subtext에 묻히지 않게.
- **등록일 ≠ 거래일이면 명시**: 거래일 섹션 헤더 + 카드 내 `등록 YYYY.MM.DD` 표기.

### 날짜 섹션 헤더

```dart
// 거래일 기준 내림차순 정렬 후 날짜별 그룹핑
Padding(
  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
  child: Row(children: [
    Text(
      '거래일 ${DateFormat('yyyy.MM.dd').format(tradeDate)}',
      style: GoogleFonts.inter(
        color: cs.onSurface.withValues(alpha: 0.55),
        fontSize: 13, fontWeight: FontWeight.w700),
    ),
    const SizedBox(width: 10),
    Expanded(child: Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.08))),
  ]),
)
```

### 종목 카드 구조

```
┌─────────────────────────────────┐
│ 종목명 (19px w800)  [KOSPI] [매수] │  ← 종목명 Primary
│ 267250 · 등록 2026.04.15         │  ← 등록일 ≠ 거래일이면 표시
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 매수 이유                    │ │  ← accent 좌측 border 블록
│ │ "좋아보임"  (14px, 본문)     │ │
│ └─────────────────────────────┘ │
│                                 │
│ 평가손익  +₩110,000  [+2.12%]   │  ← Hero 수치 (24px mono)
│─────────────────────────────────│
│ 매수가          ₩259,000        │  ← row 리스트
│ 현재가          ₩264,500 (빨강) │
│ 매수수량/잔량   50주 / 20주     │
│ 원금            ₩5,180,000      │
│ 평가금액        ₩5,290,000      │
│─────────────────────────────────│
│ [매도 1건]  총 실현손익  +₩930K │  ← 매도 이력 (bg.tertiary)
│   04/21 · 30주 · ₩290,000  +₩930K│
└─────────────────────────────────┘
```

### 매수 이유 블록

```dart
Container(
  margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: cs.onSurface.withValues(alpha: 0.05),
    borderRadius: BorderRadius.circular(10),
    border: Border(left: BorderSide(color: const Color(0xFF10B981), width: 3)),
  ),
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('매수 이유', style: GoogleFonts.inter(
      color: const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600)),
    const SizedBox(height: 5),
    Text(pick.reason, style: GoogleFonts.inter(
      color: cs.onSurface, fontSize: 14, height: 1.6)),
  ]),
)
```

### 세부 수치 Row 리스트

```dart
// ❌ 이전: 2×N 그리드 (셀 border, GridView)
// ✅ 개선: 좌:라벨 우:값 row + Divider
Column(children: [
  for (final item in details)
    Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(item.label, style: GoogleFonts.inter(
              color: cs.onSurface.withValues(alpha: 0.55), fontSize: 13)),
            Text(item.value, style: GoogleFonts.robotoMono(
              color: item.color ?? cs.onSurface, fontSize: 13,
              fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      Divider(height: 1, thickness: 1, color: cs.onSurface.withValues(alpha: 0.06)),
    ]),
])
```

### 평가손익 Hero 수치

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('평가손익', style: GoogleFonts.inter(
          color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
        const SizedBox(height: 3),
        Text(
          '${isPositive ? '+' : ''}${formatter.format(evalProfit.toInt())}',
          style: GoogleFonts.robotoMono(
            color: isPositive ? _kUpColor : _kDownColor,
            fontSize: 24, fontWeight: FontWeight.w700),
        ),
      ]),
      const SizedBox(width: 10),
      // 수익률 pill
      Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (isPositive ? _kUpColor : _kDownColor).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          '${isPositive ? '+' : ''}${returnRate.toStringAsFixed(2)}%',
          style: GoogleFonts.robotoMono(
            color: isPositive ? _kUpColor : _kDownColor,
            fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  ),
)
```

---

## 13. 보유 포지션 요약 (매매일지 상단) — ✅ 신규

> 도넛 차트로 종목별 비중 시각화 + 총 평가금액·손익 표시

### 구조

```
┌──────────────────────────────────────────┐
│ [보유 2]  내 포지션                    ⌄  │  ← 탭으로 펼치기/접기
│──────────────────────────────────────────│
│  [도넛차트 110px]   ● 종목A  71%          │  ← 차트 + 범례 행
│                    ₩5,290,000           │
│                    ● 종목B  29%          │
│                    ₩2,116,000           │
│──────────────────────────────────────────│
│  총 평가금액        │  평가손익            │  ← 별도 행 (border-top)
│  ₩7,406,000       │  +₩170,000          │
│                   │  +2.35%             │
└──────────────────────────────────────────┘
```

> - 도넛 차트: **110px** (기존 80px에서 확대)
> - 범례에 종목별 평가금액도 함께 표시
> - 총 평가금액 / 평가손익은 **차트 행과 분리된 별도 행**으로

### 도넛 차트 Flutter 구현

```dart
class _DonutChartPainter extends CustomPainter {
  final List<({Color color, double value})> segments;
  final String centerLabel;
  final String centerValue;

  _DonutChartPainter({
    required this.segments,
    required this.centerLabel,
    required this.centerValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold(0.0, (s, e) => s + e.value);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 10.0;

    double startAngle = -math.pi / 2;  // 12시 방향부터

    for (final seg in segments) {
      final sweepAngle = (seg.value / total) * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
      startAngle += sweepAngle;
    }

    // 중앙 텍스트
    final labelPainter = TextPainter(
      text: TextSpan(text: centerLabel, style: const TextStyle(
        color: Colors.white38, fontSize: 9, fontFamily: 'Pretendard')),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy - labelPainter.height - 2));

    final valuePainter = TextPainter(
      text: TextSpan(text: centerValue, style: const TextStyle(
        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700,
        fontFamily: 'JetBrainsMono')),
      textDirection: TextDirection.ltr,
    )..layout();
    valuePainter.paint(canvas,
      Offset(center.dx - valuePainter.width / 2, center.dy + 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
```

### 보유 요약 카드

```dart
GestureDetector(
  onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
  child: Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: cs.onSurface.withValues(alpha: 0.06)),
    ),
    child: Column(children: [
      // 헤더
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text('보유 ${picks.length}', style: GoogleFonts.inter(
            color: const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Text('내 포지션', style: GoogleFonts.inter(
          color: cs.onSurface, fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        AnimatedRotation(
          turns: _summaryExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.keyboard_arrow_down,
              color: cs.onSurface.withValues(alpha: 0.3)),
        ),
      ]),

      if (_summaryExpanded) ...[
        const SizedBox(height: 14),

        // ✅ 행 1: 도넛 차트(110px) + 범례(종목명+비율+금액)
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
            width: 110, height: 110,
            child: CustomPaint(painter: _DonutChartPainter(
              segments: donutSegments,
              centerLabel: '보유',
              centerValue: '${picks.length}종목',
            )),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: donutSegments.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 8, height: 8,
                      decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(s.label, style: GoogleFonts.inter(
                      color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12),
                      overflow: TextOverflow.ellipsis)),
                    Text('${(s.value / totalValue * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.robotoMono(
                        color: cs.onSurface, fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Text(formatter.format(s.value.toInt()),
                      style: GoogleFonts.robotoMono(
                        color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
                  ),
                ]),
              )).toList(),
            ),
          ),
        ]),

        // ✅ 행 2: 총 평가금액 / 평가손익 — 별도 행
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(
                color: cs.onSurface.withValues(alpha: 0.06))),
          ),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('총 평가금액', style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
              const SizedBox(height: 4),
              Text(formattedTotal, style: GoogleFonts.robotoMono(
                color: cs.onSurface, fontSize: 17, fontWeight: FontWeight.w700)),
            ])),
            Container(width: 1, height: 40,
              color: cs.onSurface.withValues(alpha: 0.06),
              margin: const EdgeInsets.symmetric(horizontal: 16)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('평가손익', style: GoogleFonts.inter(
                color: cs.onSurface.withValues(alpha: 0.38), fontSize: 11)),
              const SizedBox(height: 4),
              Text(formattedProfit, style: GoogleFonts.robotoMono(
                color: isPositive ? _kUpColor : _kDownColor,
                fontSize: 17, fontWeight: FontWeight.w700)),
              Text(formattedRate, style: GoogleFonts.robotoMono(
                color: isPositive ? _kUpColor : _kDownColor, fontSize: 12)),
            ])),
          ]),
        ),
      ],
    ]),
  ),
)
```

---

## 14. 체크리스트 (업데이트)

새 화면 만들 때:

- [ ] 좌우 여백 `20px`
- [ ] 기본은 카드리스(`Padding + Divider`)인지 먼저 검토
- [ ] 카드가 필요하면 `radius.16` + 약한 border만 사용
- [ ] 숫자는 JetBrains Mono
- [ ] 상승/하락 색상 일관성 확인
- [ ] 라이트/다크 모두 확인
- [ ] 버튼은 최하단 고정 or 인라인 — 중간에 붕 뜨지 않게
- [ ] **AppBar에 종목명 표시** (코드만 X)
- [ ] **탭바 indicator — 흰 배경 + 다크 텍스트** (다크 모드 가독성)
- [ ] **PER/PBR은 pill 행으로 분리** (가격 행에 float X)
- [ ] **투표 UI에 비율 바** 추가
- [ ] **공유 등 보조 CTA는 TextButton** (Outline primary 금지)
- [ ] **코멘트는 borderless row** — 아바타 radius 18
- [ ] **매매일지 날짜는 섹션 헤더** — 거래일 내림차순, 카드 내 반복 X
- [ ] **매수/매도 이유는 별도 accent border 블록**
- [ ] **평가손익/수익률은 카드 상단 hero** — 그리드 맨 아래 X
- [ ] 빈 상태(empty state) 처리 있는지
- [ ] 로딩 상태 처리 있는지
