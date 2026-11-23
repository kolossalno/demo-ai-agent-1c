# ==============================================================================
# build.ps1 - Build 1C:Enterprise DemoAIAgent external data processor from XML sources
# ==============================================================================
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/build.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Version 1
#   powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Version 2
#   powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -V8Path "C:\Program Files\1cv8\8.5.1.1529\bin"
# ==============================================================================

param(
    [string]$V8Path = "",
    [ValidateSet("1", "2", "all")]
    [string]$Version = "all"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

function Find-1CExecutable {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path $ExplicitPath) {
            if ((Get-Item $ExplicitPath).PSIsContainer) {
                $candidate = Join-Path $ExplicitPath "1cv8.exe"
                if (Test-Path $candidate) { return $candidate }
            } else {
                return $ExplicitPath
            }
        }
    }

    $searchRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path $_) }

    $candidates = @()
    foreach ($root in $searchRoots) {
        $v8Dir = Join-Path $root "1cv8"
        if (Test-Path $v8Dir) {
            $found = Get-ChildItem -Path $v8Dir -Filter "1cv8.exe" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "\\bin\\1cv8\.exe$" -and $_.FullName -notmatch "common" }
            $candidates += $found
        }
    }

    if ($candidates.Count -gt 0) {
        $sorted = $candidates | Sort-Object { $_.FullName } -Descending
        return $sorted[0].FullName
    }

    return $null
}

function Build-ExternalProcessor {
    param(
        [string]$ExePath,
        [string]$XmlPath,
        [string]$EpfPath
    )

    $fullXml = [System.IO.Path]::GetFullPath($XmlPath)
    $fullEpf = [System.IO.Path]::GetFullPath($EpfPath)
    $epfDir = Split-Path -Parent $fullEpf

    if (-not (Test-Path $epfDir)) {
        New-Item -ItemType Directory -Path $epfDir -Force | Out-Null
    }

    $tempDbDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "v8_epf_stub_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDbDir -Force | Out-Null
    $logPath = [System.IO.Path]::Combine($tempDbDir, "build_log.txt")

    try {
        Write-Host "  -> Creating temporary infobase..." -ForegroundColor DarkGray
        $createArgs = "CREATEINFOBASE `"File=`"$tempDbDir`";`" /DisableStartupDialogs"
        $createProc = Start-Process -FilePath $ExePath -ArgumentList $createArgs -Wait -PassThru -NoNewWindow
        if ($createProc.ExitCode -ne 0) {
            throw "Failed to create temporary 1C infobase (exit code: $($createProc.ExitCode))"
        }

        Write-Host "  -> Loading external processor from XML: $XmlPath ..." -ForegroundColor Cyan
        $buildArgs = "DESIGNER /F `"$tempDbDir`" /LoadExternalDataProcessorOrReportFromFiles `"$fullXml`" `"$fullEpf`" /Out `"$logPath`" /DisableStartupDialogs"
        $buildProc = Start-Process -FilePath $ExePath -ArgumentList $buildArgs -Wait -PassThru -NoNewWindow

        if (Test-Path $logPath) {
            $logText = Get-Content -Path $logPath -Encoding Default -ErrorAction SilentlyContinue
            if ($logText) {
                Write-Host ($logText -join [Environment]::NewLine) -ForegroundColor Gray
            }
        }

        if (-not (Test-Path $fullEpf)) {
            throw "Build failed: output file was not created ($EpfPath, exit code: $($buildProc.ExitCode))"
        }

        $size = (Get-Item $fullEpf).Length
        Write-Host "  [OK] Successfully built: $EpfPath ($size bytes)" -ForegroundColor Green
    }
    finally {
        if (Test-Path $tempDbDir) {
            Remove-Item -Path $tempDbDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "=== 1C:Enterprise DemoAIAgent Build ===" -ForegroundColor Magenta

$v8Exe = Find-1CExecutable -ExplicitPath $V8Path
if (-not $v8Exe) {
    Write-Error "1C:Enterprise platform was not found. Please specify path to 1cv8.exe via -V8Path parameter."
    exit 1
}

Write-Host "Using 1C platform: $v8Exe" -ForegroundColor DarkCyan

if ($Version -eq "1" -or $Version -eq "all") {
    Write-Host "`n[Version 1] Building DemoAIAgent..." -ForegroundColor Yellow
    Build-ExternalProcessor -ExePath $v8Exe `
        -XmlPath (Join-Path $RepoRoot "src\DemoAIAgent.xml") `
        -EpfPath (Join-Path $RepoRoot "build\DemoAIAgent.epf")
}

if ($Version -eq "2" -or $Version -eq "all") {
    Write-Host "`n[Version 2] Building DemoAIAgent_v2..." -ForegroundColor Yellow
    Build-ExternalProcessor -ExePath $v8Exe `
        -XmlPath (Join-Path $RepoRoot "src\DemoAIAgent_v2.xml") `
        -EpfPath (Join-Path $RepoRoot "build\DemoAIAgent_v2.epf")
}

Write-Host "`nBuild complete!" -ForegroundColor Green
