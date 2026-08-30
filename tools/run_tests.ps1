# Runs every headless check. Developer tool - never shipped.
#
#   ./tools/run_tests.ps1
#   ./tools/run_tests.ps1 -Godot "D:/path/to/Godot_console.exe"
#
# The editor is found in this order: the -Godot parameter, then $env:GODOT, then
# PATH. tools/run_tests.sh is the same thing for git-bash.

[CmdletBinding()]
param(
    [string]$Godot = ""
)

$ErrorActionPreference = "Stop"

if (-not $Godot) { $Godot = $env:GODOT }
if (-not $Godot) { $Godot = "godot" }

$root = Split-Path -Parent $PSScriptRoot

# Resolve the editor: an explicit path first, otherwise whatever PATH offers.
$editor = $null
if (Test-Path -LiteralPath $Godot) {
    $editor = (Resolve-Path -LiteralPath $Godot).Path
} else {
    try { $editor = (Get-Command $Godot -ErrorAction Stop).Source } catch { }
}

if (-not $editor) {
    Write-Host "Godot not found at '$Godot'." -ForegroundColor Red
    Write-Host 'Pass -Godot "<path to the editor exe>", or set $env:GODOT.'
    exit 127
}

$suites = @(
    @{ Scene = "res://tools/smoke_test.tscn";       Label = "core systems" }
    @{ Scene = "res://tools/ui_smoke_test.tscn";    Label = "UI components and touch targets" }
    @{ Scene = "res://tools/warung_test.tscn";      Label = "Warung end to end" }
    @{ Scene = "res://tools/kebun_test.tscn";       Label = "Kebun end to end" }
    @{ Scene = "res://tools/integration_test.tscn"; Label = "hub to mini-game and back" }
)

# Godot writes test results to stdout and parse errors to stderr, and Windows
# PowerShell mangles a native command's stderr when it is merged inline. Running
# through Start-Process with both streams going to files sidesteps that and gives
# a trustworthy exit code.
function Invoke-Godot {
    param([string]$Editor, [string]$Arguments)

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $Editor -ArgumentList $Arguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        $lines = @()
        if (Test-Path $outFile) { $lines += Get-Content $outFile }
        if (Test-Path $errFile) { $lines += Get-Content $errFile }

        return @{ ExitCode = $process.ExitCode; Lines = $lines }
    } finally {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

# Import once so the class cache and .import files are current. Without this the
# first suite pays for it and can report spurious parse errors.
Invoke-Godot -Editor $editor -Arguments ('--headless --path "{0}" --import' -f $root) | Out-Null

$failed = 0
foreach ($suite in $suites) {
    Write-Host ""
    Write-Host "=== $($suite.Label) ==="

    $result = Invoke-Godot -Editor $editor `
        -Arguments ('--headless --path "{0}" "{1}"' -f $root, $suite.Scene)

    $result.Lines | Select-String -Pattern '^  FAIL|^=== \d+ passed' | ForEach-Object { Write-Host $_.Line }

    if ($result.ExitCode -ne 0) {
        Write-Host "FAILED (exit $($result.ExitCode)): $($suite.Label)" -ForegroundColor Red
        $result.Lines | Select-String -Pattern 'SCRIPT ERROR|Parse Error' |
            Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.Line)" }
        $failed = 1
    }
}

# The budget check is last and is not headless: it reads the renderer's own
# counters after a frame has actually been drawn, and a headless run draws
# nothing. It is in this script rather than left to be remembered because the
# village went 70% over the triangle budget in a single afternoon of art work,
# and nothing said so until it was measured.
Write-Host ""
Write-Host "=== village performance budget ==="
$budget = Invoke-Godot -Editor $editor `
    -Arguments ('--path "{0}" res://tools/scene_budget.tscn -- hub' -f $root)
$budget.Lines | Select-String -Pattern '^  (draw calls|triangles)|^=== (within|OVER)' |
    ForEach-Object { Write-Host $_.Line }
if ($budget.ExitCode -ne 0) {
    Write-Host "OVER BUDGET (PLAN.md 4.2)" -ForegroundColor Red
    $failed = 1
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "All suites passed." -ForegroundColor Green
} else {
    Write-Host "Some suites failed. Re-run one on its own to see every check:" -ForegroundColor Red
    Write-Host '  & $env:GODOT --headless --path . res://tools/<suite>.tscn'
}
exit $failed
