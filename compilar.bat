@echo off
title Compilador de Plataforma Biblica
cls
echo =======================================================
echo          COMPILADOR AUTOMÁTICO DE LA APP
echo =======================================================
echo.

echo [1/3] Limpiando cache del proyecto...
call flutter clean
echo.

echo [2/3] Descargando dependencias actualizadas...
call flutter pub get
echo.

echo [3/3] Compilando APK de Android optimizado...
call flutter build apk --release --split-per-abi
echo.

echo [4/3] Compilando plataforma Web de produccion...
call flutter build web --release
echo.

echo =======================================================
echo 🎉 PROCESO TERMINADO CON ÉXITO
echo =======================================================
echo 📱 APK Android: build\app\outputs\flutter-apk\
echo 🌐 Carpeta Web: build\web\
echo =======================================================
echo.
pause
