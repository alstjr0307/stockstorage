@echo off
cd /d %~dp0
echo ===== %date% %time% ===== >> run_log.txt
node fmkorea_scraper.js >> run_log.txt 2>&1
