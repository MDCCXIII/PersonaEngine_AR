@echo off
setlocal

REM ===== Settings =====
set BRANCH=master

REM Go to the folder this script is in (your repo root)
pushd "%~dp0" >nul 2>&1

echo.
echo 🌐 Fetching latest from remote...
git fetch --all

echo.
echo 💣 Resetting local copy to origin/%BRANCH% ...
git reset --hard origin/%BRANCH%

echo.
echo 🧹 Cleaning untracked files and folders...
git clean -fd

echo.
echo ✅ Local copy now exactly matches origin/%BRANCH%.
echo.
pause

