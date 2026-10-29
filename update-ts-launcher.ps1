# Sync upstream Aerial, rebuild it as com.ts.launcher (a package name some Xiaomi TV firmwares let take over HOME),
# sign it with YOUR release key, and optionally install it and publish a GitHub release.
#
# Usage:
#   .\update-ts-launcher.ps1 -KeyDir C:\path\to\keys [-Tv <ip>:5555] [-Proxy host:port] [-NoInstall] [-Publish]
#
# KeyDir must contain aerial-release.jks and signing.properties (storeFile/storePassword/keyAlias/keyPassword).
# Keep that folder private and backed up: losing it means users cannot upgrade in place.
param(
    [Parameter(Mandatory = $true)][string]$KeyDir,
    [string]$Tv = "",
    [string]$Proxy = "",
    [switch]$NoInstall,
    [switch]$Publish
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (git remote | Select-String -Quiet "^upstream$")) {
    git remote add upstream https://github.com/pengchujin/aerial-tv.git
}
git fetch upstream
git merge upstream/main --no-edit
if ($LASTEXITCODE -ne 0) { throw "Merge conflict: resolve it (likely the applicationId lines in app/build.gradle.kts), commit, rerun." }
git push origin HEAD

$env:JAVA_HOME = if ($env:JAVA_HOME) { $env:JAVA_HOME } else { "$env:USERPROFILE\scoop\apps\temurin21-jdk\current" }
if (-not $env:ANDROID_HOME) { throw "Set ANDROID_HOME to your Android SDK folder." }
"sdk.dir=$($env:ANDROID_HOME -replace '\\','/')" | Set-Content local.properties

New-Item -ItemType Directory -Force local | Out-Null
Copy-Item "$KeyDir\aerial-release.jks" local\aerial-release.jks -Force
Copy-Item "$KeyDir\signing.properties" local\signing.properties -Force

$gradleArgs = @("assembleStandardRelease", "-PlauncherApplicationId=com.ts.launcher", "--no-daemon", "-q")
if ($Proxy) {
    $h, $p = $Proxy.Split(":")
    $px = "-Dhttp.proxyHost=$h -Dhttp.proxyPort=$p -Dhttps.proxyHost=$h -Dhttps.proxyPort=$p"
    $env:GRADLE_OPTS = $px
    $gradleArgs += "-Dorg.gradle.jvmargs=-Xmx2g $px"
}
.\gradlew.bat @gradleArgs
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

$apk = "app\build\outputs\apk\standard\release\app-standard-release.apk"
$ver = (Select-String -Path app\build.gradle.kts -Pattern 'versionName = "([^"]+)"').Matches[0].Groups[1].Value
$name = "aerial-$ver-com.ts.launcher.apk"
Copy-Item $apk $name -Force
$sha = (Get-FileHash $name -Algorithm SHA256).Hash.ToLower()
Write-Host "Built $name  sha256=$sha"

if ($Tv -and -not $NoInstall) {
    adb connect $Tv
    adb -s $Tv install -r $name
}

if ($Publish) {
    $tag = "v$ver-ts"
    "$sha  $name" | Set-Content "$name.sha256"
    $notes = @"
Unofficial build of Aerial $ver (upstream: pengchujin/aerial-tv) packaged as ``com.ts.launcher``.

Why this package name: on some Xiaomi TV firmwares only allowlisted package names can take over HOME. With this name the
stock launcher can be disabled and Home goes straight to Aerial without flashing the stock desktop.

- Tested on: Redmi TV X 2026 (MiTV-MFTR0), firmware OS3.0.107. Other models/firmwares may behave differently.
- It installs as a separate app from the official ``app.orchard.tv``; it does not upgrade it. Do not run both.
- Signed with this project's own release key, not the upstream key.
- SHA256: ``$sha``
- Risk: disabling the stock launcher can leave a black screen on some firmwares. Recovery over ADB: ``pm enable com.mitv.tvhome``.
- Source change vs upstream: configurable applicationId, and the revival account type follows it.
"@
    gh release create $tag $name "$name.sha256" --title "Aerial $ver (com.ts.launcher)" --notes $notes
}
