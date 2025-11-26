@echo off
setlocal enabledelayedexpansion

REM Go to the folder this script is in (repo root)
pushd "%~dp0" >nul 2>&1

REM Base URL for raw GitHub content
set "BASE=https://raw.githubusercontent.com/MDCCXIII/PersonaEngine_AR/master"

REM Temp file to assemble the URL list
set "tmp=%TEMP%\personaengine_ar_raw_urls.txt"
if exist "%tmp%" del "%tmp%"

REM Ensure the .toc exists
if not exist "PersonaEngine_AR.toc" (
    echo PersonaEngine_AR.toc not found in %CD%
    goto :done
)

REM 1) Start with the .toc itself
echo %BASE%/PersonaEngine_AR.toc>"%tmp%"

REM 2) Follow load order from the .toc
REM    - Skip empty lines
REM    - Skip comment lines starting with "##"
REM    - Only include lines that end with .lua

for /f "usebackq tokens=* delims=" %%L in ("PersonaEngine_AR.toc") do (
    set "line=%%L"

    REM Trim leading spaces
    for /f "tokens=* delims= " %%X in ("!line!") do set "line=%%X"

    REM Skip empty lines
    if not "!line!"=="" (

        REM Skip comments (## ...)
        if /I not "!line:~,2!"=="##" (

            REM Only process .lua entries
            if /I "!line:~-4!"==".lua" (
                set "rel=!line!"

                REM Convert backslashes (if any) to forward slashes
                set "rel=!rel:\=/!"

                echo %BASE%/!rel!>>"%tmp%"
            )
        )
    )
)

REM 3) Copy the full ordered list to clipboard
type "%tmp%" | clip

REM 4) Cleanup
del "%tmp%" >nul 2>&1

:done
popd >nul 2>&1
endlocal
