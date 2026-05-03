# AI Agent Secure GUI kompilieren
# Liest Bash-Scripts ein, bettet sie als C#-Strings ein, kompiliert nach dist/
# Purpose: Single source for GUI builds and embedded-script round-trip checks.
# Scope: If lib/protection.sh or config/default.conf changes, this build must prove the shipped EXE matches them.

param(
    [switch]$NoVersionFileUpdate
)

. (Join-Path $PSScriptRoot "tools\git-bash-discovery.ps1")

$cscDir = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319"
$csc = Join-Path $cscDir "csc.exe"
$wpf = Join-Path $cscDir "WPF"

function Convert-ToBashPath {
    param([string]$FilePath)

    $resolved = (Resolve-Path $FilePath).Path.Replace('\', '/')
    if ($resolved -match '^([A-Za-z]):(.*)$') {
        return "/$($matches[1].ToLower())$($matches[2])"
    }
    return $resolved
}

function Assert-BashSyntax {
    param(
        [string]$BashPath,
        [string]$FilePath
    )

    if (-not $BashPath) {
        throw "Kein bash gefunden. Der Build-Check fuer eingebettete Shell-Scripts kann nicht ausgefuehrt werden."
    }

    $normalized = Convert-ToBashPath -FilePath $FilePath
    & $BashPath --noprofile --norc -lc "bash -n '$normalized'"
    if ($LASTEXITCODE -ne 0) {
        throw "Bash-Syntaxpruefung fehlgeschlagen: $FilePath"
    }
}

function Get-EmbeddedConstants {
    param([string]$AssemblyPath)

    $assembly = [System.Reflection.Assembly]::LoadFile((Resolve-Path $AssemblyPath))
    $flags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static
    $type = $assembly.GetType("EmbeddedScripts", $true)

    return @{
        ProtectionSh = [string]$type.GetField("ProtectionSh", $flags).GetRawConstantValue()
        DefaultConf  = [string]$type.GetField("DefaultConf",  $flags).GetRawConstantValue()
        EnvLoaderSh  = [string]$type.GetField("EnvLoaderSh",  $flags).GetRawConstantValue()
    }
}

function Assert-EmbeddedRoundTrip {
    param(
        [string]$AssemblyPath,
        [string]$BashPath,
        [string]$ExpectedProtectionSh,
        [string]$ExpectedDefaultConf,
        [string]$ExpectedEnvLoaderSh
    )

    $constants = Get-EmbeddedConstants -AssemblyPath $AssemblyPath

    if ($constants.ProtectionSh -cne $ExpectedProtectionSh) {
        throw "EmbeddedScripts.ProtectionSh weicht vom Quelltext ab."
    }
    if ($constants.DefaultConf -cne $ExpectedDefaultConf) {
        throw "EmbeddedScripts.DefaultConf weicht vom Quelltext ab."
    }
    if ($constants.EnvLoaderSh -cne $ExpectedEnvLoaderSh) {
        throw "EmbeddedScripts.EnvLoaderSh weicht vom erwarteten Loader ab."
    }

    $tempDir = Join-Path $PSScriptRoot ".build-check"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }
    $tempProtection = Join-Path $tempDir "protection.roundtrip.sh"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($tempProtection, $constants.ProtectionSh, $utf8NoBom)
    try {
        Assert-BashSyntax -BashPath $BashPath -FilePath $tempProtection
    }
    finally {
        Remove-Item $tempProtection -ErrorAction SilentlyContinue
        if ((Test-Path $tempDir) -and -not (Get-ChildItem $tempDir -Force | Select-Object -First 1)) {
            Remove-Item $tempDir -ErrorAction SilentlyContinue
        }
    }
}

function Get-BuildCommit {
    $commit = (& git rev-parse --short=12 HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
        return "unknown"
    }
    return $commit.Trim()
}

function Get-CSharpStringConstant {
    param(
        [string]$FilePath,
        [string]$Name
    )

    $source = Get-Content -Raw -Path $FilePath
    $pattern = 'public\s+const\s+string\s+' + [regex]::Escape($Name) + '\s*=\s*"([^"]*)"\s*;'
    if ($source -notmatch $pattern) {
        throw "C#-Versionskonstante nicht gefunden: $Name in $FilePath"
    }
    return $matches[1]
}

function Read-VersionManifest {
    $path = Join-Path $PSScriptRoot "VERSION"
    if (-not (Test-Path -LiteralPath $path)) {
        return $null
    }

    $values = @{}
    foreach ($line in Get-Content -Path $path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') {
            continue
        }
        $parts = $line.Split('=', 2)
        $values[$parts[0].Trim()] = $parts[1].Trim()
    }

    if (-not $values.ContainsKey("build") -or -not $values.ContainsKey("built_utc")) {
        return $null
    }

    return [pscustomobject]@{
        BuildId = $values["build"]
        BuildTimeUtc = $values["built_utc"]
    }
}

function New-VersionMetadata {
    param(
        [string]$ProductName,
        [string]$Version,
        [switch]$UseExistingManifest
    )

    if ($UseExistingManifest) {
        $existing = Read-VersionManifest
        if ($existing) {
            return [pscustomobject]@{
                ProductName = $ProductName
                Version = $Version
                BuildId = $existing.BuildId
                BuildTimeUtc = $existing.BuildTimeUtc
            }
        }
    }

    $buildUtc = [System.DateTime]::UtcNow
    return [pscustomobject]@{
        ProductName = $ProductName
        Version = $Version
        BuildId = $buildUtc.ToString("yyyyMMdd.HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
        BuildTimeUtc = $buildUtc.ToString("yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
}

function Write-VersionFiles {
    param(
        [pscustomobject]$Metadata
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $versionPath = Join-Path $PSScriptRoot "VERSION"
    $versionText = @"
product=$($Metadata.ProductName)
version=$($Metadata.Version)
build=$($Metadata.BuildId)
built_utc=$($Metadata.BuildTimeUtc)
"@
    [IO.File]::WriteAllText($versionPath, ($versionText.TrimEnd() + "`n"), $utf8NoBom)

    $readmePath = Join-Path $PSScriptRoot "README.md"
    $readme = [IO.File]::ReadAllText($readmePath)
    $start = "<!-- ai-agent-secure-version:start -->"
    $end = "<!-- ai-agent-secure-version:end -->"
$block = @"
$start
**Current version:** ``$($Metadata.Version)`` | Build ``$($Metadata.BuildId)`` | Built ``$($Metadata.BuildTimeUtc) UTC``

See [VERSION](VERSION) for the build manifest.
$end
"@.Trim()

    $markerPattern = "(?s)" + [regex]::Escape($start) + ".*?" + [regex]::Escape($end)
    if ([regex]::IsMatch($readme, $markerPattern)) {
        $readme = [regex]::Replace($readme, $markerPattern, $block)
    }
    elseif ($readme.StartsWith("# AI Agent Secure")) {
        $rest = $readme.Substring("# AI Agent Secure".Length).TrimStart("`r", "`n")
        $readme = "# AI Agent Secure`n`n$block`n`n$rest"
    }
    else {
        throw "README-Titel nicht gefunden; Versionsblock kann nicht aktualisiert werden."
    }

    [IO.File]::WriteAllText($readmePath, $readme, $utf8NoBom)
}

function Remove-ExistingBuildOutput {
    param(
        [string]$Path,
        [string]$DistDir
    )

    $target = [System.IO.Path]::GetFullPath($Path)
    $dist = [System.IO.Path]::GetFullPath($DistDir).TrimEnd('\', '/')
    if (-not $target.StartsWith($dist + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Build-Artefakt liegt ausserhalb von dist/: $target"
    }

    if (-not (Test-Path -LiteralPath $target)) {
        return $true
    }

    try {
        Remove-Item -LiteralPath $target -Force -ErrorAction Stop
        Write-Host "Alte EXE entfernt: $target" -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Host "Alte EXE konnte nicht entfernt werden: $target" -ForegroundColor Yellow
        return $false
    }
}

$bash = Get-GitBashPath
$buildExitCode = 0
$pushedLocation = $false

Push-Location $PSScriptRoot
$pushedLocation = $true
try {

# ── Icon bereitstellen ──
$iconPath = Join-Path $PSScriptRoot "shell-secure.ico"
$iconMaker = Join-Path $PSScriptRoot "make-icon.ps1"
if (Test-Path -LiteralPath $iconMaker) {
    Write-Host "Generiere Icon..." -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File $iconMaker
    if ($LASTEXITCODE -ne 0) {
        throw "Icon-Generierung fehlgeschlagen."
    }
}
elseif (Test-Path -LiteralPath $iconPath) {
    Write-Host "Nutze vorhandenes Icon..." -ForegroundColor Cyan
}
else {
    throw "Icon fehlt: $iconPath"
}

# ── Bash-Scripts einlesen ──
Write-Host "Lese eingebettete Scripts..." -ForegroundColor Cyan

# Die Schutz-Schicht ist seit dem Slice-Refactor in lib/protection-*.sh
# aufgeteilt; lib/protection.sh ist nur ein Loader fuer Dev/Test. Build und
# Install konkatenieren die Slices in dieser Reihenfolge in eine einzige
# protection.sh, die im Runtime-Install genau wie vor dem Refactor liegt.
# Die Reihenfolge ist relevant: core liefert die Variablen + Helper, die
# alle anderen brauchen; tokenize laeuft danach, weil delete und ps die
# Tokens nutzen.
$protectionSlices = @(
    "lib\protection-core.sh",
    "lib\protection-i18n.sh",
    "lib\protection-tokenize.sh",
    "lib\protection-delete.sh",
    "lib\protection-ps.sh",
    "lib\protection-git.sh",
    "lib\protection-env.sh"
)
$protectionSh = ""
foreach ($slice in $protectionSlices) {
    $sliceFull = Join-Path $PSScriptRoot $slice
    Assert-BashSyntax -BashPath $bash -FilePath $sliceFull
    $protectionSh += Get-Content -Raw $sliceFull
}
# Aktivierungs-Marker am Ende des konkatenierten Blobs (im Loader-Eintrag
# steht der gleiche Export, damit Source-Level-Tests konsistent sind).
$protectionSh += "`nexport SHELL_SECURE_ACTIVE=true`n"
$defaultConf  = Get-Content -Raw "config\default.conf"
$productName = Get-CSharpStringConstant -FilePath "AppInfo.cs" -Name "ProductName"
$productVersion = Get-CSharpStringConstant -FilePath "AppInfo.cs" -Name "Version"
$buildMetadata = New-VersionMetadata -ProductName $productName -Version $productVersion -UseExistingManifest:$NoVersionFileUpdate
if (-not $NoVersionFileUpdate) {
    Write-VersionFiles -Metadata $buildMetadata
    Write-Host "Version aktualisiert: $($buildMetadata.Version) Build $($buildMetadata.BuildId)" -ForegroundColor Cyan
}
$buildCommit = Get-BuildCommit
$buildId = $buildMetadata.BuildId
$buildTimeUtc = $buildMetadata.BuildTimeUtc
$envLoaderSh  = @'
#!/bin/bash
prev_file="$HOME/.shell-secure/previous-bash-env.txt"
if [ -f "$prev_file" ]; then
    IFS= read -r prev < "$prev_file"
    if [ -n "$prev" ] && [ "$prev" != "$HOME/.shell-secure/env-loader.sh" ] && [ -f "$prev" ]; then
        source "$prev"
    fi
fi
if [ -f "$HOME/.shell-secure/protection.sh" ]; then
    source "$HOME/.shell-secure/protection.sh"
fi
'@

# ── EmbeddedScripts.cs generieren ──
$embedded = @"
// Auto-generiert von build-gui.ps1 - nicht manuell bearbeiten
static class EmbeddedScripts
{
    public const string Version = @"$($productVersion.Replace('"', '""'))";

    public const string BuildId = @"$($buildId.Replace('"', '""'))";

    public const string BuildCommit = @"$($buildCommit.Replace('"', '""'))";

    public const string BuildTimeUtc = @"$($buildTimeUtc.Replace('"', '""'))";

    public const string ProtectionSh = @"$($protectionSh.Replace('"', '""'))";

    public const string DefaultConf = @"$($defaultConf.Replace('"', '""'))";

    public const string EnvLoaderSh = @"$($envLoaderSh.Replace('"', '""'))";

    public const string BashrcBlock = @"
# >>> shell-secure >>>
# AI Agent Secure: Shell-Secure Schutz-Core
if [ -f ""`$HOME/.shell-secure/protection.sh"" ]; then
    source ""`$HOME/.shell-secure/protection.sh""
fi
# <<< shell-secure <<<
";
}
"@

Set-Content -Path "EmbeddedScripts.cs" -Value $embedded -Encoding UTF8

# ── Dist-Ordner und Build-Ziel vorbereiten ──
$distDir = Join-Path $PSScriptRoot "dist"
if (!(Test-Path -LiteralPath $distDir)) { New-Item -ItemType Directory -Path $distDir | Out-Null }

# Kanonischer Name - matcht README/Release-Download. Vor dem Compile
# werden alte Artefakte entfernt, damit ein fehlgeschlagener Build nicht
# versehentlich als frisches Ergebnis gelesen wird. Falls die EXE noch
# laeuft (File-Lock), Fallback mit Suffix, damit der Build nicht scheitert.
$outName = "shell-secure-gui.exe"
$out = Join-Path $distDir $outName
$fallbackOutName = "shell-secure-gui-new.exe"
$fallbackOut = Join-Path $distDir $fallbackOutName
[void](Remove-ExistingBuildOutput -Path $fallbackOut -DistDir $distDir)
if (-not (Remove-ExistingBuildOutput -Path $out -DistDir $distDir)) {
    $outName = $fallbackOutName
    $out = $fallbackOut
    if (-not (Remove-ExistingBuildOutput -Path $out -DistDir $distDir)) {
        throw "Build-Ziel ist gesperrt. Bitte laufende AI Agent Secure GUI schliessen: $out"
    }
    Write-Host "Alte EXE laeuft noch, baue als $outName" -ForegroundColor Yellow
}

# ── Kompilieren ──
Write-Host "Kompiliere AI Agent Secure GUI..." -ForegroundColor Cyan
$src = @(
    Get-ChildItem -Path . -Filter "*.cs" -File |
        Where-Object { $_.Name -ne "EmbeddedScripts.cs" } |
        Sort-Object Name |
        ForEach-Object { $_.Name }
) + @("EmbeddedScripts.cs")

& $csc /target:winexe `
    /codepage:65001 `
    "/lib:$wpf" `
    /reference:PresentationFramework.dll `
    /reference:PresentationCore.dll `
    /reference:WindowsBase.dll `
    /reference:System.Xaml.dll `
    /reference:System.Windows.Forms.dll `
    /reference:System.Drawing.dll `
    /win32icon:shell-secure.ico `
    /out:$out /optimize+ /nologo $src

$compileExitCode = $LASTEXITCODE
if ($compileExitCode -eq 0) {
    Assert-EmbeddedRoundTrip -AssemblyPath $out -BashPath $bash -ExpectedProtectionSh $protectionSh -ExpectedDefaultConf $defaultConf -ExpectedEnvLoaderSh $envLoaderSh
    $size = [math]::Round((Get-Item $out).Length / 1KB, 1)
    Write-Host "Fertig: $out ($size KB)" -ForegroundColor Green
    Write-Host "Embedded-Script-Checks: OK" -ForegroundColor Green
    Write-Host ""
    Write-Host "Die EXE ist komplett eigenstaendig." -ForegroundColor DarkGray
    Write-Host "Einfach auf einen beliebigen PC kopieren und starten." -ForegroundColor DarkGray
} else {
    Write-Host "Kompilierung fehlgeschlagen!" -ForegroundColor Red
    $buildExitCode = if ($compileExitCode -ne 0) { $compileExitCode } else { 1 }
}

}
finally {
# ── Temp-Datei aufraeumen ──
    Remove-Item "EmbeddedScripts.cs" -ErrorAction SilentlyContinue

    if ($pushedLocation) {
        Pop-Location
    }
}

if ($buildExitCode -ne 0) {
    exit $buildExitCode
}
