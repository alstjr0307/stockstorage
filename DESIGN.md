# 주식저장소 Design System

> **컨셉: "Calm Finance"**
> 복잡한 금융 정보를 군더더기 없이. 토스처럼 — 보는 순간 이해되고, 쓰는 순간 편하게.
> 여백으로 말하고, 타이포로 계층을 만든다.

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
| `accent` | `#3182F6` | `#4D9BFF` | CTA, 링크, 포커스 |
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
| `type.display` | 28px | 700 | 1.2 | -0.6 | 큰 숫자, 히어로 |
| `type.title1` | 24px | 700 | 1.3 | -0.5 | 페이지 제목 |
| `type.title2` | 20px | 700 | 1.35 | -0.4 | 섹션 제목 |
| `type.title3` | 17px | 600 | 1.4 | -0.3 | 카드 제목 |
| `type.body1` | 16px | 400 | 1.6 | 0 | 본문 |
| `type.body2` | 14px | 400 | 1.6 | 0 | 보조 본문 |
| `type.caption1` | 13px | 500 | 1.4 | 0 | 라벨, 태그 |
| `type.caption2` | 12px | 400 | 1.4 | 0 | 타임스탬프, 힌트 |
| `type.micro` | 11px | 500 | 1.3 | 0 | 배지, 아주 작은 라벨 |
| `type.number.lg` | 32px | 700 | 1.1 | -0.5 | 주가, 총액 (Mono) |
| `type.number.md` | 18px | 600 | 1.3 | -0.3 | 수익률, 변동폭 (Mono) |
| `type.number.sm` | 13px | 500 | 1.4 | 0 | 소형 수치 (Mono) |

### 원칙
- **숫자는 항상 JetBrains Mono.** 자릿수 정렬이 곧 신뢰감.
- weight는 400 / 600 / 700 세 가지만.
- 색으로 강조하지 않고 **size와 weight로 계층** 만들기.

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

- 강조 색 accent bar 없음 — **여백과 타이포로 계층 표현**
- 카드 안에 또 카드 넣지 않기

---

### Button

**Primary**
```dart
FilledButton(
  style: FilledButton.styleFrom(
    backgroundColor: accent,        // #3182F6
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

```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(label,
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
  ),
)
```

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

```dart
TabBar(
  labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  unselectedLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
  labelColor: label.primary,
  unselectedLabelColor: label.tertiary,
  indicatorColor: label.primary,
  indicatorWeight: 2,
  indicatorSize: TabBarIndicatorSize.label,
  dividerColor: Colors.transparent,
)
```

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

---

## 10. 토스와 다른 점

주식 앱이라 토스와 다르게 가져갈 부분:

| 항목 | 토스 | 주식저장소 |
|---|---|---|
| 정보 밀도 | 낮음 (1화면 1정보) | 중간 (차트+수치 공존) |
| 색 사용 | 거의 흑백 | 지수별 색상 + 상승/하락색 |
| 숫자 폰트 | 일반 폰트 | JetBrains Mono |
| 차트 | 없음 | 핵심 기능 |

---

## 11. 체크리스트

새 화면 만들 때:

- [ ] 좌우 여백 `20px`
- [ ] 카드 `radius.16` + 그림자 or border
- [ ] 숫자는 JetBrains Mono
- [ ] 상승/하락 색상 일관성 확인
- [ ] 라이트/다크 모두 확인
- [ ] 버튼은 최하단 고정 or 인라인 — 중간에 붕 뜨지 않게
- [ ] 빈 상태(empty state) 처리 있는지
- [ ] 로딩 상태 처리 있는지
