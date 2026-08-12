@echo off
cd /d "%~dp0"
echo Compiling xianxia-game...
haxe compile-js.hxml
if %errorlevel% equ 0 (
    echo.
    echo === Compilation SUCCESS ===
) else (
    echo.
    echo === Compilation FAILED (error code: %errorlevel%) ===
)
pause
