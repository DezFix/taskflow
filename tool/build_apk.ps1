# Собирает release-APK отдельным процессом и оставляет отметку о финале.
# Отдельный процесс нужен потому, что фоновая задача в PowerShell
# заканчивается вместе с сессией, не дождавшись сборки.

$ErrorActionPreference = 'Continue'
$env:GRADLE_USER_HOME = 'D:\CODE\Task-work\.toolchain\gradle'
$env:JAVA_HOME = 'D:\CODE\Task-work\.toolchain\jdk17'
$env:ANDROID_SDK_ROOT = 'D:\Android\Sdk'
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:PUB_CACHE = 'D:\CODE\Task-work\.toolchain\pub-cache'

$root = 'D:\CODE\Task-work\taskflow'
$log = Join-Path $root 'buildlog.txt'
$done = Join-Path $root 'build.done'

Set-Location $root
Remove-Item -Force $done -ErrorAction SilentlyContinue

# Флаг, чтобы вывод писался построчно: иначе Tee-Object держит
# весь лог в памяти до конца сборки и его не видно при зависании.
& 'D:\CODE\Task-work\.toolchain\flutter\bin\flutter.bat' build apk --release --no-pub *>&1 |
    ForEach-Object { $_ | Tee-Object -FilePath $log -Append }

"EXIT=$LASTEXITCODE" | Out-File -FilePath $done -Encoding UTF8
