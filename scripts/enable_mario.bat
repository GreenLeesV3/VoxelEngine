@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  Voxel Engine — Enable Mario Mode (Bring Your Own ROM)
:: ============================================================
::  Validates your Super Mario 64 (USA) ROM by SHA1 and copies
::  it to roms\baserom.us.z64 so the engine can find it at runtime.
::
::  Usage:
::    1. Drag-and-drop your .z64 ROM onto this file, OR run:
::         enable_mario.bat "C:\path\to\your_rom.z64"
::    2. If no argument is given, the script searches this folder
::       and subfolders for a .z64 file.
::
::  The ROM is NOT included and is never committed to git.
::  Obtain it legally (e.g. dump your own cartridge).
::  Expected SHA1: 9bef1128717f958171a4afac3ed78ee2bb4e86ce
:: ============================================================

set "EXPECTED_SHA1=9bef1128717f958171a4afac3ed78ee2bb4e86ce"
set "ROOT=%~dp0.."
set "DEST_DIR=%ROOT%\roms"
set "DEST=%DEST_DIR%\baserom.us.z64"

::: --- Find the ROM file ---
set "ROM="

set "ARG=%~1"
if "!ARG!"=="" goto :search_rom
set "ROM=!ARG!"
goto :found_rom

:search_rom
:: Prefer existing baserom.us.z64 if present
if exist "%DEST%" (
    set "ROM=%DEST%"
    goto :found_rom
)
:: Iterate all .z64 candidates, pick the one whose SHA1 matches SM64
for /r "%ROOT%" %%f in (*.z64) do (
    if not defined ROM (
        call :check_sha1 "%%f"
        if !SHA1_OK! equ 1 set "ROM=%%f"
    )
)
goto :found_rom

:check_sha1
set "SHA1_OK=0"
set "CAND_HASH="
set "CL=0"
for /f "skip=1 tokens=*" %%a in ('certutil -hashfile "%~1" SHA1 2^>nul') do (
    set /a CL+=1
    if !CL! equ 1 (
        set "CAND_HASH=%%a"
        set "CAND_HASH=!CAND_HASH: =!"
    )
)
if /i "!CAND_HASH!"=="%EXPECTED_SHA1%" set "SHA1_OK=1"
goto :eof

:found_rom

if not defined ROM (
    echo.
    echo  [ERROR] No ROM file found.
    echo.
    echo  Usage: enable_mario.bat "C:\path\to\Super Mario 64 (USA).z64"
    echo  Or place a .z64 file in this folder and run the script.
    echo.
    exit /b 1
)

if not exist "%ROM%" (
    echo.
    echo  [ERROR] File not found: "%ROM%"
    exit /b 1
)

echo.
echo  Found ROM: %ROM%
echo  Validating SHA1 hash...

:: --- Compute SHA1 using certutil ---
:: certutil output is:
::   SHA1 hash of <filename>:
::   <hash>
::   CertUtil: -hashfile command completed successfully.
:: We skip the first line and grab the second (the hash).
set "HASH="
set "LINECOUNT=0"
for /f "skip=1 tokens=*" %%a in ('certutil -hashfile "%ROM%" SHA1 2^>nul') do (
    set /a LINECOUNT+=1
    if !LINECOUNT! equ 1 (
        set "HASH=%%a"
        :: Strip spaces (certutil may insert them on some Windows versions)
        set "HASH=!HASH: =!"
    )
)

if not defined HASH (
    echo.
    echo  [ERROR] Could not compute SHA1 hash. Is certutil available?
    exit /b 1
)

echo  Computed SHA1: !HASH!
echo  Expected SHA1: %EXPECTED_SHA1%

if /i "!HASH!" neq "%EXPECTED_SHA1%" (
    echo.
    echo  [ERROR] SHA1 mismatch!
    echo  This is not the correct SM64 US ROM.
    echo  The engine requires the US release with SHA1:
    echo    %EXPECTED_SHA1%
    echo.
    exit /b 1
)
::: --- Copy to roms/baserom.us.z64 (skip if already there) ---
if not exist "%DEST_DIR%" mkdir "%DEST_DIR%"

:: Canonicalize both paths so same-file is detected regardless of ..\ or relative paths
for %%I in ("%ROM%") do set "ROM_ABS=%%~fI"
for %%I in ("%DEST%") do set "DEST_ABS=%%~fI"

if /i "!ROM_ABS!"=="!DEST_ABS!" (
    echo  ROM already in place: %DEST%
) else (
    copy /y "%ROM%" "%DEST%" >nul 2>&1
    if errorlevel 1 (
        echo.
        echo  [ERROR] Failed to copy ROM to "%DEST%"
        exit /b 1
    )
    echo  Copied to: %DEST%
)

echo.
echo  ========================================
echo   Mario mode is now ready!
echo   Press M in-game to activate Mario.
echo.
echo   The ROM also provides authentic SM64 HUD
echo   textures (power meter, coins, stars) at
echo   runtime — no copyrighted data is stored
echo   or uploaded to GitHub.
echo  ========================================
exit /b 0
