@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rotate.ps1" %*
if "%1"=="" pause
