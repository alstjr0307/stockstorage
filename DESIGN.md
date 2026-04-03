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
> 기존 초록/빨강 유지하려면 `up: #4ADE80`, `down: #F87171`로 교체.

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

> Pretendard는 한국어 최적화 폰트. 토스가 사용하는 폰트와 동일 계열.

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
- weight는 400 / 600 / 700 / 800 네 가지. 800은 display·히어로에만.
- 색으로 강조하지 않고 **size와 weight로 계층** 만들기.
- **title2(22px)** 를 카드 헤드라인 기본으로. 17px title3는 너무 작다.

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

**라운드는 일관되게. 섞지 않는다.**

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

토스처럼 **그림자 최소화.** 배경색 차이와 border로 깊이 표현.

```dart
// 카드 (라이트)
BoxDecoration(
  color: Color(0xFFFFFFFF),
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
      color: Color(0x0D000000), // 5% black
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
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

### Card

```dart
Container(
  padding: EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: bg.secondary,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [...],  // 라이트만
  ),
  child: content,
)
```

- **기본값은 카드리스.** 카드는 예외 상황에서만 사용.
- 카드가 꼭 필요할 때도 1중 컨테이너만 사용 (카드 안 카드 금지).
- 강조 색 accent bar 없음 — **여백과 타이포로 계층 표현**.

### Cardless First (기본 원칙)

- 리스트/피드/지수/커뮤니티형 화면은 카드 컨테이너 없이 `Padding + Divider`로 구성.
- 정보 계층은 `title 크기 + weight + 여백`으로 만든다.
- 시각적 분리는 보더보다 **세로 리듬(간격)**을 우선한다.

**Borderless 콘텐츠 행 (토스 커뮤니티 스타일)**
```dart
// 카드 컨테이너 없이, 패딩과 Divider만으로
Padding(
  padding: EdgeInsets.fromLTRB(20, 20, 20, 20),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 메타 정보 (날짜, 카테고리)
      Text(meta, style: type.caption1.copyWith(color: label.tertiary)),
      SizedBox(height: 8),
      // 제목 — 크고 bold
      Text(title, style: type.title2),   // 22px w700
      SizedBox(height: 6),
      // 본문 프리뷰
      Text(preview, maxLines: 2, style: type.body2.copyWith(color: label.secondary)),
    ],
  ),
)
```

---

### Button

**Primary**
```dart
FilledButton(
  style: FilledButton.styleFrom(
    backgroundColor: accent,        // #10B981
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    minimumSize: Size(double.infinity, 52),
    textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    elevation: 0,
  ),
)
```

**Secondary**
```dart
OutlinedButton(
  style: OutlinedButton.styleFrom(
    foregroundColor: label.primary,
    side: BorderSide(color: border),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    minimumSize: Size(double.infinity, 52),
    backgroundColor: bg.secondary,
    elevation: 0,
  ),
)
```

**텍스트 버튼**
```dart
TextButton(
  style: TextButton.styleFrom(
    foregroundColor: accent,
    textStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  ),
)
```

---

### Input Field

```dart
TextField(
  decoration: InputDecoration(
    filled: true,
    fillColor: bg.tertiary,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: accent, width: 1.5),
    ),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: TextStyle(color: label.tertiary, fontSize: 15),
  ),
  style: TextStyle(fontSize: 15, color: label.primary),
)
```

---

### List Item (토스 스타일)

```dart
// 구분선 없이 여백으로 구분
Padding(
  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  child: Row(
    children: [
      // 아이콘 또는 썸네일
      Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: bg.tertiary,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: type.title3),
            SizedBox(height: 2),
            Text(subtitle, style: type.caption1.copyWith(color: label.secondary)),
          ],
        ),
      ),
      // 우측 값
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: type.number.md),
          Text(change, style: type.caption1.copyWith(color: up or down)),
        ],
      ),
    ],
  ),
)
```

---

### Badge / Tag

**Pill Badge (기본 — 토스 스타일)**
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(9999),   // pill
  ),
  child: Text(label,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
  ),
)
```

**Chip (텍스트 필터, 카테고리)**
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: isSelected ? accent.withValues(alpha: 0.12) : bg.tertiary,
    borderRadius: BorderRadius.circular(9999),
    border: isSelected ? Border.all(color: accent.withValues(alpha: 0.3)) : null,
  ),
  child: Text(label,
    style: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: isSelected ? accent : label.secondary,
    ),
  ),
)
```

> borderRadius 4는 쓰지 않는다. 최소 6, 기본 pill(9999).

---

### Bottom Sheet

```dart
showModalBottomSheet(
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (_) => Container(
    decoration: BoxDecoration(
      color: bg.secondary,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Column(children: [
      // 핸들
      Container(
        margin: EdgeInsets.only(top: 10, bottom: 6),
        width: 32, height: 3,
        decoration: BoxDecoration(
          color: border,
          borderRadius: BorderRadius.circular(9999),
        ),
      ),
      // 타이틀
      Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Text(title, style: type.title2),
      ),
      content,
    ]),
  ),
)
```

---

### Tab Bar

두 가지 스타일 중 선택:

**① Pill 탭 (토스 커뮤니티 스타일 — 트렌디)**
```dart
TabBar(
  labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
  labelColor: label.primary,
  unselectedLabelColor: label.tertiary,
  dividerColor: Colors.transparent,
  indicator: BoxDecoration(
    color: bg.tertiary,                      // 선택된 탭 배경
    borderRadius: BorderRadius.circular(9999),
  ),
  indicatorSize: TabBarIndicatorSize.tab,
  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
  tabAlignment: TabAlignment.start,           // 좌측 정렬 (콘텐츠 탭)
)
```

**② 언더라인 탭 (현재 스타일 — 클래식)**
```dart
TabBar(
  labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
  labelColor: label.primary,
  unselectedLabelColor: label.tertiary,
  indicatorColor: label.primary,
  indicatorWeight: 2,
  indicatorSize: TabBarIndicatorSize.label,
  dividerColor: border,
)
```

> 시황/지표 탭 → pill 탭 권장. 페이지 수가 많을수록 언더라인이 스크롤하기 좋음.

---

### Toast / Snackbar

```dart
SnackBar(
  content: Text(message, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
  backgroundColor: Color(0xFF191F28),   // 라이트/다크 공통
  behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  margin: EdgeInsets.fromLTRB(20, 0, 20, 24),
  duration: Duration(seconds: 3),
  elevation: 0,
)
```

---

## 7. Data Display

### 주가 / 수익률 표시 규칙

```
+12.34%  →  color: up,   앞에 + 명시
-5.67%   →  color: down, 앞에 - 자동
0.00%    →  color: label.secondary
```

- 폰트: 항상 JetBrains Mono
- 소수점: 주가 2자리, 수익률 2자리, 퍼센트 1자리

### 금액 포맷

| 단위 | 표시 | 예시 |
|---|---|---|
| 원화 | `₩#,###` | ₩1,234,500 |
| 달러 | `$#,##0.00` | $123.45 |
| 억 이상 | `#.#억` | 12.3억 |
| 조 이상 | `#.#조` | 1.2조 |

---

## 8. Divider

토스는 **줄 구분선 거의 안 씀.** 여백으로 구분.

꼭 필요할 때만:
```dart
Divider(height: 1, thickness: 1, color: border)
// 또는 섹션 구분용 두꺼운 바
Container(height: 8, color: bg.tertiary)  // 토스 스타일 섹션 구분
```

---

## 9. Motion

| 상황 | Duration | Curve |
|---|---|---|
| 버튼 피드백 | 100ms | linear |
| 화면 전환 | 250ms | easeOutCubic |
| 바텀시트 | 300ms | easeOutQuart |
| 숫자 카운팅 | 600ms | easeOut |

- **불필요한 애니메이션 없음.** 전환은 빠르게.
- 숫자 변동 시 카운팅 애니메이션은 신뢰감 UP.

### 현재 앱 적용 규칙 (Stagger Reveal)

- 초기 진입 시 콘텐츠는 `위 -> 아래` 순서로 짧게 나타난다.
- 기본 단위: `fade + translateY(12px -> 0)` 조합.
- 첫 블록 `delay: 40ms`, 이후 블록은 `+70~100ms` 간격으로 스태거 적용.
- 한 화면 총 등장 시간은 **600ms 내외**로 제한.
- 차트/리스트는 데이터 로딩 이후 한 번만 reveal하고, 스크롤 중 재실행 금지.

```dart
// 예시: 화면 블록 단위 reveal
_StaggerReveal(
  delay: const Duration(milliseconds: 40),
  child: header,
)
_StaggerReveal(
  delay: const Duration(milliseconds: 120),
  child: chart,
)
```

### 성능 가이드 (버벅임 방지)

- 한 화면에서 동시 애니메이션 위젯 수를 6~8개 이하로 유지.
- 무거운 위젯(차트, 긴 리스트)은 부모 애니메이션 1개만 적용.
- 정적 UI는 `const` 우선 사용.
- 차트 영역은 필요 시 `RepaintBoundary`로 분리.
- `AnimatedOpacity` 중첩/과도한 blur/shadow는 지양.

---

## 10. 토스와 다른 점

주식 앱이라 토스와 다르게 가져갈 부분:

| 항목 | 토스 | 주식저장소 |
|---|---|---|
| 정보 밀도 | 낮음 (1화면 1정보) | 중간 (차트+수치 공존) |
| 색 사용 | 거의 흑백 | 지수별 색상 + 상승/하락색 |
| 숫자 폰트 | 일반 폰트 | JetBrains Mono |
| 차트 | 없음 | 핵심 기능 |
| 탭 스타일 | Pill 탭 (커뮤니티) | Pill 탭 권장 |
| 타이포 크기 | 크고 bold (22-24px 헤드) | title2(22px) 적극 활용 |

### 토스에서 직접 가져올 것들 ✅
- **Pill 탭** — 언더라인보다 훨씬 트렌디
- **큰 제목** — 카드 유무와 무관하게 타이틀 22px w700, 숫자 34px
- **배지 pill화** — borderRadius 4 → 9999
- **카드리스 피드** — 목록/지수/커뮤니티는 카드보다 row 중심
- **메타 먼저** — 날짜/카테고리 위에, 제목 아래

---

## 11. 커뮤니티 피드 (토스 자유게시판 스타일)

> 레퍼런스: 토스 증권 커뮤니티 자유게시판 피드
> 카드 컨테이너 없이, 아바타·제목·인터랙션 바가 세로로 흐르는 소셜 피드 레이아웃.

### 핵심 원칙

- **카드 테두리 없음.** 포스트 간 구분은 가로 Divider 1px로만.
- **작성자 정보는 상단.** 아바타 + 이름 + 팔로우 버튼 → 타임스탬프 + 맥락 한 줄.
- **제목은 크고 bold.** 17–18px w700, 본문은 그 아래 2줄 preview.
- **인터랙션 바는 하단.** 좋아요 / 댓글 / 리포스트 / 공유 아이콘 행.

### 포스트 아이템 구조

```
┌────────────────────────────────────────────┐  ← 패딩 20px 좌우
│ [Avatar 40px]  닉네임  뱃지?   [팔로우]     │  ← 작성자 행
│                N시간 전 · 종목에 남긴 글      │  ← 메타 (caption2, tertiary)
│                                            │
│ 제목 (title3 17px w700)                    │  ← 제목
│ 본문 프리뷰 maxLines:2 (body2, secondary)  │
│ [미디어/링크 프리뷰 — 있을 때만]             │
│                                            │
│ ♡ 27   💬 22   ↻   ⬆                      │  ← 인터랙션 바
└────────────────────────────────────────────┘
────────────────────────────────────────────  ← Divider 1px
```

### Flutter 구현 패턴

```dart
// 포스트 아이템 — 카드 컨테이너 없이 패딩만
Column(children: [
  Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ① 작성자 행
      Row(children: [
        CircleAvatar(radius: 20, ...),          // 40px
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(nickname, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (isVerified) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 14, color: Color(0xFF10B981)),
              ],
            ]),
            Text(
              '$timeAgo · $stockName에 남긴 글',
              style: TextStyle(fontSize: 12, color: label.tertiary),
            ),
          ]),
        ),
        // 팔로우 버튼 (내 글이 아닐 때만)
        if (!isOwn)
          TextButton(
            onPressed: onFollow,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF10B981),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: const Text('팔로우'),
          ),
      ]),

      const SizedBox(height: 12),

      // ② 제목
      Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),

      // ③ 본문 프리뷰 (4–5줄 + 더 보기)
      if (content.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(content,
            maxLines: 4, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: label.secondary, height: 1.6)),
        // 실제로 4줄 넘길 때 "더 보기" 표시
        GestureDetector(
          onTap: onExpandContent,
          child: Text('더 보기', style: TextStyle(fontSize: 14, color: accent, fontWeight: FontWeight.w500)),
        ),
      ],

      // ④ 미디어 (있을 때만)
      if (imageUrl != null) ...[
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(imageUrl!, fit: BoxFit.cover),
        ),
      ],

      // ⑤ 링크 프리뷰 카드 (있을 때만)
      if (linkPreview != null) ...[
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: bg.tertiary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Row(children: [
            // 썸네일
            if (linkPreview!.imageUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                child: Image.network(linkPreview!.imageUrl!, width: 72, height: 72, fit: BoxFit.cover),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(linkPreview!.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(linkPreview!.domain,
                      style: TextStyle(fontSize: 11, color: label.tertiary)),
                ]),
              ),
            ),
          ]),
        ),
      ],

      const SizedBox(height: 12),

      // ⑥ 인터랙션 바
      Row(children: [
        _InteractionBtn(icon: isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? Colors.redAccent : label.tertiary, count: likeCount, onTap: onLike),
        const SizedBox(width: 16),
        _InteractionBtn(icon: Icons.chat_bubble_outline_rounded,
            color: label.tertiary, count: commentCount, onTap: onComment),
        const SizedBox(width: 16),
        _InteractionBtn(icon: Icons.repeat_rounded, color: label.tertiary, onTap: onRepost),
        const Spacer(),
        _InteractionBtn(icon: Icons.ios_share_rounded, color: label.tertiary, onTap: onShare),
      ]),

    ]),
  ),
  Divider(height: 1, thickness: 1, color: border),  // 포스트 간 구분
])
```

### 인터랙션 버튼 패턴

```dart
class _InteractionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ]),
    );
  }
}
```

### 현재 앱 대비 달라지는 것

| 항목 | 현재 (bordered card) | 토스 스타일 |
|---|---|---|
| 컨테이너 | `Container` + `Border.all` + `radius 16` | 패딩만, 테두리 없음 |
| 구분선 | 카드 간 `margin 12` | `Divider` 1px |
| 작성자 위치 | **하단** (divider 아래) | **상단** (제목 위) |
| 아바타 크기 | `radius 11` (22px) | `radius 20` (40px) |
| 팔로우 버튼 | 없음 | 텍스트 버튼, accent 색 |
| 인터랙션 | 좋아요만 (하단 우측) | 좋아요·댓글·리포스트·공유 한 행 |
| 시간 표기 | `MM.dd HH:mm` | `N시간 전` (상대 시간) |
| 본문 줄 수 | maxLines 2 | maxLines 4–5 + "더 보기" 링크 |

### "더 보기" 패턴

```dart
// 본문이 4줄 이상일 때 "더 보기" 인라인 표시
// isOverflow는 LayoutBuilder 또는 TextPainter로 실제 줄 넘침 감지
if (isExpanded)
  Text(content, style: body2)
else
  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(content, maxLines: 4, overflow: TextOverflow.ellipsis, style: body2),
    if (isOverflow)
      GestureDetector(
        onTap: () => setState(() => isExpanded = true),
        child: Text('더 보기', style: TextStyle(fontSize: 14, color: accent, fontWeight: FontWeight.w500)),
      ),
  ])
```

---

## 12. 순위 리스트 (토스 발견 탭 스타일)

> 레퍼런스: 토스 증권 발견 탭 "실시간 차트" 섹션
> 거래대금·거래량·급상승 등 필터 탭 + 로고 + 순위번호 + 가격/등락 + 즐겨찾기 한 줄

### 핵심 원칙

- **카드 없음.** 배경 그대로, 행 사이 여백만으로 구분.
- **순위 번호는 accent 색(파란색).** JetBrains Mono, 고정폭 28px 박스.
- **로고는 원형 48px.** 없을 때 이니셜 fallback.
- **가격은 primary, 등락은 상승=빨강/하락=파랑.** (국내 증권 컨벤션)
- **즐겨찾기 하트는 우측 끝 고정.** outline → filled 토글.

### 화면 구조

```
페이지 헤더
─────────────────────────────────────
발견  S&P 500  6,582.69  +0.1%        ← 대제목 32px w800 + 지수 inline (accent/up 색)

[✦ 실시간 이슈  1 미국 3월 고용 반등 –  >]  ← AI 이슈 배너 (accent border glow)

[🇺🇸 해외주식] [🇰🇷 국내주식] [↗ 옵션] [채권] [ETF]  ← 카테고리 칩 수평 스크롤

2일 뒤 이벤트  ISM …  |  나스닥 21,879.18 +0.1%  |  …  ← 이벤트/지수 바 수평 스크롤

실시간 차트                                           ← 섹션 타이틀 22px w800
─────────────────────────────────────
거래대금  거래량  급상승  급하락  인기              ← 언더라인 필터 탭 (좌측 정렬)
─────────────────────────────────────
1  [Samsung]  삼성전자          ♡
              185,800원 +4.1%
2  [Logo]     고려아연          ♡
              1,488,000원 +1.3%
…
```

### 레이아웃 상세

#### 섹션 헤더 (페이지 타이틀 + 인라인 지수)

```dart
Row(children: [
  Text('발견', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
  const SizedBox(width: 10),
  Text('S&P 500', style: TextStyle(fontSize: 13, color: label.secondary)),
  const SizedBox(width: 6),
  Text('6,582.69', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
      color: up, fontFamily: 'JetBrainsMono')),
  const SizedBox(width: 4),
  Text('+0.1%', style: TextStyle(fontSize: 13, color: up, fontFamily: 'JetBrainsMono')),
])
```

#### AI 실시간 이슈 배너

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 1.2),
    // 미묘한 glow — 다크 모드에서만
    boxShadow: isDark ? [
      BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.12), blurRadius: 12),
    ] : null,
  ),
  child: Row(children: [
    Icon(Icons.auto_awesome, size: 14, color: const Color(0xFF10B981)),
    const SizedBox(width: 8),
    Text('실시간 이슈', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF10B981))),
    const SizedBox(width: 10),
    Expanded(child: Text(issueText, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
    Icon(Icons.chevron_right, size: 18, color: label.tertiary),
  ]),
)
```

#### 카테고리 칩 (수평 스크롤)

```dart
SizedBox(
  height: 80,
  child: ListView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    children: categories.map((cat) => Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: bg.secondary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: cat.icon),  // 국기 이모지 or Icon
        ),
        const SizedBox(height: 6),
        Text(cat.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    )).toList(),
  ),
)
```

#### 필터 탭 (언더라인, 좌측 정렬)

```dart
TabBar(
  isScrollable: true,
  tabAlignment: TabAlignment.start,
  labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  labelColor: label.primary,
  unselectedLabelColor: label.tertiary,
  indicatorColor: label.primary,
  indicatorWeight: 2,
  indicatorSize: TabBarIndicatorSize.label,
  dividerColor: Colors.transparent,
  padding: const EdgeInsets.symmetric(horizontal: 20),
  tabs: [...],
)
```

#### 순위 리스트 아이템

```
[rank 28px]  [logo 48px]  [name + price]  …  [♡ 24px]
```

```dart
Padding(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  child: Row(children: [

    // ① 순위 번호
    SizedBox(
      width: 28,
      child: Text(
        '$rank',
        style: GoogleFonts.robotoMono(
          fontSize: 15, fontWeight: FontWeight.w700,
          color: const Color(0xFF10B981),  // accent
        ),
      ),
    ),

    const SizedBox(width: 12),

    // ② 종목 로고
    CircleAvatar(
      radius: 24,                     // 48px
      backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
      backgroundColor: bg.tertiary,
      child: logoUrl == null
          ? Text(name[0], style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))
          : null,
    ),

    const SizedBox(width: 12),

    // ③ 종목명 + 가격
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Row(children: [
          Text(
            priceStr,                 // "185,800원"
            style: GoogleFonts.robotoMono(fontSize: 13, fontWeight: FontWeight.w500, color: label.primary),
          ),
          const SizedBox(width: 6),
          Text(
            changeStr,                // "+4.1%"
            style: GoogleFonts.robotoMono(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: change > 0 ? up : change < 0 ? down : label.secondary,
            ),
          ),
        ]),
      ]),
    ),

    // ④ 즐겨찾기
    GestureDetector(
      onTap: onFavorite,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          isFavorite ? Icons.favorite : Icons.favorite_border,
          size: 22,
          color: isFavorite ? Colors.redAccent : label.tertiary,
        ),
      ),
    ),

  ]),
),
```

> 행 사이 구분선은 `Divider(height: 1, indent: 60, color: border)` — 로고 왼쪽은 건너뜀.

### 레이아웃 요약표

| 요소 | 스펙 |
|---|---|
| 순위 번호 색 | `accent` (#10B981) |
| 순위 번호 폰트 | JetBrains Mono / Roboto Mono, w700 |
| 순위 번호 폭 | 고정 28px |
| 로고 크기 | 48px (radius 24) |
| 종목명 | 15px w700 |
| 가격 | Mono 13px w500, label.primary |
| 등락 | Mono 13px w600, up/down 색 |
| 하트 아이콘 | 22px, outline/filled 토글 |
| 행 패딩 | 수직 12px, 좌우 20px |
| 구분선 | Divider 1px, indent 60 (로고 위치까지) |

---

## 14. 체크리스트

새 화면 만들 때:

- [ ] 좌우 여백 `20px`
- [ ] 기본은 카드리스(`Padding + Divider`)인지 먼저 검토
- [ ] 카드가 필요하면 `radius.16` + 약한 border만 사용
- [ ] 숫자는 JetBrains Mono
- [ ] 상승/하락 색상 일관성 확인
- [ ] 라이트/다크 모두 확인
- [ ] 버튼은 최하단 고정 or 인라인 — 중간에 붕 뜨지 않게
- [ ] 빈 상태(empty state) 처리 있는지
- [ ] 로딩 상태 처리 있는지
