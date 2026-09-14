# Instagram Reel design — approved 2026-09-13

User request: 앞으로 인스타 업로드 되는 종목분석 릴스도 이런 폰트랑 디자인 이용해. 아래에 여백 두는것도 잊지말고.

## Reusable defaults

- Reference: `output/app-promo-reel/hd-v8/stockstorage-app-promo-hd-v8.mp4`.
- Native 1080×1920, 30fps. No 720p upscaling.
- Wanted Sans Black/ExtraBold headlines; Medium/SemiBold supporting text; Regular secondary text. Fonts and OFL: `functions/instagram_assets/WantedSans-*`.
- Palette: ivory #f4f3ec, ink #151813, lime #c6f45b, muted #777c73. Alternate light and dark cuts for rhythm; lime highlights only key text/actions.
- Large, left-aligned typography, tight tracking (-0.035em), clear weight hierarchy, generous whitespace and thin separators. Avoid unnecessary nested decorative cards.
- At least 72px side margins. All visible content including captions, sources, logos, progress indicators and download buttons must remain above y=1550. Keep the bottom 370px blank. Check through the shared `assert_safe_bottom` helper before publication.
- Use `functions/instagram_reel_style.json` as the deployable source of truth; the local Python helper reads that same file. The current approved promo renderer imports them.

## Stock-analysis content to retain

Retain the approved stock-analysis information when applying this appearance: curiosity opening with a large company name, “왜 올랐을까”, small “AI 분석으로 알아보는 (기업명)”, and “오늘의 AI종목분석” at top left. Explain the company and recent issue early, include an early AI score, avoid duplicate cuts, show five historical fiscal years and two available forecast years with growth rates, 52-week drawdown, at least eight trading days of foreign/institutional flows, and peer PER/PBR. Label forecasts and use verified sources; do not fabricate missing information. Preserve readable charts/tables and concise cut timings.

## Scope

The user authorized the scheduled stock-analysis pipeline to publish Reels on 2026-09-15. `generateDailyInstagramAnalysis` now uses `functions/instagram_reel.js`, `instagram_reel_frames.js`, the deployment-bundled style JSON and fonts, and `InstagramGraph.reel()`. One native 1080×1920 MP4 replaces the prior carousel. Preserve schedule and duplicate guards when changing this path. Historical local video scripts remain review artifacts; production does not depend on the output directory.

Font source: https://github.com/wanteddev/wanted-sans
Design reference reviewed: https://toss.im/new-dimension/brand-story
