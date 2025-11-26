@echo off
setlocal

REM === CONFIG ===
REM Source lua.xml (same folder as this .bat)
set "SOURCE=%~dp0lua.xml"

REM Notepad++ install and autocomplete paths
set "NPP_EXE=C:\Program Files\Notepad++\notepad++.exe"
set "NPP_AC_DIR=C:\Program Files\Notepad++\autoCompletion"
set "TARGET=%NPP_AC_DIR%\lua.xml"

REM === CHECK SOURCE EXISTS ===
if not exist "%SOURCE%" (
    echo [ERROR] Source lua.xml not found at:
    echo         %SOURCE%
    echo Make sure lua.xml is in the same folder as this script.
    pause
    goto :EOF
)

REM === KILL NOTEPAD++ (unsaved changes will be lost!) ===
echo Closing Notepad++ ...
taskkill /IM notepad++.exe /F >nul 2>&1

REM === COPY AUTOCOMPLETE FILE ===
echo Updating Notepad++ autocomplete file ...
copy /Y "%SOURCE%" "%TARGET%" >nul

if errorlevel 1 (
    echo [ERROR] Failed to copy lua.xml to:
    echo         %TARGET%
    echo You probably need to run this script as Administrator.
    pause
    goto :EOF
)

REM === RE-LAUNCH NOTEPAD++ ===
echo Relaunching Notepad++ ...
start "" "%NPP_EXE%"

echo Done.
endlocal
@echo off
setlocal

REM === CONFIG ===
REM Source lua.xml (same folder as this .bat)
set "SOURCE=%~dp0lua.xml"

REM Notepad++ install and autocomplete paths
set "NPP_EXE=C:\Program Files\Notepad++\notepad++.exe"
set "NPP_AC_DIR=C:\Program Files\Notepad++\autoCompletion"
set "TARGET=%NPP_AC_DIR%\lua.xml"

echo ================================
echo  PersonaEngine - Update lua.xml
echo ================================
echo.

REM === CHECK SOURCE EXISTS ===
if not exist "%SOURCE%" (
    echo [ERROR] Source lua.xml not found at:
    echo         %SOURCE%
    echo Make sure lua.xml is in the same folder as this script.
    pause
    goto :EOF
)

REM === CHECK IF NOTEPAD++ IS RUNNING ===
tasklist /FI "IMAGENAME eq notepad++.exe" | find /I "notepad++.exe" >nul
if %errorlevel%==0 (
    echo Notepad++ is currently running.
    echo.
    echo Please switch to Notepad++, SAVE ALL your files,
    echo then come back here.
    echo.

    choice /C YN /M "When you're done saving, press Y to continue or N to cancel"
    if errorlevel 2 (
        echo.
        echo Update cancelled by user.
        goto :EOF
    )

    echo.
    echo Closing Notepad++ ...
    REM Try graceful close first (no /F)
    taskkill /IM notepad++.exe >nul 2>&1

    REM Wait a moment
    timeout /t 2 >nul

    REM If it's still alive, force it (this should be rare)
    tasklist /FI "IMAGENAME eq notepad++.exe" | find /I "notepad++.exe" >nul
    if %errorlevel%==0 (
        echo Notepad++ is still running, forcing close...
        taskkill /IM notepad++.exe /F >nul 2>&1
    )
) else (
    echo Notepad++ is not running. Proceeding...
)

echo.
echo Updating Notepad++ autocomplete file ...
copy /Y "%SOURCE%" "%TARGET%" >nul

if errorlevel 1 (
    echo [ERROR] Failed to copy lua.xml to:
    echo         %TARGET%
    echo You probably need to run this script as Administrator.
    pause
    goto :EOF
)

echo Done copying lua.xml.
echo.

echo Relaunching Notepad++ ...
start "" "%NPP_EXE%"

echo.
echo All set. Notepad++ is running with the updated autocomplete.
echo (Remember Notepad++ only reads lua.xml on startup, which we just forced.)
echo.

endlocal
