# FMKorea Scraper Ops Guide

이 폴더의 스크립트는 로컬이 아니라 GitHub Actions에서 자동 실행되도록 구성할 수 있습니다.

## 수집 대상
- `fmkorea_scraper.js`: 펨코 지수 (`fmkorea_index`, `fmkorea_index_meta`)
- `fmkorea_yesterday_mentions_scraper.js`: HOT 종목 (`fmkorea_stock_mentions_daily`, `fmkorea_stock_mentions_realtime/today`)
- `premarket_briefing.js`: 평일 아침 장전 뉴스 브리핑 (`premarket_briefings`, `premarket_briefings_meta/latest`)
- `auto_stock_picker.js`: 네이버 일봉 기반 자동 추천 후보 선별 및 특징주 업로드

## GitHub Actions 워크플로우
- 파일: `.github/workflows/fmkorea-scraper.yml`
- 장전 브리핑 파일: `.github/workflows/premarket-briefing.yml`
- 특징주 파일: `.github/workflows/auto-stock-picker.yml`
- 스케줄:
  - HOT 종목: 매시 5분(UTC)
  - 펨코 지수: 00:00, 04:00, 09:00, 14:00 UTC (KST 09:00, 13:00, 18:00, 23:00)
  - 장전 브리핑: 일-목 22:30 UTC (KST 평일 07:30)
  - 특징주: 월-금 06:30 UTC (KST 평일 15:30)
- `workflow_dispatch`로 수동 실행 가능

## 필수 Secrets
레포 `Settings > Secrets and variables > Actions`에 아래를 추가하세요.

- `FIREBASE_SERVICE_ACCOUNT`
  - Firebase 서비스 계정 JSON 전체 문자열
  - 예시: `{"type":"service_account",...}`
- `OPENAI_API_KEY` (선택)
  - 있으면 OpenAI Responses API로 브리핑 문장을 다듬습니다.
  - 없으면 수집 기사 기반 기본 템플릿으로 생성합니다.
- `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` (선택)
  - 설정하면 브리핑 전문을 텔레그램으로 보냅니다.

## 선택 Variables
- `OPENAI_MODEL`: 기본값 `gpt-4.1-mini`
- `SEND_PREMARKET_FCM`: `1`이면 FCM 토픽 알림 발송
- `PREMARKET_FCM_TOPIC`: 기본값 `stock_alerts`
- `AUTO_PICK_MIN_SCORE`: 자동 추천 최소 점수, 기본값 `65`
- `AUTO_PICK_MAX_PICKS`: 하루 최대 업로드 수, 기본값 `8`
- `AUTO_PICK_MIN_AVG_TRADING_VALUE`: 20일 평균 거래대금 하한, 기본값 `1000000000`
- `AUTO_PICK_SEND_FCM`: `1`이면 자동 추천 업로드 후 FCM 발송
- `AUTO_PICK_FCM_TOPIC`: 기본값 `new_pick_alerts`

## 로컬 수동 실행(테스트용)
```bash
cd scraper
npm ci

# 펨코 지수
node fmkorea_scraper.js

# HOT 종목(오늘 누적)
TARGET_MODE=today node fmkorea_yesterday_mentions_scraper.js

# 장전 브리핑
npm run premarket

# 자동 추천주 테스트(업로드 없음)
DRY_RUN=1 MAX_STOCKS=50 npm run auto-picks

# 특징주 업로드
npm run market-features

# 자동 추천주 업로드(수동 실행용)
npm run auto-picks
```

## 참고
- GitHub Actions는 서버리스로 동작하므로 PC가 꺼져 있어도 실행됩니다.
- Puppeteer 기반이라 간헐적 차단/타임아웃이 있을 수 있으며, 필요 시 재시도/스케줄 간격 조정으로 안정화하세요.
