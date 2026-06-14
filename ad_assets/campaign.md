# 주식저장소 — CPI 설치형 광고 등록 양식

리워드 매체(캐시워크/타임스프레드 등) 7개 매체 노출 기준.

---

## 1. 이미지 (1200 x 600, PNG, 150KB 이하)
- 시안 파일: `ad_assets/banner_1200x600.svg`
- PNG 변환 필요. 변환 방법 (택1):
  - Figma/Illustrator로 SVG 열어서 1200x600 PNG export
  - 온라인 변환기: cloudconvert.com 등에 SVG 업로드 → PNG (1200x600)
  - 명령줄: `npx svgexport ad_assets/banner_1200x600.svg ad_assets/banner_1200x600.png 1200:600`
- 150KB 초과 시 tinypng.com 등으로 압축

## 2. 캠페인명 (최대 20자, 띄어쓰기 포함)

후보 3종 — 매체 톤에 맞춰 선택:

| # | 카피 | 글자수 | 톤 |
|---|---|---|---|
| A | AI가 골라주는 오늘의 주식 | 14 | 정공법 (기능 소구) |
| B | 출석만 해도 AI 주식분석 무료 | 17 | 리워드 매체 친화 (행동 유도) |
| C | 주식저장소 - 무료 AI 종목분석 | 16 | 브랜드+기능 |

**추천: B** — 리워드 매체 사용자 동선(출석 → 리워드)과 앱의 출석 미션 기능이 일치해서 클릭율 유리.

## 3. 캠페인 소개 및 참여방법, 주의사항

```
[주식저장소]
AI가 한국·미국 주식을 매일 분석해드립니다.

✓ 종목별 AI 종합 점수 & 매수/매도 시그널
✓ 매매일지로 내 투자 복기
✓ 관심종목 실시간 시세 알림
✓ 매일 출석 시 무료 AI 분석권 지급

[설치형 캐시 지급 방법]
1. 아래의 '참여하기' 버튼을 누른다
2. 링크를 타고 이동 후 앱을 설치한다
3. 설치 완료 후 앱을 1회 이상 실행한다
4. 이 화면으로 돌아와 '적립 요청' 버튼을 누른다
5. 버튼이 '참여 완료'로 바뀐 것을 확인한다

[유의사항]
1. 참여 대상: 본 이벤트 페이지를 통해 다운로드한 신규 사용자
2. 신규 사용자에 한하여 제공됩니다
3. 동일 기기 중복 참여 불가
4. 설치 후 일정 시간 내 미실행 시 적립이 취소될 수 있습니다
5. 본 광고는 투자 권유가 아니며, 모든 투자 판단과 책임은 본인에게 있습니다
```

> **법무 한 줄 추천**: 마지막 투자 권유 부인 문구는 반드시 포함 (금융 관련 앱이라 매체 심의에서 걸릴 가능성 있음).

## 4. 랜딩 URL
- Android Play Store: `https://play.google.com/store/apps/details?id=www.stockstorage.stockdiary`
- iOS App Store: (App Store ID 확인 후 입력 — `https://apps.apple.com/app/idXXXXXXXXX`)

## 5. 앱 식별자

| OS | 값 |
|---|---|
| AOS package name | `www.stockstorage.stockdiary` |
| iOS URL scheme | (현재 앱 전용 URL scheme 미설정 — Google/Kakao SDK용만 있음. CPI 트래킹 SDK 안내에 맞춰 신규 scheme 발급 필요. 임시 후보: `stockstorage://`) |

> **iOS scheme 액션 아이템**: 매체사가 요구하는 형식이 `xxx://`인데, 현 `ios/Runner/Info.plist`에는 앱 전용 scheme이 없음. 광고 트래킹용으로 `stockstorage://`를 Info.plist의 `CFBundleURLSchemes`에 추가해서 다음 빌드에 포함시켜야 적립 확인이 가능합니다.

## 6. 광고필수항목 (보험심의필)
필수 값 X — 해당 없음 (주식 추천 앱은 보험 심의 대상 아님)

## 7. 세금계산서 / 구글 메일
- 세금계산서 발행 메일: (사업자 등록증 + 메일 전달)
- 리포트 확인용 구글 메일: alswp26@gmail.com (advertiser.xarvis.kr 로그인용)

---

## 추가 권장 사항

- **디타겟팅 가능**: 기존 설치자 제외하려면 ADID/IDFA 리스트 매체사에 별도 전달
- **CPI vs 구글 콘솔 지표 차이**: 매체사 리포트와 GA/Play Console 지표가 다를 수 있음 (참고용)
- **노출 매체**: 캐시워크, 타임스프레드 등 약 7개 동시 노출

