@echo off
setlocal
if not defined GODOT set "GODOT=godot"
"%GODOT%" --version >nul 2>&1
if errorlevel 1 (
  echo Set GODOT to the full path of your Godot 4.7.1 console executable.
  exit /b 1
)
if not exist "%~dp0build\web" mkdir "%~dp0build\web"
"%GODOT%" --headless --path "%~dp0." --editor --import
if errorlevel 1 exit /b 1
"%GODOT%" --headless --path "%~dp0." --export-release "Web" "%~dp0build\web\index.html"
if errorlevel 1 exit /b 1
echo Experimental Web build. See docs/BUILDING.md for limitations.
echo Serve with: python -m http.server 8080 --directory "%~dp0build\web"
