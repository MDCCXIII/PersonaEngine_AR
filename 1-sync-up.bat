@echo off
setlocal ENABLEEXTENSIONS

REM ===== Settings =====
set "BRANCH=master"

REM Move to the folder this script is in
pushd "%~dp0" >nul 2>&1

echo.
echo  Staging all changes...
git add -A

REM ===== Timestamp builder via PowerShell =====
for /f "delims=" %%a in ('
    powershell -NoProfile -Command "(Get-Date).ToString(\"ddd [MMM-dd-yyyy]\")"
') do set "STAMP=%%a"

echo Using commit timestamp: %STAMP%

echo.
echo  Committing (if there are changes)...
git commit -m "Sync-Up: auto commit - %STAMP%"


REM If commit failed or there was nothing to commit
if errorlevel 1 (
    echo No changes to commit or commit failed.
)

REM If commit succeeded
if not errorlevel 1 (
    echo Commit created successfully.
)


echo.
echo  Force pushing local -> origin/%BRANCH% ...
git push origin %BRANCH% --force

echo.
echo  Building raw.githubusercontent.com URL list and copying to clipboard...
call "%~dp0\2-get-raw.bat"

echo.
echo  Done. Remote now matches your local copy.
echo   (Clipboard now contains raw URLs for all .lua and .toc files.)


popd >nul 2>&1
endlocal
REM pause
