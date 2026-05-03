@echo off
:: Purpose: launch setup.sh through a Git for Windows bash.exe.
:: Scope: Git Bash discovery only; setup behavior lives in setup.sh and lib/setup-*.sh.
setlocal
title Shell-Secure Setup
cd /d "%~dp0"

:: Dynamische Suche nach Git Bash
call :try_git_bash "%ProgramFiles%\Git\bin\bash.exe"
if defined SHELL_SECURE_GIT_BASH_FOUND goto :done
call :try_git_bash "%ProgramFiles%\Git\usr\bin\bash.exe"
if defined SHELL_SECURE_GIT_BASH_FOUND goto :done
call :try_git_bash "%ProgramFiles(x86)%\Git\bin\bash.exe"
if defined SHELL_SECURE_GIT_BASH_FOUND goto :done
call :try_git_bash "%ProgramFiles(x86)%\Git\usr\bin\bash.exe"
if defined SHELL_SECURE_GIT_BASH_FOUND goto :done
call :try_git_bash "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if defined SHELL_SECURE_GIT_BASH_FOUND goto :done
call :try_git_bash "%LOCALAPPDATA%\Programs\Git\usr\bin\bash.exe"
if defined SHELL_SECURE_GIT_BASH_FOUND goto :done

for /f "tokens=*" %%a in ('where bash.exe 2^>nul') do (
    call :try_git_bash "%%~fa"
    if defined SHELL_SECURE_GIT_BASH_FOUND goto :done
)

echo Git Bash nicht gefunden. Bitte Git for Windows installieren.
echo https://gitforwindows.org/
:done
pause
exit /b

:try_git_bash
set "candidate=%~1"
if "%candidate%"=="" exit /b 1
if not exist "%candidate%" exit /b 1
if /i not "%~nx1"=="bash.exe" exit /b 1
echo(%candidate%| findstr /i /r /c:"\\Git\\bin\\bash\.exe$" /c:"\\Git\\usr\\bin\\bash\.exe$" >nul
if not errorlevel 1 goto :accept_git_bash
call :has_git_for_windows_layout "%candidate%"
if errorlevel 1 exit /b 1

:accept_git_bash
set "SHELL_SECURE_GIT_BASH_FOUND=1"
"%candidate%" -l "./setup.sh"
exit /b 0

:has_git_for_windows_layout
if exist "%~dp1..\cmd\git.exe" exit /b 0
if exist "%~dp1..\..\cmd\git.exe" exit /b 0
exit /b 1
