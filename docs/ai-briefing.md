# AI 브리핑

## Schedule (Asia/Seoul, weekdays)

- 08:00: overnight news, US market, FX/rates/oil, domestic implications, upcoming calendar.
- 12:00: domestic morning session, sectors/flows/breadth; compare with the morning summary when available.
- 15:30: domestic closing summary.

`functions/index.js` registers the existing four endpoints. Shared generation lives in
`functions/ai_brief.js`, with morning inputs and prompt in `functions/ai_brief_morning.js`.
Deploy only `generateAiBriefMorning`, `generateAiBriefMidday`,
`generateAiBriefAfternoon`, and `generateAiBriefNow` for this change.

## Input and failure handling

- Morning news begins at the previous weekday's 15:30 KST. Monday includes the weekend.
  This is a weekday boundary, not an exchange holiday calendar.
- Date-invalid, older and future news items are excluded. Queries are interleaved so
  domestic results cannot consume every news slot. Titles, source, URL and publication
  time are retained; article bodies are not fetched.
- Morning does not fetch domestic sectors, breadth or flows. Previous-day domestic
  quotes do not imply a holiday at 08:00. A domestic quote outage does not stop morning generation.
- US index dates and macro observation times accompany values. Calendar dates remain
  source-local: the source's date must not be converted into an invented Korean release time.
- Weekday Korean holidays can still receive an overnight briefing. Weekend manual runs
  retain the existing closed-market notice behavior.
- Missing both US indices and news, invalid JSON, incomplete output or missing required
  sections abort generation without overwriting the previous briefing.

## Data and app compatibility

`ai_briefs/latest` and `ai_briefs/{YYYY-MM-DD}` keep `brief`, `sections`, `slot`,
`slotLabel`, `date`, and quote fields. Morning is stored under `08`; legacy manual
`09` inputs normalize to `08`. Existing dated `09` records remain readable.
New optional fields are `briefingType`, `sources`, `usMarket`, and `context`.

Old apps can read new briefing content without an update. The renamed heading,
morning section labels and correct stale-date display require a client release.
The app now compares stored dates with Korean time rather than always labeling them today.

## Verification

```text
node --test functions/ai_brief.test.js
flutter test test/ai_brief_presentation_test.dart test/keep_alive_section_test.dart
```

For a manual preview, set `OPENAI_API_KEY` in the environment and run
`node generate_brief_now.js --slot=08 --dry-run` from `functions`.
The preview uses live inputs and incurs one AI call, but makes no Firestore writes.
Without `--dry-run`, the same pipeline publishes the selected slot.
