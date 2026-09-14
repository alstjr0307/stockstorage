# AI Instagram Automation

## Production Status

- Instagram account: `@tf_stockstorage`
- Meta app: `주식저장소` (`1357828916468368`)
- Instagram app: `주식저장소-IG` (`1398866978871767`)
- Instagram user id: `17841409520140755`
- Firebase project: `stockstorage-13828`
- Deployed function: `generateDailyInstagramAnalysis`
- Schedule: Monday-Friday, 10:00 / 14:00 / 17:00 Asia/Seoul
- Default volume: 1 stock analysis per slot, one 53-second Reel (11 cuts)
- Posting secret: `INSTAGRAM_ACCESS_TOKEN` in Firebase Secret Manager

The Instagram token is not stored in the repository. It was generated with
`instagram_business_basic` and `instagram_business_content_publish` for
`tf_stockstorage`, then saved as a Firebase secret.

## Flow

`generateDailyInstagramAnalysis` reuses the existing app AI stock analysis path
through `runStockAiAnalysis()`. Scheduled runs use the synthetic uid
`instagram-automation`, so they do not consume a user quota or send push
notifications.

Each run:

1. Checks `_admin/instagramAutomation`.
2. Verifies the Instagram token identity before paying for AI analysis.
3. Chooses the next stock from the configured universe.
4. Collects current Naver market candles, quote data, valuation data, and recent
   Google News RSS items.
5. Filters news to items whose article title directly mentions the stock keyword.
6. Runs the existing AI analysis function.
7. Edits the analysis and renders 11 native 1080×1920 scenes, including annual results, with Wanted Sans and the approved ivory/ink/lime palette.
8. Encodes a 53-second H.264/AAC MP4 with bundled original music and ffmpeg-static, checks decoding, then uploads it to Firebase Storage.
9. Creates one REELS container, waits for readiness, persists publishing intent, then publishes it. No carousel children are created.
10. Records job state under `_admin/instagramAutomation/jobs/{date_market_ticker}`.

The final card and caption include:

```text
더 많은 종목 분석이 궁금하다면?
@tf_stockstorage 프로필 링크에서 주식저장소 앱을 다운로드하세요.
```

## Safety Guards

- The function exits when `_admin/instagramAutomation.enabled` is not true.
- It refuses to publish if the token identity is not `tf_stockstorage`.
- It skips stale or closed-market data unless running in local preview mode.
- It requires recent source URLs and risk factors before rendering.
- It stores `publishing` before calling Instagram `media_publish`.
- Jobs in `published`, `publishing`, or `publish_uncertain` are never replayed by
  the scheduler, preventing duplicate posts after ambiguous publish responses.
- The access token is refreshed through Instagram's refresh endpoint on scheduled
  runs when the stored refresh time is older than seven days.

## Local Preview

Run a full local smoke test without publishing:

```powershell
$env:OPENAI_API_KEY = firebase functions:secrets:access OPENAI_API_KEY --project stockstorage-13828
$env:DART_API_KEY = firebase functions:secrets:access DART_API_KEY --project stockstorage-13828
node functions/instagram_preview.js output/instagram-ai-live-preview
Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:DART_API_KEY -ErrorAction SilentlyContinue
```

Preview output contains `analysis.json`, `series.json`, and per-part directories
with JPEG cards, `caption.txt`, and `draft.json`.

## Verification

```powershell
node --check functions/index.js
node --check functions/instagram_daily.js
node --check functions/instagram_graph.js
node --check functions/instagram_content.js
node --test functions/instagram.test.js
firebase functions:list --project stockstorage-13828
firebase functions:secrets:get INSTAGRAM_ACCESS_TOKEN --project stockstorage-13828
```

Firebase currently warns that Node.js 20 is deprecated and will be
decommissioned on 2026-10-30. Plan a separate runtime upgrade for the whole
functions codebase.

## Historical implementation notes

The sections below describe earlier carousel revisions, not the current scheduled publication format.

## Full analysis carousel design (2026-09-09)

The renderer now maps the app's narrative analysis fields explicitly in
`instagram_sections.js`: company profile, complete summary, score breakdown,
price drivers, fundamentals, technicals, news, flows, every catalyst,
valuation and peers, technical details, all three scenarios, detailed risks,
timing, and supplemental sections. Source datasets and URLs remain in the
saved analysis/draft and in the app; raw historical data tables are not
converted into image pages.

Pagination measures the packaged Korean font at 32 px and preserves the
transcript, preferring sentence/paragraph boundaries. Content is grouped into
up to 8 body cards plus cover and download card per post, within Meta's
10-image publishing API limit. A stock can therefore produce multiple posts;
`dailyCount` continues to mean stocks per day, not posts per day. The full
historical NAVER fixture produces 3 parts (10, 10, 8 cards). Each part identifies
its sequence in its cover and caption and ends with the download CTA.

The packaged `instagram_assets/research-ai.png` was generated with the built-in
image tool. It is reused automatically, not regenerated on each daily run.
Its exact prompt is saved alongside the image. Cover/caption labels identify
it as a conceptual AI illustration.

`publishSeries` records part-level media IDs and retains a non-replayable
parent state across the entire series. A failure after publishing begins
requires inspection of the saved `parts` before manual recovery; never clear
a job's publication status blindly. Confirmed earlier parts must not be
published again.

Render saved analysis without API calls or publication:

```powershell
node tools/instagram_render_saved.cjs tools/instagram_ai_full_sample.json output/instagram-full-preview
```

Daily preview output now contains `analysis.json`, `series.json`, and a
`part-01`, `part-02`, etc. directory for each caption/draft/image set.


## Current visual editorial mode

Production now uses `createEditorialSeries()` from `instagram_editorial.js`.
The legacy full-transcript paginator remains available for offline exports.
The existing gpt-5-mini Responses integration makes a separate editorial pass
on the completed analysis: a question-led cover and eight topic cards, each
with a large metric/keyword and 2–4 short points. Score components use bars;
three scenarios use a comparison layout; four-point cards use a tile grid.
The final card retains the exact download CTA. This is a concise adaptation,
not a verbatim reproduction: full analysis and source sections are retained
in the saved job and the app.

Validation requires every mapped section ID to be referenced, caps text
length, checks numeric strings against source text, preserves scenario order
and the app's action verdict. These checks do not prove semantic fidelity;
the prompt also requires preserving conditions and uncertainty. Validation
failures get up to two editorial repairs, then stop publication. Rendering
still rejects overflow. The packaged AI illustration is reused.

Preview of the saved, reviewed editorial sample:

```powershell
node tools/instagram_editorial_preview.cjs --saved
```

The preview script uses a historical saved analysis; it does not publish.
Without `--saved`, it needs OPENAI_API_KEY for a new editorial pass.

## Journal layout and market charts (2026-09-10)

Current production layout uses Pretendard ExtraBold for headlines and Medium
for body copy, charcoal/ivory with a blue accent, open rows and thin rules.
The previous stock illustration is no longer used by this renderer. AI origin
is retained in the footer; the editorial pass uses everyday Korean rather
than report jargon, and rejects a defined set of stiff stock phrases before
publication. Cover and download copy use the same constraints as before.

Daily jobs now retain the collected candle data in `analysis.sourceCandles`
and its endpoint in `sourcePriceUrl`. The cover and chart page plot the latest
60 observed closing prices up to marketDate. The displayed return compares
first and last points of that window (labelled 표시 기간). No prices are invented
or projected; missing data produces an explicit unavailable message.
Peer PER bars use numeric positive values from valuation.peerComparison and
label the unit/source. Score bars still use the model's original subScores.

The historical review fixture captures the market endpoint response through
2026-09-04 in tools/instagram_chart_sample.json. Review-only rendering:

```powershell
node tools/instagram_journal_preview.cjs
```

This writes output/instagram-journal and makes no analysis/publishing calls.
The reviewed copy is in tools/instagram_human_sample.json. Production copy is
generated per stock, with topic/numeric/action/style validation and bounded
repair attempts, then measured by the renderer before any upload.

Known report phrases are also normalized before validation, including Korean
particle changes when a replacement changes the final consonant. This changes
surface wording only; numbers, ordering, and source IDs remain untouched.
The final copy must still pass all length/source checks. The captured live
response was replayed through this final normalization/rendering pipeline;
preview typography, peer bars, and 60-session history rendered successfully.

## Candles, daily investor flows and company imagery

Current 10-card order: company cover; company overview; analysis score;
recent news; peer valuation; OHLC candles; daily foreign/institutional net
trading; scenarios; risks + next checks; download CTA. Overview and score
have separate pages. The combined checks page preserves both sets of points.

The candle page uses 60 observed daily OHLC rows. Red means close >= open,
blue means close < open; candle wicks are the actual high and low. Facts below
are calculated directly from those rows: last close/day return, distance to
the 20-close average, 20-session intraday low/high range, and last volume vs
the preceding 20-session average volume (excluding the latest day).

The flow page plots chronological daily foreign and institutional net shares
on separate panels with a shared symmetric scale. Positive is net buying;
negative is net selling. Missing data remains null and is marked ×, never
converted to zero. Up to 20 available observations are retained; the preview
source contains 14 sessions. No cumulative curve replaces the daily values.

Company image files are bundled under instagram_assets/companies, with
original official page/asset URLs in manifest.json. The default stock universe
has company visuals; NAVER also has a logo, building photo and robot photo.
Caption credits identify the official image page. Images are visual company
context, not a claim that a pictured scene happened on the analysis date.

The cover omits ticker code and emphasizes company name. Repeated bottom
dates/reference footers have been removed as requested. Analysis timing and
credits remain in the caption; chart-axis dates, units and colour legends
remain part of the charts. The final download CTA is unchanged.

## Relative-volume daily selection

The existing Cloud Scheduler runs at 10:00, 14:00 and 17:00 Asia/Seoul on weekdays.
Production dailyCount is 3, one stock per slot. Each run screens config.stocks, or the 30 default companies
with bundled company imagery. The added 20 candidates use Naver's company
logo assets, with source URLs and finance-page credits in the manifest.
It ranks today's volume divided by the mean
of the preceding 20 trading sessions, excluding today. Highest ratios win;
there is no hard cutoff, so quiet markets may select ratios below 1. This is
a candidate-universe screen, not an all-KRX ranking.

Only current-market-date rows with 120+ candles and a valid volume baseline
qualify. Holidays/stale data do not publish. A failed history request stops
selection instead of silently ranking an incomplete universe. Historical
data collected for selection is reused for the selected stocks' app analysis.

Each slot's stock and ranking metrics are stored transactionally under
_admin/instagramAutomation/selections/YYYY-MM-DD_HHMM. Same-day jobs and reserved
stocks are excluded, along with publications and uncertain publications in the
preceding 7 calendar days (repeatExclusionDays: 0 for same day, -1 for forever).
Reruns reuse the slot selection. If the candidate universe is exhausted, the
slot reports NO_UNUSED_INSTAGRAM_CANDIDATES rather than repeating a company.
This means three daily posts are conditional on eligible unused candidates.
Job leases and publish-uncertainty protection still apply. Other slots run
independently; results
are recorded on the config document and partial failure is reported to Cloud
Functions. Scheduler retries remain disabled; failed jobs can be rerun without
replaying confirmed/uncertain publications.

Intraday OHLC and accumulated volume come from Naver's KRX realtime quote,
guarded by the basic quote's actual localTradedAt date. Server response time
is never treated as a trade date. Prior-day quotes do not fabricate today's
candle. NXT combined volume is excluded to match the historical KRX baseline.
The 10:00/14:00 candle and caption explicitly identify provisional intraday
values. The ranking compares accumulated volume so far with the previous
20 full-session average; it does not claim a same-time-of-day comparison.

## Clean card design and fixed caption

The production renderer now uses SUIT Regular/Bold (v2.0.5, SIL OFL,
instagram_assets/SUIT-LICENSE.txt), white backgrounds, navy text and blue
accents. Overview points use spaced panels; scores use a ring and subscore
bars; logo-only companies no longer repeat the same logo twice on the news
page. Candles and daily investor-flow charts retain observed data.

Captions use the user's fixed four-paragraph copy, including the actual target
https://tofusoft-software.github.io/Stockstorage/ and four hashtags. The old
stock/date/source header and automatically appended image credit are omitted.
Asset attribution remains in the bundled manifest. Intraday status remains
visible on the candle card. Verified against both NAVER and the published
SK Innovation draft; 19 tests passed. Preview: output/instagram-clean/overview-v2.jpg.

## User reference: warm editorial cards

Reference reviewed: https://ai-for-everybody.tistory.com/4, including its cover
and body design examples. Applied warm cream/brown colors, yellow category
labels, a stronger title/body distinction and a short cover hook. Gmarket Sans
Bold (official TTF distribution, see instagram_assets/GmarketSans-SOURCE.txt)
is used for display headings; SUIT remains for supporting copy and chart labels.
The original blog illustrations are not reused. Company imagery, 10-card order,
observed candles and daily investor flows are preserved. Preview folder:
output/instagram-reference. The user-approved fixed caption is unchanged.

Score-card correction: title is fixed to 'AI 분석 점수' in both draft creation
and rendering of older saved drafts. Color thresholds match the app: below 50
red, 50 to below 70 amber, 70+ green, unavailable gray. Ring, total number and
subscore bars/numbers share this rule. Transparent text margins are trimmed
before centering the visible number at (278, 662); /100 is independently
centered below. Zero and missing scores have no foreground arc. Verified
0/9/49/50/69/70/72/100/missing with <=0.5px center error and 20 passing tests.
Actual-data preview: output/instagram-score-fix/actual-score.jpg.

## Automatic Reels (2026-09-15)

`instagram_daily.js` now always calls `renderReel()` and `InstagramGraph.reel()`. A stock produces one 53-second video: 4 seconds each for cover/CTA, 5 seconds each for nine body cuts. It keeps the existing slot selection, account verification, leases, stale-market guards and non-replayable published/uncertain states. No old completed job is republished during migration.

The renderer uses the deployment-bundled `instagram_reel_style.json` and `instagram_assets/WantedSans-*` files. It renders directly at 1080×1920, asserts all text is above y=1550, and checks every frame's lower 370px is uniform. A frame overflow or encoding failure prevents upload. Temporary video files are removed in `finally`. The Linux encoder is installed by the pinned npm dependency during Cloud Build, not copied from a developer laptop. Original music is bundled as `reel-bed.wav`.

The early AI score, company/issue imagery, seven-row annual table, eight daily foreign/institutional observations, 52-week high comparison and peer PER/PBR use the saved app analysis and market responses. Annual values come from the annual NAVER response, not quarterly statements. Missing historical/forecast years are shown as —; no unavailable estimates are invented. Negative or zero prior operating profit does not produce a misleading YoY percentage. A quote's 52-week high is used; a shorter chart history is never labelled as 52 weeks.

Review without publishing: `node tools/instagram_auto_reel_preview.cjs`. The saved fixture is historical and missing unavailable source values by design. `functions/instagram_preview.js` uses the same scheduler callback in draft mode for a live data/AI preview when credentials are configured. No public diagnostic endpoint or scheduler-time test post was introduced.

Tests: `node --test functions/instagram_reel.test.js` checks actual render dimensions and blank safe areas, annual missing/forecast values, PER/PBR, eight flow dates, and publish-intent ordering/uncertain outcomes.

Validation on 2026-09-15: four dedicated Reel tests passed; both historical and saved live-production SK하이닉스 drafts encoded and decoded as 53-second MP4s. The combined suite passed 25/26 tests; the pre-existing legacy full-transcript carousel pagination test fails with CARD_TEXT_OVERFLOW on this macOS environment. The same failure was reproduced using the original HEAD files. That legacy path is not used by the scheduled Reel renderer.
