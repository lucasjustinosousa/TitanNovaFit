@echo off
chcp 65001 > nul
title TitanNovaFit - Auto Commit ^& Deploy Vercel
echo ========================================================
echo   TitanNovaFit - Sincronizacao Automatica Git ^& Vercel
echo ========================================================
echo.

set MSG=%~1
if "%MSG%"=="" set MSG=chore: atualizacoes e sincronizacao automatica do TitanNova Fit

echo [1/3] Adicionando arquivos modificados (git add)...
git add .

echo [2/3] Criando commit local (git commit)...
git commit -m "%MSG%"

echo [3/3] Enviando para o GitHub e Vercel (git push)...
git push origin main

echo.
if %ERRORLEVEL% EQU 0 (
    echo ========================================================
    echo   [SUCESSO] Alterações enviadas para o GitHub e Vercel!
    echo ========================================================
) else (
    echo ========================================================
    echo   [ATENÇÃO] Se for o primeiro envio, confirme o login
    echo   na janela do navegador / GitHub.
    echo ========================================================
)
echo.
echo Pressione qualquer tecla para fechar esta janela...
pause > nul
