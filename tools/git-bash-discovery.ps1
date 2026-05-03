# Read this file first when changing Git Bash discovery outside the Bash runtime.
# Purpose: keep PowerShell-side Git Bash lookup aligned across build and test entrypoints.
# Scope: the Windows batch launcher and GUI installer still own their native discovery code.

function Test-IsGitBashPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    try {
        $full = [System.IO.Path]::GetFullPath($Path).Replace('/', '\')
        if (-not (Test-Path -LiteralPath $full)) {
            return $false
        }

        if (-not $full.EndsWith("\bash.exe", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        $systemBash = Join-Path $env:WINDIR "System32\bash.exe"
        if ($full.Equals($systemBash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }

        if ($full -match '(?i)\\Git\\(?:usr\\)?bin\\bash\.exe$') {
            return $true
        }

        return Test-HasGitForWindowsLayout -FullPath $full
    }
    catch {
        return $false
    }
}

function Test-HasGitForWindowsLayout {
    param([string]$FullPath)

    try {
        $dir = [System.IO.Path]::GetDirectoryName($FullPath)
        if ([string]::IsNullOrWhiteSpace($dir)) {
            return $false
        }

        foreach ($root in @(
            [System.IO.Path]::GetFullPath((Join-Path $dir "..")),
            [System.IO.Path]::GetFullPath((Join-Path $dir "..\.."))
        )) {
            if (Test-Path -LiteralPath (Join-Path $root "cmd\git.exe")) {
                return $true
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function Get-GitBashCandidates {
    param(
        [string]$ProgramFiles = $env:ProgramFiles,
        [string]$ProgramFilesX86 = ${env:ProgramFiles(x86)},
        [string]$LocalAppData = $env:LOCALAPPDATA
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @(
        @{ Root = $ProgramFiles; Rel = "Git\bin\bash.exe" },
        @{ Root = $ProgramFiles; Rel = "Git\usr\bin\bash.exe" },
        @{ Root = $ProgramFilesX86; Rel = "Git\bin\bash.exe" },
        @{ Root = $ProgramFilesX86; Rel = "Git\usr\bin\bash.exe" },
        @{ Root = $LocalAppData; Rel = "Programs\Git\bin\bash.exe" },
        @{ Root = $LocalAppData; Rel = "Programs\Git\usr\bin\bash.exe" }
    )) {
        if (-not [string]::IsNullOrWhiteSpace($entry.Root)) {
            [void]$candidates.Add((Join-Path $entry.Root $entry.Rel))
        }
    }

    return $candidates.ToArray()
}

function Get-GitBashPath {
    param(
        [string]$ProgramFiles = $env:ProgramFiles,
        [string]$ProgramFilesX86 = ${env:ProgramFiles(x86)},
        [string]$LocalAppData = $env:LOCALAPPDATA,
        [string]$CommandPath
    )

    foreach ($candidate in Get-GitBashCandidates -ProgramFiles $ProgramFiles -ProgramFilesX86 $ProgramFilesX86 -LocalAppData $LocalAppData) {
        if (Test-IsGitBashPath -Path $candidate) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }

    if (-not $PSBoundParameters.ContainsKey("CommandPath")) {
        $cmd = Get-Command bash -ErrorAction SilentlyContinue
        if ($cmd) {
            $CommandPath = $cmd.Source
        }
    }

    if (Test-IsGitBashPath -Path $CommandPath) {
        return [System.IO.Path]::GetFullPath($CommandPath)
    }

    return $null
}
