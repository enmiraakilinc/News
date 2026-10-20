$ErrorActionPreference = 'Stop'
$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$appPath = Join-Path $workspaceRoot 'flutter_application_1'
$versionLine = Get-Content -LiteralPath (Join-Path $appPath 'pubspec.yaml') | Where-Object { $_ -match '^version:' }
if ($versionLine -notmatch '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Invalid app version.' }
$releaseVersion = $Matches[1]
$releaseCode = $Matches[2]
$outputDir = [IO.Path]::GetFullPath((Join-Path $workspaceRoot "artifacts/releases/$releaseVersion"))
if (!$outputDir.StartsWith($workspaceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output escaped workspace.' }
$env:JAVA_HOME = 'C:/Users/mkund/jdk17'
$flutterPath = 'C:/Users/mkund/flutter/bin/flutter.bat'
$aaptPath = 'C:/Users/mkund/AppData/Local/Android/Sdk/build-tools/36.0.0/aapt.exe'
$signerPath = 'C:/Users/mkund/AppData/Local/Android/Sdk/build-tools/36.0.0/apksigner.bat'
# Build Android only, without unrelated desktop plugin symlinks.
$previousWindowsFlag = [Environment]::GetEnvironmentVariable('FLUTTER_WINDOWS', 'Process')
$env:FLUTTER_WINDOWS = 'false'
Push-Location -LiteralPath $appPath
try {
    & $flutterPath build apk --release --target-platform android-arm64 --tree-shake-icons
    if ($LASTEXITCODE -ne 0) { throw 'Release build failed.' }
    $builtApk = Join-Path $appPath 'build/app/outputs/flutter-apk/app-release.apk'
    $details = & $aaptPath dump badging $builtApk
    if ($LASTEXITCODE -ne 0) { throw 'APK inspection failed.' }
    $packageLine = $details | Select-Object -First 1
    if ($packageLine -notmatch "versionCode='$releaseCode'" -or $packageLine -notmatch "versionName='$releaseVersion'") { throw 'Unexpected APK version.' }
    if (($details | Where-Object { $_.StartsWith('native-code:') }) -ne "native-code: 'arm64-v8a'") { throw 'Unexpected APK ABI.' }
    if ($details -contains 'application-debuggable') { throw 'Debuggable APK rejected.' }
    $certificates = (& $signerPath verify --print-certs $builtApk) -join "`n"
    if ($LASTEXITCODE -ne 0 -or !$certificates.Contains('c9419e64533312afc0430f961354c869619fa6d3500097390e1bf537671bd08c')) { throw 'Signing certificate mismatch.' }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $filename = "Neural-Haber-$releaseVersion-arm64.apk"
    $outputApk = Join-Path $outputDir $filename
    Copy-Item -LiteralPath $builtApk -Destination $outputApk
    $size = (Get-Item -LiteralPath $outputApk).Length
    $report = [ordered]@{version=$releaseVersion;code=[int]$releaseCode;filename=$filename;bytes=$size;MB=[Math]::Round($size/1000000,2);sha256=(Get-FileHash -LiteralPath $outputApk -Algorithm SHA256).Hash.ToLower();abi=@('arm64-v8a');signingVerified=$true;debuggable=$false;published=$false;physicalDeviceTested=$false}
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputDir 'build-report.json') -Encoding UTF8
    Write-Output "Verified signed ARM64 release: $releaseVersion ($releaseCode), $($report.MB) MB. Publication pending."
} finally {
    Pop-Location
    [Environment]::SetEnvironmentVariable('FLUTTER_WINDOWS', $previousWindowsFlag, 'Process')
}
