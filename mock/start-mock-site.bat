@echo off
rem Serves the mock site (mock\site) at http://localhost:8080/ until this window is closed.
rem Guide: mock/README.md
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 8080
pause
