$ErrorActionPreference = 'Stop'
$gatewayDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $gatewayDir
$server = Join-Path $gatewayDir 'server_ai.py'
$log = Join-Path $gatewayDir 'gateway_embedded.log'
Set-Location -LiteralPath $root

"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] embedded gateway start" | Set-Content -LiteralPath $log -Encoding UTF8
$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    & $python.Source $server *>> $log
    exit $LASTEXITCODE
}
$py = Get-Command py -ErrorAction SilentlyContinue
if ($py) {
    & $py.Source -3 $server *>> $log
    exit $LASTEXITCODE
}
"Python was not found on PATH." | Add-Content -LiteralPath $log -Encoding UTF8
exit 1
