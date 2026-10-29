# Sync upstream Aerial, rebuild as com.ts.launcher (Xiaomi HOME allowlist name), optionally install.
# Usage: .\update-ts-launcher.ps1 [-Tv 10.0.0.30:5555] [-Proxy 127.0.0.1:3067] [-NoInstall]
param(
    [string]$Tv = "10.0.0.30:5555",
    [string]$Proxy = "127.0.0.1:3067",
    [switch]$NoInstall
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (git remote | Select-String -Quiet "^upstream$")) {
    git remote add upstream https://github.com/pengchujin/aerial-tv.git
}
git fetch upstream
git merge upstream/main --no-edit
if ($LASTEXITCODE -ne 0) { throw "Merge conflict: resolve it (likely app/build.gradle.kts applicationId line), commit, rerun." }
git push origin HEAD

$env:JAVA_HOME = "$env:USERPROFILE\scoop\apps\temurin21-jdk\current"
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Temp\android-sdk" }
"sdk.dir=$($env:ANDROID_HOME -replace '\\','/')" | Set-Content local.properties
$h, $p = $Proxy.Split(":")
$px = "-Dhttp.proxyHost=$h -Dhttp.proxyPort=$p -Dhttps.proxyHost=$h -Dhttps.proxyPort=$p"
$env:GRADLE_OPTS = $px
.\gradlew.bat assembleStandardRelease "-PlauncherApplicationId=com.ts.launcher" --no-daemon -q "-Dorg.gradle.jvmargs=-Xmx2g $px"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$apk = "app\build\outputs\apk\standard\release\app-standard-release.apk"
Write-Host "Built: $apk"
if (-not $NoInstall) {
    adb connect $Tv
    adb -s $Tv install -r $apk
}
