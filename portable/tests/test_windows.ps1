$ErrorActionPreference='Stop'
$origin = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path ([IO.Path]::GetTempPath()) ('domaca-offline-test-'+[Guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path (Join-Path $root 'scripts'),(Join-Path $root 'data\ai'),(Join-Path $root 'config') | Out-Null
  Copy-Item (Join-Path $origin 'scripts\start-offline.ps1') (Join-Path $root 'scripts\start-offline.ps1')
  [IO.File]::WriteAllText((Join-Path $root 'data\ai\qwen-small.gguf'),'tiny')
  [IO.File]::WriteAllText((Join-Path $root 'data\ai\qwen-large.gguf'),'larger model bytes')
  foreach($ram in @(8,16,32)) {
    $env:DP_TEST_RAM_GIB=[string]$ram
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\start-offline.ps1') -SelectOnly
    if ($LASTEXITCODE -ne 0) { throw "Windows script failed for RAM=$ram" }
    $profile=(Get-Content (Join-Path $root 'config\ai-active-profile.txt') -TotalCount 1).Trim()
    $want=if($ram -le 16){'small'}else{'large'}
    if($profile -ne $want){throw "RAM=$ram actual=$profile expected=$want"}
    $model=(Get-Content (Join-Path $root 'config\ai-active-model.txt') -TotalCount 1).Trim()
    if(-not $model.EndsWith("qwen-$want.gguf")){throw "Wrong model: $model"}
    Write-Host "PASS $ram GiB => $want"
  }
  [IO.File]::WriteAllText((Join-Path $root 'data\ai\qwen-third.gguf'),'medium')
  $env:DP_TEST_RAM_GIB='32'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'scripts\start-offline.ps1') -SelectOnly
  if($LASTEXITCODE -ne 0){throw 'More than two GGUF files should work.'}
  $model=(Get-Content (Join-Path $root 'config\ai-active-model.txt') -TotalCount 1).Trim()
  if(-not $model.EndsWith('qwen-large.gguf')){throw 'Largest GGUF not selected.'}
  Write-Host 'PASS multiple GGUF files'
} finally {
  Remove-Item Env:DP_TEST_RAM_GIB -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
