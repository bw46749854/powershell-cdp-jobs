@echo off
rem Runs all test suites with Windows PowerShell 5.1 (for double-click use).
rem Arguments are passed on, for example: run-tests.bat -Suite Pester -IncludeE2E
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Tests.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
pause
exit /b %EXIT_CODE%
