$ErrorActionPreference = "Continue"

$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $repo "github-auto-sync.log"
$intervalSeconds = 5

Set-Location -LiteralPath $repo

function Write-Log([string]$message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $message
    Write-Host $line
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Invoke-GitCommand([string[]]$arguments) {
    $output = & git @arguments 2>&1
    $code = $LASTEXITCODE
    if ($output) {
        foreach ($line in $output) {
            Write-Log ("git {0}: {1}" -f ($arguments -join " "), $line)
        }
    }
    return $code
}

function Sync-Once {
    $status = & git status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) {
        foreach ($line in $status) { Write-Log "status failed: $line" }
        return
    }

    if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
        return
    }

    Write-Log "Detected local changes. Syncing..."

    $code = Invoke-GitCommand @("add", "-A")
    if ($code -ne 0) { return }

    & git diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Log "No staged changes after add."
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $code = Invoke-GitCommand @("commit", "-m", "Auto sync $timestamp")
    if ($code -ne 0) { return }

    $code = Invoke-GitCommand @("push")
    if ($code -eq 0) {
        Write-Log "Synced to GitHub."
    } else {
        Write-Log "Push failed. The commit is local and will retry on the next loop."
    }
}

Write-Log "GitHub auto-sync started for $repo"
Write-Log "Polling every $intervalSeconds seconds. Close this window to stop."

while ($true) {
    try {
        Sync-Once
    } catch {
        Write-Log ("Unexpected error: " + $_.Exception.Message)
    }
    Start-Sleep -Seconds $intervalSeconds
}
