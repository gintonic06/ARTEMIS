@echo off
title ARTEMIS Launcher

echo ========================================
echo    🚀 Iniciando ARTEMIS
echo ========================================

echo Iniciando servidor FastAPI...
start python -m uvicorn main:app --host 0.0.0.0 --port 8765 --reload

timeout /t 5 /nobreak >nul

echo Ejecutando Flutter (en Windows desktop)...
flutter run -d windows

echo ========================================
echo    ✅ ARTEMIS finalizado
echo ========================================

