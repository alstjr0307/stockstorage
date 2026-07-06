# 주식저장소 Flutter 웹 빌드 계획

작성일: 2026-07-05

## 0. 목표 / 범위

기존 Flutter 앱(`stockstorage`)의 Dart 코드를 재사용해서 **브라우저에서 돌아가는 축소판 웹 버전**을 만든다.
앱의 모든 기능을 옮기지 않고, 아래 8개만 웹에 노출한다.

| # | 웹에 넣을 기능 | 재사용할 기존 화면 |
|---|---|---|
| 1 | AI 종목분석 | `StockAiAnalysisListScreen` + `StockAiAnalysisResultScreen` (+ quota/gate) |
| 2 | 추천주 | `home_screen._buildStockPicksPage` (독립 페이지로 분리) |
| 3 | 자유게시판 | `CommunityScreen` + `PostDetailScreen` + `WritePostScreen` |
| 4 | 시황분석글 | `MarketAnalysisScreen` + `MarketAnalysisDetailScreen` + `WriteMarketAnalysisScreen` |
| 5 | 코스피/코스닥 야간선물 | `NightFuturesChartScreen` + home 야간선물 섹션 |
| 6 | 실시간 지수 | home 실시간 시장 섹션 + `IndexDetailScreen` |
| 7 | 경제 캘린더 | `CalendarScreen` |
| 8 | 시장심리지표 | `MarketSentimentScreen` |

**웹에서 뺄 것:** 매매일지/일지차트, 관심종목/포트폴리오, 종목검색·종목상세·종목비교, 리더보드, 구독 결제, 알림설정/이력, 온보딩, 어드민, 광고, 프로필 일부.

백엔드(Firebase: auth / firestore / functions / storage)는 그대로 공유한다. 새로 만들 필요 없음.

---

## 1. 아키텍처 결정

### 1-1. 단일 코드베이스 + 웹 타겟 추가
별도 React/Next 프론트를 만들지 않는다. 기존 `lib/` 코드를 재사용하고 `flutter build web` 대상만 추가한다.
- 장점: 화면·로직·모델·Firestore 스키마 100% 재사용, 유지보수 1벌.
- 트레이드오프: CanvasKit 렌더라 SEO는 사실상 안 됨 → **웹의 목적은 "기존/신규 유저가 PC 브라우저에서 사용"**이지 검색 유입이 아님. (검색 유입이 목표가 되면 그때 별도 SSR 웹을 검토)

### 1-2. 웹 전용 네비게이션 셸
모바일 `home_screen.dart`(2600줄, 매매일지/관심종목 탭 포함)를 그대로 쓰지 않고, **웹 전용 셸**을 새로 만든다.
- `lib/web/web_shell.dart` — 데스크탑 레이아웃(좌측/상단 네비 + 넓은 본문). 위 8개 기능만 라우팅.
- 기존 화면 위젯들은 그대로 `import`해서 본문에 끼워 넣음(화면 재작성 X).
- 진입 분기: `main.dart`에서 `kIsWeb`이면 `WebShell`, 아니면 기존 앱 홈.

### 1-3. CORS 처리 = onCall 프록시 (핵심)
브라우저는 `finance.naver.com` / Yahoo로의 직접 `http` 호출을 CORS로 차단한다.
→ **Firebase Functions `onCall`** 로 중계한다. `onCall`은 Firebase SDK로 호출돼 CORS가 발생하지 않고, 웹에서 바로 동작한다.

이미 이 패턴이 존재함 (재사용/확장):
- `getKisDomesticQuote` (onCall) — 국내 시세
- `getKospiNightFutures` (onCall) — 야간선물 (웹 그대로 OK)
- `getServerTime` (onCall)

`stock_price_service`에서 아직 직접 `http`로 때리는 경로(예: `polling.finance.naver.com/api/realtime/domestic/index/...`, Yahoo chart/search)만 골라, `kIsWeb`일 때 대응 `onCall` 프록시로 우회한다. 모바일은 기존 직접 호출 유지(성능/무변경).

---

## 2. 작업 분해 (Phase)

### Phase A — 웹 컴파일 통과 (아무 기능 없이 빌드만 성공)
1. `main.dart` 네이티브 init을 `kIsWeb` 분기/가드
   - 가드 대상: `KakaoSdk.init`, `MobileAds.initialize`, ATT, FCM 백그라운드 핸들러, `NotificationService`, `FirebaseAppCheck`(웹은 reCAPTCHA provider로 대체 or 스킵), `SubscriptionService.initialize`, `DeepLinkService`.
2. `dart:io` 제거 — 웹에서 컴파일 깨는 6개 화면 대응
   - 대상: `market_analysis_screen`, `market_sentiment_screen`, `night_futures_chart_screen`, `stock_ai_analysis_result_screen`, `write_market_analysis_screen`, `portfolio/stock_detail`(웹 제외 화면이면 라우팅에서만 빼도 됨).
   - 방식: 조건부 import 스텁 (`io_stub.dart` / `io_real.dart`) 또는 `image_picker`의 `XFile.bytes` 기반으로 `File` 사용부 교체.
3. 네이티브 전용 서비스 웹 스텁
   - `ad_service` → 웹에서 no-op (광고 없음)
   - `subscription_service` → 웹에서 `isPremium=false` 고정, 결제 호출 no-op
   - `notification_service` / `fcm_direct_service` → 웹 no-op
   - `analytics_service.setAdvertiserTracking` → 웹 no-op
   - 로그인: **웹은 카카오 + 구글 + 이메일만** (애플 로그인 웹 제외).
     - 구글/이메일: firebase_auth 웹 그대로 (구글 웹 클라이언트ID 설정 필요).
     - 카카오: `kakao_flutter_sdk_user`는 웹 지원되므로 `KakaoSdk.init`에 **javascriptAppKey** 추가 + `web/index.html`에 Kakao JS SDK `<script>` 로드. 로그인 콜백은 기존 `kakaoAuthCode`/`createKakaoCustomToken` onCall 재사용.
4. `flutter build web` 성공 확인.

### Phase B — 웹 셸 + 기능 연결
5. `lib/web/web_shell.dart` 작성 (8개 기능 네비 + 데스크탑 레이아웃)
6. 각 기능 화면을 셸 본문에 연결. `추천주`는 `_buildStockPicksPage`를 독립 위젯으로 추출.
7. AI 게이트 웹 경로: 광고 게이트 스킵, 로그인 유저 무료 쿼터만 적용(프리미엄 결제 없음).

### Phase C — 실시간 데이터 (CORS 프록시)
8. `stock_price_service`의 직접 http 경로 감사 → 웹 필요분 목록화.
9. `functions/`에 부족한 `onCall` 프록시 추가 (실시간 지수 폴링 등). 기존 `getKospiNightFutures` 등은 재사용.
10. `stock_price_service`에 `kIsWeb` 분기: 웹=onCall, 모바일=기존 직접호출.
11. 실시간 지수/야간선물 웹에서 표시 확인.

### Phase D — 마감
12. 반응형/데스크탑 레이아웃 다듬기, 다크모드 확인.
13. `web/index.html`·manifest·favicon 정리(PWA), Firebase Hosting 배포 설정.
14. 로그인 리다이렉트(구글/애플 웹), 딥링크→웹 라우팅 점검.

---

## 3. 네이티브 플러그인 웹 대응표

| 플러그인 | 웹 | 웹 처리 |
|---|---|---|
| `firebase_core/auth/firestore/functions/storage` | ✅ | 그대로 |
| `firebase_analytics` | ✅ | 그대로 |
| `firebase_app_check` | ⚠️ | 웹은 reCAPTCHA provider 또는 스킵 |
| `firebase_messaging` | ⚠️ | 웹 푸시 미사용 → no-op |
| `google_mobile_ads` | ❌ | no-op 스텁 (광고 없음) |
| `purchases_flutter` | ❌ | no-op, `isPremium=false` |
| `app_tracking_transparency` | ❌ | no-op |
| `facebook_app_events` | ❌ | no-op |
| `flutter_local_notifications` | ❌ | no-op |
| `kakao_flutter_sdk_user` | ⚠️ | 웹 JS SDK 별도 / 초기엔 미노출 |
| `sign_in_with_apple` | ⚠️ | 웹 OAuth 리다이렉트 방식 |
| `google_sign_in` | ✅ | 웹 클라이언트ID 설정 필요 |
| `image_picker` | ✅ | 웹은 bytes 기반 |
| `fl_chart`, `url_launcher`, `shared_preferences`, `http`, `web_socket_channel`, `intl`, `timeago` | ✅ | 그대로 |

---

## 4. 확정된 정책 / 남은 리스크

### 확정
- **로그인 (웹):** 카카오 + 구글 + 이메일. 애플 웹 제외.
- **실시간 프록시 비용 절감:** Functions 호출을 최소화한다.
  - **서버 캐시:** 프록시 `onCall`이 매 호출마다 Naver를 때리지 않고, **Firestore(또는 함수 인스턴스 메모리)에 짧은 TTL(예: 지수 10~15초)로 캐싱**해서 그 안엔 캐시 반환. 이미 있는 `recordNightFuturesPrice`(onSchedule)처럼 **스케줄러가 주기적으로 값을 채우고, 웹은 그 최신값만 읽는** 방식이면 웹 유저 수와 무관하게 함수 비용이 고정됨 → 이 방식 우선.
  - **클라이언트 폴링 간격 하한:** 웹에서 실시간 갱신 주기를 과도하게 짧게 두지 않음(예: 지수 10초+).
  - **리전/타임아웃:** 기존 함수와 동일 `asia-northeast3`, timeout 10s.

### 남은 리스크
- **AI 분석 남용 방지:** 웹엔 광고 게이트가 없으므로 로그인 필수 + 무료 쿼터로만 제한. 쿼터는 Firestore 기반이라 웹에도 동일 적용.
- **카카오 웹 도메인 등록:** Kakao 개발자 콘솔에 웹 플랫폼(사이트 도메인/Redirect URI) 등록 필요. 배포 도메인 확정 후 진행.
- **딥링크/공유:** 앱 딥링크와 웹 URL 매핑 정책(후순위).

---

## 5. 구현 진행 상태 (2026-07-05 업데이트)

### ✅ Phase A — 웹 컴파일 통과 (완료)
- `main.dart`: 네이티브 부트스트랩을 조건부 import 파사드로 분리
  → `lib/boot/native_boot.dart` (+ `_io.dart` 실제 / `_stub.dart` 웹 no-op).
  광고/FCM/딥링크/AppCheck/ATT 는 웹에서 아예 import 안 됨.
- `subscription_service` · `ad_service`: `dart:io Platform` → `defaultTargetPlatform` 교체(웹 안전).
- `dart:io` 쓰던 화면 스텁:
  - 스크린샷 공유 → `lib/utils/share_capture.dart`(+io/web). 네이티브 temp파일 / 웹 `XFile.fromData`.
  - 픽커 이미지 표시 → `lib/utils/local_image.dart`(+io/web). 네이티브 `Image.file` / 웹 `Image.network`.
  - `market_analysis_screen` 의 `HttpClient` → `http` 패키지로 교체.
- `bot_profiles.dart`: JS 64비트 정수 초과 → `Random` 로 교체.
- **결과:** `flutter build web` 성공.

### ✅ Phase B — 웹 셸 + 8개 기능 (완료)
- `lib/web/web_shell.dart`: 넓은 화면 NavigationRail / 좁은 화면 Drawer, 본문 max-width 720 중앙정렬.
  8개 기능을 IndexedStack 으로 연결(AI분석·추천주·자유게시판·시황분석글·야간선물·실시간지수·경제캘린더·시장심리지표).
  - 추천주 = 기존 `StockPicksListScreen` 재사용.
  - 야간선물 = 코스피/코스닥 세그먼트 → `NightFuturesChartScreen`.
  - 실시간 지수 = 지수 타일 리스트 → `IndexDetailScreen`.
- `lib/web/web_login_sheet.dart`: 카카오/구글/이메일 로그인 다이얼로그(애플 제외).
- `main.dart` 진입 분기: `kIsWeb ? WebShell() : _RootGate()`.
- **결과:** 로컬 서빙(`build/web`) 부팅·렌더 확인, 콘솔 에러 0.

### ✅ Phase C — 실시간 데이터 CORS 프록시 (코드 완료 / 배포 필요)
- `functions/cors_proxy.js`: 범용 `corsProxy` onCall — 허용호스트 allowlist(naver/yahoo finance)
  + 인메모리 10초 TTL 캐시(비용 억제). `index.js` 에 export 등록.
- `stock_price_service._pget`: 저수준 http 래퍼. 웹이면 `corsProxy` 경유, 네이티브면 직접.
  기존 `http.get` 24곳 전부 `_pget` 로 치환 → 지수/차트/펀더멘털 등 웹 데이터 경로 일괄 커버.
- ⚠️ **배포 전까지 웹의 실시간 지수/차트 데이터는 비어 보임.** (야간선물은 기존 `getKospiNightFutures` 로 이미 동작)

### 🔧 남은 수동 작업 (배포/콘솔 — 사용자 진행 필요)
1. **Functions 배포:** `firebase deploy --only functions:corsProxy` (프로젝트 `stockstorage-13828`).
2. **웹 앱 호스팅:** 현재 `firebase.json` 의 hosting `public` 은 딥링크 랜딩(pick.html 등)을 서빙 중 →
   **건드리지 말 것.** Flutter 웹은 별도 사이트로 배포 권장:
   - `firebase hosting:sites:create stockstorage-web`
   - `firebase.json` hosting 을 배열로 바꿔 두 타깃(기존 `public`, 신규 `build/web` + SPA rewrite) 구성
   - `flutter build web` → `firebase deploy --only hosting:stockstorage-web`
3. **카카오 콘솔:** 웹 플랫폼 도메인 등록(배포 도메인 + localhost), JavaScript 키를
   빌드 시 주입: `flutter build web --dart-define=KAKAO_JS_KEY=<js키>`.
4. **구글 로그인:** Firebase Auth 승인된 도메인에 배포 도메인 추가(웹 팝업 로그인용).
5. **App Check(선택):** 웹 App Check 는 현재 스킵. Firestore/Functions 에 App Check 강제(enforce)가
   켜져 있으면 웹에서 reCAPTCHA v3 provider 등록 필요.

### 로컬 미리보기
`.claude/launch.json` 에 `Flutter Web Build`(python http.server, `build/web`, 8200) 추가됨.
`flutter build web` 후 해당 서버로 확인.
