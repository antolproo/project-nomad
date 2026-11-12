# Domaca pevnost OFFLINE: automatic RAM model selection and one-click launch (Windows).
# Requires only Windows PowerShell 5.1; portable llama.cpp + GGUF stay on the SSD.
[CmdletBinding()]
param([switch]$SelectOnly)
$ErrorActionPreference = 'Stop'
try {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $modelsDir = Join-Path $root 'data\ai'
    $cfg = Join-Path $root 'config'
    $logs = Join-Path $root 'logs'
    New-Item -ItemType Directory -Force -Path $cfg,$logs | Out-Null
    if (-not (Test-Path -LiteralPath $modelsDir -PathType Container)) {
        throw "Chyba data/ai na SSD: $modelsDir"
    }
    if ($SelectOnly -and $env:DP_TEST_RAM_GIB) {
        $ram = [long]::Parse($env:DP_TEST_RAM_GIB) * 1GB
    } else {
        $ram = [long](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    }
    if ($ram -le 0) { throw 'RAM sa nepodarilo zistit.' }
    $profile = if ($ram -le 16GB) { 'small' } else { 'large' }

    function Read-Path([string]$configPath) {
        $line = (Get-Content -LiteralPath $configPath -Encoding UTF8 -TotalCount 1).Trim()
        if (-not $line) { throw "Prazdny subor: $configPath" }
        if ([IO.Path]::IsPathRooted($line)) { return [IO.Path]::GetFullPath($line) }
        return [IO.Path]::GetFullPath((Join-Path $root $line))
    }
    $smallFile = Join-Path $cfg 'ai-model-small.txt'
    $largeFile = Join-Path $cfg 'ai-model-large.txt'
    if ((Test-Path $smallFile) -and (Test-Path $largeFile)) {
        $small = Read-Path $smallFile
        $large = Read-Path $largeFile
    } elseif ((Test-Path $smallFile) -or (Test-Path $largeFile)) {
        throw 'Konfiguracia modelov je nekompletna.'
    } else {
        $models = @(Get-ChildItem -LiteralPath $modelsDir -Recurse -File -Filter '*.gguf' |
            Where-Object { $_.Name -notmatch '(?i)(mmproj|projector|embedding|tokenizer|clip|vision|reranker)' } |
            Sort-Object Length,FullName)
        if ($models.Count -lt 2) { throw "Potrebne su aspon 2 GGUF modely; najdenych: $($models.Count)." }
        $small = $models[0].FullName
        $large = $models[-1].FullName
    }
    if (-not (Test-Path -LiteralPath $small -PathType Leaf)) { throw "Mensi model chyba: $small" }
    if (-not (Test-Path -LiteralPath $large -PathType Leaf)) { throw "Vacsi model chyba: $large" }
    if ([string]::Equals($small,$large,[StringComparison]::OrdinalIgnoreCase)) { throw 'Oba modely su rovnake.' }
    $model = if ($profile -eq 'small') { $small } else { $large }
    $port = 8099
    $portConfig = Join-Path $cfg 'ai-port.txt'
    if (Test-Path $portConfig) {
        $portText = (Get-Content -LiteralPath $portConfig -TotalCount 1).Trim()
        if (-not [int]::TryParse($portText, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Neplatny port.' }
    }
    $endpoint = "http://127.0.0.1:$port"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $cfg 'ai-active-model.txt'),$model + [Environment]::NewLine,$utf8)
    [IO.File]::WriteAllText((Join-Path $cfg 'ai-active-profile.txt'),$profile + [Environment]::NewLine,$utf8)
    [IO.File]::WriteAllText((Join-Path $cfg 'ai-endpoint.txt'),$endpoint + [Environment]::NewLine,$utf8)
    Write-Host ("RAM={0:N1} GiB | profil={1} | model={2}" -f ($ram/1GB),$profile,$model)
    if ($SelectOnly) { exit 0 }

    $env:DOMACA_OFFLINE_AI_ENDPOINT = $endpoint
    $env:DOMACA_OFFLINE_AI_MODEL = $model
    $env:DOMACA_OFFLINE_AI_PROFILE = $profile
    $serverCandidates = @(
        'apps\windows\llama-server.exe',
        'apps\windows\bin\llama-server.exe',
        'apps\windows\llama.cpp\build\bin\Release\llama-server.exe'
    )
    $server = $null
    foreach ($candidate in $serverCandidates) {
        $p = Join-Path $root $candidate
        if (Test-Path -LiteralPath $p -PathType Leaf) { $server=$p; break }
    }
    if (-not $server) {
        $dir=Join-Path $root 'apps\windows'
        if (Test-Path $dir) {
            $found=Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'llama-server.exe' | Select-Object -First 1
            if ($found) { $server=$found.FullName }
        }
    }
    if (-not $server) { throw 'Prenosny llama-server.exe na SSD nebol najdeny.' }

    $busy=$false
    $client=New-Object Net.Sockets.TcpClient
    try {
        $ar=$client.BeginConnect('127.0.0.1',$port,$null,$null)
        if ($ar.AsyncWaitHandle.WaitOne(400)) {
            try { $client.EndConnect($ar); $busy=$true } catch {}
        }
    } finally { $client.Dispose() }

    if ($busy) {
        try {
            $props=Invoke-RestMethod -Uri "$endpoint/props" -TimeoutSec 3
            $running=[string]$props.model_path
        } catch { $running='' }
        if (-not [string]::Equals($running,$model,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Port $port je obsadeny inym modelom alebo aplikaciou."
        }
    } else {
        $out=Join-Path $logs 'ai-server-windows.out.log'
        $err=Join-Path $logs 'ai-server-windows.err.log'
        $quoted='"' + $model.Replace('"','') + '"'
        $p=Start-Process -FilePath $server -ArgumentList @('-m',$quoted,'--host','127.0.0.1','--port',"$port",'-c','2048') -PassThru -WorkingDirectory ([IO.Path]::GetDirectoryName($server)) -RedirectStandardOutput $out -RedirectStandardError $err
        [IO.File]::WriteAllText((Join-Path $cfg 'ai-server-windows.pid'),[string]$p.Id,$utf8)
        for ($i=0; $i -lt 90; $i++) {
            if ($p.HasExited) { throw "llama-server skoncil. Log: $err" }
            try {
                $null=Invoke-RestMethod -Uri "$endpoint/health" -TimeoutSec 2
                break
            } catch { Start-Sleep -Seconds 1 }
        }
        if ($i -ge 90) { throw "AI sa nespustila do 90 sekund. Log: $err" }
    }

    $app=$null
    foreach ($candidate in @('apps\windows\START.exe','apps\windows\START.cmd','apps\windows\START.bat','START.exe')) {
        $path=Join-Path $root $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) { $app=$path; break }
    }
    if ($app) {
        if ($app -match '\.(cmd|bat)$') {
            Start-Process -FilePath $env:ComSpec -ArgumentList ('/c "'+$app+'"') -WorkingDirectory ([IO.Path]::GetDirectoryName($app)) | Out-Null
        } else {
            Start-Process -FilePath $app -WorkingDirectory ([IO.Path]::GetDirectoryName($app)) | Out-Null
        }
    } else {
        Start-Process $endpoint | Out-Null
    }
    exit 0
} catch {
    [Console]::Error.WriteLine('DOMACA_OFFLINE: ' + $_.Exception.Message)
    exit 1
}