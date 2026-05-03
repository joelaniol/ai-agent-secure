# AI Agent Secure release ZIP packaging
# Purpose: create a versioned GitHub Release asset from the current committed build manifest.
# Scope: source version bumps stay in AppInfo.cs/build-gui.ps1; this script only packages artifacts.

param(
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-VersionManifest {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "VERSION file not found: $Path"
    }

    $values = @{}
    foreach ($line in Get-Content -Path $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') {
            continue
        }
        $parts = $line.Split('=', 2)
        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    foreach ($key in @("product", "version", "build", "built_utc")) {
        if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
            throw "VERSION is missing required key: $key"
        }
    }

    return $values
}

function Get-GitValue {
    param([string[]]$GitArgs)

    try {
        $value = (& git @GitArgs 2>$null)
        $exitCode = $LASTEXITCODE
    }
    catch {
        return "unknown"
    }

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
        return "unknown"
    }
    return ($value | Select-Object -First 1).Trim()
}

function Assert-ChildPath {
    param(
        [string]$Path,
        [string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if (-not $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Release output path is outside the expected directory: $fullPath"
    }
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Remove-OldReleasePackages {
    param([string]$DistDir)

    $patterns = @(
        "ai-agent-secure-v*-windows.zip",
        "ai-agent-secure-v*-windows.zip.sha256"
    )

    foreach ($pattern in $patterns) {
        foreach ($file in Get-ChildItem -LiteralPath $DistDir -Filter $pattern -File -ErrorAction SilentlyContinue) {
            Assert-ChildPath -Path $file.FullName -Root $DistDir
            Remove-Item -LiteralPath $file.FullName -Force
            Write-Host "Altes Release-Paket entfernt: $($file.Name)" -ForegroundColor DarkGray
        }
    }
}

$repoRoot = $PSScriptRoot
$distDir = Join-Path $repoRoot "dist"
$versionPath = Join-Path $repoRoot "VERSION"
$releaseNotesPath = Join-Path $repoRoot "RELEASE_NOTES.md"
$exePath = Join-Path $distDir "shell-secure-gui.exe"
$fallbackExePath = Join-Path $distDir "shell-secure-gui-new.exe"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "build-gui.ps1") -NoVersionFileUpdate
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    $packageExePath = $exePath
    $hasExe = Test-Path -LiteralPath $exePath
    $hasFallbackExe = Test-Path -LiteralPath $fallbackExePath
    if ($hasFallbackExe -and (-not $hasExe -or (Get-Item -LiteralPath $fallbackExePath).LastWriteTimeUtc -gt (Get-Item -LiteralPath $exePath).LastWriteTimeUtc)) {
        $packageExePath = $fallbackExePath
        Write-Host "Nutze frisch gebaute Fallback-EXE: $fallbackExePath" -ForegroundColor Yellow
    }
    elseif (-not $hasExe) {
        throw "GUI executable not found: $exePath"
    }

    $manifest = Read-VersionManifest -Path $versionPath
    $version = $manifest["version"]
    $build = $manifest["build"]
    $safeVersion = $version -replace '[^0-9A-Za-z._-]', '-'
    $safeBuild = $build -replace '[^0-9A-Za-z._-]', '-'
    $releaseBase = "ai-agent-secure-v$safeVersion-build-$safeBuild-windows"

    if (-not (Test-Path -LiteralPath $distDir)) {
        New-Item -ItemType Directory -Path $distDir | Out-Null
    }

    Remove-OldReleasePackages -DistDir $distDir

    $stageDir = Join-Path $distDir $releaseBase
    $zipPath = Join-Path $distDir ($releaseBase + ".zip")
    $zipShaPath = Join-Path $distDir ($releaseBase + ".zip.sha256")
    Assert-ChildPath -Path $stageDir -Root $distDir
    Assert-ChildPath -Path $zipPath -Root $distDir
    Assert-ChildPath -Path $zipShaPath -Root $distDir

    foreach ($path in @($stageDir, $zipPath, $zipShaPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    New-Item -ItemType Directory -Path $stageDir | Out-Null

    Copy-Item -LiteralPath $packageExePath -Destination (Join-Path $stageDir "shell-secure-gui.exe")
    Copy-Item -LiteralPath $versionPath -Destination (Join-Path $stageDir "VERSION")
    Copy-Item -LiteralPath (Join-Path $repoRoot "README.md") -Destination (Join-Path $stageDir "README.md")
    Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $stageDir "LICENSE")
    Copy-Item -LiteralPath (Join-Path $repoRoot "CONTRIBUTING.md") -Destination (Join-Path $stageDir "CONTRIBUTING.md")
    if (Test-Path -LiteralPath $releaseNotesPath) {
        Copy-Item -LiteralPath $releaseNotesPath -Destination (Join-Path $stageDir "RELEASE_NOTES.md")
    }

    $commit = Get-GitValue -GitArgs @("rev-parse", "--short=12", "HEAD")
    $tag = Get-GitValue -GitArgs @("describe", "--tags", "--exact-match", "HEAD")
    $packageUtc = [System.DateTime]::UtcNow.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    $releaseText = @"
$($manifest["product"])

Version: $version
Build: $build
Built UTC: $($manifest["built_utc"])
Commit: $commit
Tag: $tag
Package UTC: $packageUtc

Run shell-secure-gui.exe to start AI Agent Secure.
Project: https://github.com/joelaniol/ai-agent-secure
"@
    if (Test-Path -LiteralPath $releaseNotesPath) {
        $notesText = Get-Content -LiteralPath $releaseNotesPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($notesText)) {
            $releaseText = $releaseText.TrimEnd() + "`n`nRelease notes:`n`n" + $notesText.TrimEnd() + "`n"
        }
    }
    [IO.File]::WriteAllText((Join-Path $stageDir "RELEASE.txt"), ($releaseText.TrimEnd() + "`n"), $utf8NoBom)

    $sumLines = @()
    $packageFiles = @("shell-secure-gui.exe", "VERSION", "README.md", "LICENSE", "CONTRIBUTING.md", "RELEASE.txt")
    if (Test-Path -LiteralPath (Join-Path $stageDir "RELEASE_NOTES.md")) {
        $packageFiles += "RELEASE_NOTES.md"
    }
    foreach ($fileName in $packageFiles) {
        $filePath = Join-Path $stageDir $fileName
        $sumLines += "$(Get-Sha256 -Path $filePath)  $fileName"
    }
    [IO.File]::WriteAllText((Join-Path $stageDir "SHA256SUMS.txt"), (($sumLines -join "`n") + "`n"), $utf8NoBom)

    Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

    $zipHash = Get-Sha256 -Path $zipPath
    [IO.File]::WriteAllText($zipShaPath, "$zipHash  $(Split-Path -Leaf $zipPath)`n", $utf8NoBom)

    Remove-Item -LiteralPath $stageDir -Recurse -Force

    Write-Host "Release ZIP: $zipPath" -ForegroundColor Green
    Write-Host "SHA256:      $zipShaPath" -ForegroundColor Green
}
finally {
    Pop-Location
}
