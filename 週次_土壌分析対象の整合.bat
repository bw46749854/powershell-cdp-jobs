@echo off
rem Weekly job: export the plot roster from the greenhouse console, then align the
rem soil analysis target checkboxes with it (JobName: WeeklySoilAnalysisSync).
rem Before running, show the plot list in a browser started with remote debugging.
rem Guide: docs/guides/operations.md
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\invoke-job.ps1" -JobName WeeklySoilAnalysisSync
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
    echo Completed: WeeklySoilAnalysisSync
) else (
    echo FAILED: WeeklySoilAnalysisSync - exit code %EXIT_CODE%. Read the messages above.
)
pause
exit /b %EXIT_CODE%
