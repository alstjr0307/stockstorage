# Instagram Reel production preferences

For Instagram stock-analysis and app-promotion Reels, follow the user-approved design in [docs/instagram-reel-design.md](docs/instagram-reel-design.md). This is the default for future Reel work, unless the user requests a change.

Use the shared `tools/instagram_reel_style.py` / `tools/instagram_reel_style.json` defaults and the bundled Wanted Sans fonts. Render natively at 1080×1920. Keep all visible content above y=1550; the bottom 370px must remain clear for Instagram advertising controls. Do not revert to older Samsung reel typography or 720p-upscaled templates.

The scheduled stock-analysis pipeline now generates and publishes Reels through `functions/instagram_reel.js` and `InstagramGraph.reel()`. Deploy changes to `generateDailyInstagramAnalysis` to update the server. Use the deployment-bundled `functions/instagram_reel_style.json` and Wanted Sans fonts; local shared defaults must stay in sync. The user authorized future scheduled stock-analysis Reels. Do not duplicate previously published media.
