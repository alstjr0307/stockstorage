@echo off
cd /d %~dp0
echo ===== %date% %time% ===== >> run_mentions_log.txt
set TARGET_MODE=today
node fmkorea_yesterday_mentions_scraper.js >> run_mentions_log.txt 2>&1
