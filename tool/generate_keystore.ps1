<#
  Создаёт ключ для подписи release-сборок Android и файл key.properties.

  Запуск из корня проекта:

    powershell -ExecutionPolicy Bypass -File tool\generate_keystore.ps1

  Ключ нужен один раз на проект: им подписываются все сборки, иначе
  сотрудникам не придётся обновлять приложение поверх старого.
#>

param(
    [string]$Alias = "upload",
    [string]$StoreFile = "upload-keystore.jks",
    [int]$ValidityDays = 10950
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $root "android"
$keytool = Join-Path $androidDir "key.properties"
$storePath = Join-Path $androidDir $StoreFile

if (-not (Test-Path $keytool)) {
    Write-Host "Файл key.properties уже существует: $keytool" -ForegroundColor Yellow
    Write-Host "Удалите его, если хотите создать новый ключ." -ForegroundColor Yellow
    return
}

# Ищем keytool: сначала в JAVA_HOME из локального toolchain, затем в системе.
$javaHome = $env:JAVA_HOME
$keytoolExe = $null

if ($javaHome) {
    $candidate = Join-Path $javaHome "bin\keytool.exe"
    if (Test-Path $candidate) { $keytoolExe = $candidate }
}
if (-not $keytoolExe) {
    $keytoolExe = (Get-Command keytool.exe -ErrorAction SilentlyContinue).Source
}
if (-not $keytoolExe) {
    Write-Host "keytool не найден. Установите JDK 17 или задайте JAVA_HOME." -ForegroundColor Red
    return
}

Write-Host "Инструмент: $keytoolExe" -ForegroundColor Cyan
Write-Host "Пароль вводите дважды — он понадобится в GitHub Secrets." -ForegroundColor Cyan

& $keytoolExe -genkeypair `
    -alias $Alias `
    -keyalg RSA `
    -keysize 2048 `
    -validity $ValidityDays `
    -keystore $storePath `
    -storetype JKS

if ($LASTEXITCODE -ne 0) {
    Write-Host "Не удалось создать ключ" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "Ключ создан: $storePath" -ForegroundColor Green
Write-Host ""
Write-Host "Следующий шаг: создайте android/key.properties" -ForegroundColor Yellow
Write-Host "Скопируйте android/key.properties.example и подставьте пароли." -ForegroundColor Yellow
Write-Host ""
Write-Host "Для CI задайте GitHub Secrets:" -ForegroundColor Yellow
Write-Host "  KEYSTORE_BASE64   — содержимое .jks в base64"
Write-Host "  KEYSTORE_PASSWORD — пароль хранилища"
Write-Host "  KEY_ALIAS        — $Alias"
Write-Host "  KEY_PASSWORD     — пароль ключа"
