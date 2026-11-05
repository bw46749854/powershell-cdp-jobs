@echo off
rem Monthly job: save the planting records of every plot from the planting ledger, then
rem collect last month's plantings into one CSV (JobName: MonthlyPlantingReport).
rem Before running, show the plot list in a browser started with remote debugging.
rem Guide: docs/guides/operations.md
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\invoke-job.ps1" -JobName MonthlyPlantingReport
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (
    echo Completed: MonthlyPlantingReport
) else (
    echo FAILED: MonthlyPlantingReport - exit code %EXIT_CODE%. Read the messages above.
)
pause
exit /b %EXIT_CODE%
