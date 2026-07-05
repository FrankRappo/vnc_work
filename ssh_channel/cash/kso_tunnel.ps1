# kso_tunnel.ps1 - KSO reverse-SSH tunnel watchdog (autossh replacement).
# Keeps  ssh -R 0.0.0.0:2243:127.0.0.1:22  alive from the cash to the jump VPS so that
# /work can reach the cash's sshd as  ssh -p 2243 sco_m210@178.253.55.128 .
# Runs forever; reconnects 10s after any drop. Registered as Scheduled Task 'KSOTunnel'.
$ErrorActionPreference='Continue'
$key='C:\kso\ssh\kso_tunnel'
$kh ='C:\kso\ssh\known_hosts'
$log='C:\kso\ssh\tunnel.log'
function L($m){ try{ Add-Content -Path $log -Value ((Get-Date -Format o)+' '+$m) -Encoding UTF8 }catch{} }
# keep the log from growing without bound across reconnects
try{ if((Test-Path $log) -and ((Get-Item $log).Length -gt 1MB)){ Clear-Content $log } }catch{}
L ('watchdog start pid='+$PID+' user='+$env:USERNAME)
while($true){
  L 'connecting to 178.253.55.128'
  & ssh -i $key -o "UserKnownHostsFile=$kh" -o StrictHostKeyChecking=accept-new `
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes `
        -o BatchMode=yes -o ConnectTimeout=20 -N `
        -R 0.0.0.0:2243:127.0.0.1:22 root@178.253.55.128 2>&1 | ForEach-Object { L ("ssh: $_") }
  L 'ssh exited; sleep 10 then reconnect'
  Start-Sleep -Seconds 10
}
