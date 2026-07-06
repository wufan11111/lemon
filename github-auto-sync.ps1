$ErrorActionPreference = "Continue"

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repo

$ignoreDirs = @(
    "\.git\",
    "\.vercel\",
    "\.npm-cache\",
    "\work\",
    "\.agents\",
    "\.codex\"
)

function Test-IgnoredPath([string]$path) {
    $normalized = $path.Replace("/", "\")
    foreach ($dir in $ignoreDirs) {
        if ($normalized.Contains($dir)) { return $true }
    }
    return $false
}

function Invoke-GitSync {
    param([string]$reason)

    Start-Sleep -Seconds 2

    $status = git status --porcelain
    if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
        return
    }

    git add -A
    git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "Auto sync $timestamp"
    git push

    Write-Host "Synced to GitHub at $timestamp ($reason)"
}

Write-Host "GitHub auto-sync is running for: $repo"
Write-Host "Close this window to stop syncing."

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $repo
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

$timer = New-Object System.Timers.Timer
$timer.Interval = 3000
$timer.AutoReset = $false

$pendingReason = "change"
$timer.add_Elapsed({
    Invoke-GitSync -reason $script:pendingReason
})

$action = {
    if (Test-IgnoredPath $Event.SourceEventArgs.FullPath) {
        return
    }
    $script:pendingReason = $Event.SourceEventArgs.ChangeType
    $timer.Stop()
    $timer.Start()
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Deleted -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

try {
    while ($true) {
        Start-Sleep -Seconds 1
    }
} finally {
    $watcher.EnableRaisingEvents = $false
    $watcher.Dispose()
    $timer.Dispose()
}
