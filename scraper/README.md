# FMKorea Scraper Ops Guide

이 폴더의 스크립트는 로컬이 아니라 GitHub Actions에서 자동 실행되도록 구성할 수 있습니다.

## 수집 대상
- `fmkorea_scraper.js`: 펨코 지수 (`fmkorea_index`, `fmkorea_index_meta`)
- `fmkorea_yesterday_mentions_scraper.js`: HOT 종목 (`fmkorea_stock_mentions_daily`, `fmkorea_stock_mentions_realtime/today`)

## GitHub Actions 워크플로우
- 파일: `.github/workflows/fmkorea-scraper.yml`
- 스케줄:
  - HOT 종목: 매시 5분(UTC)
  - 펨코 지수: 00:00, 04:00, 09:00, 14:00 UTC (KST 09:00, 13:00, 18:00, 23:00)
- `workflow_dispatch`로 수동 실행 가능

## 필수 Secrets
레포 `Settings > Secrets and variables > Actions`에 아래를 추가하세요.

- `FIREBASE_SERVICE_ACCOUNT`
  - Firebase 서비스 계정 JSON 전체 문자열
  - 예시: `{"type":"service_account",...}`

## 로컬 수동 실행(테스트용)
```bash
cd scraper
npm ci

# 펨코 지수
node fmkorea_scraper.js

# HOT 종목(오늘 누적)
TARGET_MODE=today node fmkorea_yesterday_mentions_scraper.js
```

## 참고
- GitHub Actions는 서버리스로 동작하므로 PC가 꺼져 있어도 실행됩니다.
- Puppeteer 기반이라 간헐적 차단/타임아웃이 있을 수 있으며, 필요 시 재시도/스케줄 간격 조정으로 안정화하세요.
