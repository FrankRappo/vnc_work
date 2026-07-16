# kso_app_backup.ps1 — архивирует ПРИЛОЖЕНИЕ КСО (наш код), НЕ весь C:\kso.
# Whitelist: ksoapp (dist + electron/*.cjs + config, без node_modules) + скрипты кассы (*.ps1) +
# агент 1С (*.epf) + конфиги (exchange_share.json, *.json) + ярлыки. НЕ включает: дамп 1С-конфигурации
# (cfgfull ~1ГБ), рантайм electron (~268МБ, качается заново), debug/deploy-папки, node_modules, логи, 1С-базу.
$ErrorActionPreference = "Stop"
$ts = (Get-Date).ToString("yyyyMMdd_HHmm")
$out = "C:\kso\_full_app_$ts.zip"
$stg = "C:\kso\_bkstage_$ts"
if (Test-Path $out) { Remove-Item $out -Force }
if (Test-Path $stg) { Remove-Item $stg -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stg | Out-Null
# наш фронт/electron-код (без node_modules)
robocopy C:\kso\ksoapp "$stg\ksoapp" /E /XD node_modules /NFL /NDL /NJH /NJS /NP | Out-Null
# скрипты кассы, агент .epf, конфиги, ярлыки из корня C:\kso
Copy-Item C:\kso\*.ps1  $stg -Force -ErrorAction SilentlyContinue
Copy-Item C:\kso\*.epf  $stg -Force -ErrorAction SilentlyContinue
Copy-Item C:\kso\*.json $stg -Force -ErrorAction SilentlyContinue
Copy-Item C:\kso\*.cmd  $stg -Force -ErrorAction SilentlyContinue
Copy-Item C:\kso\*.bat  $stg -Force -ErrorAction SilentlyContinue
Copy-Item C:\kso\*.lnk  $stg -Force -ErrorAction SilentlyContinue
# упаковка
Push-Location $stg
tar -a -c -f $out *
Pop-Location
Remove-Item $stg -Recurse -Force
$sz = [math]::Round((Get-Item $out).Length/1MB,1)
Write-Output ("BACKUP_ZIP=$out")
Write-Output ("SIZE_MB=$sz")
$list = (tar -tf $out) 2>$null
$hasDist = [bool]($list | Select-String -Quiet "ksoapp/dist/index")
$hasEpf  = [bool]($list | Select-String -Quiet "\.epf")
$hasCS   = [bool]($list | Select-String -Quiet "close_shift_kso.ps1")
$hasNm   = [bool]($list | Select-String -Quiet "node_modules")
Write-Output ("CHECK dist=$hasDist epf=$hasEpf close_shift=$hasCS node_modules=$hasNm files=" + ($list | Measure-Object).Count)
