@echo off
title Compilador de Plataforma Biblica
cls
echo =======================================================
echo          COMPILADOR AUTOMÁTICO DE LA APP
echo =======================================================
echo.

echo [1/4] Limpiando cache del proyecto...
cmd /c flutter clean
echo.

echo [2/4] Descargando dependencias actualizadas...
cmd /c flutter pub get
echo.

echo [3/4] Compilando APK de Android optimizado...
cmd /c flutter build apk --release --split-per-abi
echo.

echo [4/4] Compilando plataforma Web de produccion...
cmd /c flutter build web --release
echo.

echo =======================================================
echo 🎉 PROCESO TERMINADO CON EXITO
echo =======================================================
echo APK Android: build\app\outputs\flutter-apk\
echo Carpeta Web: build\web\
echo =======================================================
echo.
pause
