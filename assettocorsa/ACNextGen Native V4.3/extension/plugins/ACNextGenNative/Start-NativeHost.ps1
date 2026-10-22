param([double]$Seconds=0)
$ErrorActionPreference='Stop'
$pluginRoot=$PSScriptRoot
$argsForHost=@('--ac-root','D:\steam\steamapps\common\assettocorsa','--runtime',(Join-Path $pluginRoot 'runtime'))
if($Seconds -gt 0){$argsForHost+=@('--seconds',([string]$Seconds))}
& (Join-Path $pluginRoot 'bin\ACNextGenHost.exe') @argsForHost
if($LASTEXITCODE -ne 0){throw "Native host exit $LASTEXITCODE"}
