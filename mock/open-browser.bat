@echo off
rem Opens Microsoft Edge with remote debugging (port 9222) on a dedicated profile and shows
rem both mock apps. Run start-mock-site.bat first.
rem The dedicated profile matters: the browser ignores the debugging port when a window
rem using the same profile is already open.
setlocal
set "PROFILE_DIR=%LOCALAPPDATA%\powershell-cdp-jobs\edge-remote-debugging"
start "" msedge.exe --remote-debugging-port=9222 --user-data-dir="%PROFILE_DIR%" --no-first-run "http://localhost:8080/greenhouse-console/" "http://localhost:8080/planting-ledger/"
