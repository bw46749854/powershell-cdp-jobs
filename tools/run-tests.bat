@echo off
rem Windows PowerShell 5.1 でテスト一式を実行する（ダブルクリック用）。
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-Tests.ps1"
pause
