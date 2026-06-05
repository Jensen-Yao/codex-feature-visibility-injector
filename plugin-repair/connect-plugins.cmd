@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0connect-openai-bundled-plugins.ps1"
echo.
echo Done. Fully quit and reopen Codex/Codex++ or start a new chat if Computer tools are not visible in the current chat.
pause
