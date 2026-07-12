param(
    [string]$JobId = "manual",
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if (-not $Root) {
    $Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

$logPath = Join-Path $PSScriptRoot "git_backup.log"
$mutex = New-Object Threading.Mutex($false, "Local_PID_Code_Backup")
$locked = $false

function Write-BackupLog([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

try {
    $locked = $mutex.WaitOne([TimeSpan]::FromMinutes(5))
    if (-not $locked) {
        Write-BackupLog "Skipped ${JobId}: another backup is still running."
        exit 2
    }

    $remotes = @(& git -C $Root remote)
    if ($LASTEXITCODE -ne 0 -or $remotes -notcontains "origin") {
        Write-BackupLog "Skipped ${JobId}: GitHub remote 'origin' is not configured."
        exit 3
    }
    $remote = (& git -C $Root remote get-url origin)
    $userName = (& git -C $Root config user.name)
    $userEmail = (& git -C $Root config user.email)
    if (-not $userName -or -not $userEmail) {
        Write-BackupLog "Skipped ${JobId}: git user.name or user.email is not configured."
        exit 4
    }

    & git -C $Root add -A -- .
    if ($LASTEXITCODE -ne 0) { throw "git add failed." }

    & git -C $Root diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-BackupLog "No code changes for $JobId."
        exit 0
    }
    if ($LASTEXITCODE -ne 1) { throw "git diff failed." }

    $message = "auto-backup: PID task $JobId completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    & git -C $Root commit -m $message
    if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

    $branch = (& git -C $Root branch --show-current).Trim()
    if (-not $branch) { $branch = "main" }
    & git -C $Root push -u origin $branch
    if ($LASTEXITCODE -ne 0) { throw "git push failed." }

    Write-BackupLog "Pushed $JobId to $remote ($branch)."
    exit 0
} catch {
    Write-BackupLog "Failed ${JobId}: $($_.Exception.Message)"
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
