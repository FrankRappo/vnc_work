# ssh_setup.ps1 - ONE-SHOT elevated installer for the KSO reverse-SSH channel.
# Run elevated (via UAC). Installs OpenSSH server, starts sshd, opens the firewall,
# installs /work's pubkey for admin login, hardens to key-only auth, locks the tunnel
# private key perms, and registers+starts the KSOTunnel autostart task (SYSTEM, at boot).
# All progress is appended to C:\kso\ssh_setup.log so /work can read it back via the daemon.
$ErrorActionPreference='Continue'
$log='C:\kso\ssh_setup.log'
function L($m){ Add-Content -Path $log -Value ((Get-Date -Format o)+' '+$m) -Encoding UTF8 }
Set-Content -Path $log -Value ('=== KSO ssh_setup begin '+(Get-Date -Format o)+' ===') -Encoding UTF8
$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$el=([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
L ('elevated='+$el+' user='+$env:USERNAME)
if(-not $el){ L 'NOT ELEVATED - abort'; exit 1 }

# 1. OpenSSH Server (+ Client, if missing) via Windows capability
try{
  $srv=Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
  L ('server cap: '+$srv.Name+' state='+$srv.State)
  if($srv.State -ne 'Installed'){ $r=Add-WindowsCapability -Online -Name $srv.Name; L ('  add server -> RestartNeeded='+$r.RestartNeeded) }
}catch{ L ('server cap ERR: '+$_.Exception.Message) }
try{
  $cli=Get-WindowsCapability -Online -Name 'OpenSSH.Client*'
  if($cli.State -ne 'Installed'){ $r=Add-WindowsCapability -Online -Name $cli.Name; L ('  add client -> RestartNeeded='+$r.RestartNeeded) } else { L 'client cap already Installed' }
}catch{ L ('client cap ERR: '+$_.Exception.Message) }

# fallback: GitHub release if sshd.exe still absent
if(-not (Test-Path 'C:\Windows\System32\OpenSSH\sshd.exe')){
  L 'sshd.exe missing after capability install -> GitHub fallback'
  try{
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $url='https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.8.1.0p1-Preview/OpenSSH-Win64.zip'
    $zip="$env:TEMP\OpenSSH-Win64.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath 'C:\Program Files\OpenSSH' -Force
    & 'C:\Program Files\OpenSSH\OpenSSH-Win64\install-sshd.ps1'
    L 'GitHub OpenSSH installed'
  }catch{ L ('github fallback ERR: '+$_.Exception.Message) }
}

# 2. services: sshd + ssh-agent -> Automatic + start
try{ Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service ssh-agent -ErrorAction SilentlyContinue }catch{}
try{
  Set-Service sshd -StartupType Automatic
  Start-Service sshd
  $s=Get-Service sshd; L ('sshd status='+$s.Status+' start='+$s.StartType)
}catch{ L ('sshd svc ERR: '+$_.Exception.Message) }

# 3. firewall: allow inbound TCP 22
try{
  if(-not (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue)){
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    L 'firewall rule created (22/tcp)'
  } else { Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue; L 'firewall rule already present' }
}catch{ L ('firewall ERR: '+$_.Exception.Message) }

# 4. administrators_authorized_keys  (sco_m210 is admin -> key MUST live here, not ~/.ssh)
try{
  $ak='C:\ProgramData\ssh\administrators_authorized_keys'
  $pub='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEz/32tAWzxJXVgkzWwhDobouwPbZ7O2TbIhoc0H2NKu work-to-cash'
  New-Item -ItemType Directory -Force -Path 'C:\ProgramData\ssh' | Out-Null
  Set-Content -Path $ak -Value $pub -Encoding ascii
  icacls $ak /inheritance:r | Out-Null
  icacls $ak /grant 'SYSTEM:F' | Out-Null
  icacls $ak /grant 'BUILTIN\Administrators:F' | Out-Null
  L ('authorized_keys written: '+((Get-Content $ak) -join ''))
}catch{ L ('authkeys ERR: '+$_.Exception.Message) }

# 5. lock the tunnel private key so ssh.exe (run as SYSTEM) will accept it.
#    ssh.exe requires: owner in {SYSTEM, Administrators, current-user} AND only SYSTEM+Admins+owner
#    have access. The KSOTunnel task runs as SYSTEM, so set owner=SYSTEM and DACL=SYSTEM:R+Admins:R.
#    Use .NET + well-known SIDs (locale-independent — 'NT AUTHORITY\SYSTEM' via icacls fails on RU Windows).
try{
  $key='C:\kso\ssh\kso_tunnel'
  if(Test-Path $key){
    $sys=New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
    $adm=New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl=Get-Acl -Path $key
    $acl.SetOwner($sys)
    $acl.SetAccessRuleProtection($true,$false)
    @($acl.Access) | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sys,'Read','Allow')))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adm,'Read','Allow')))
    Set-Acl -Path $key -AclObject $acl
    L ('tunnel key locked; '+((icacls $key 2>&1 | Out-String).Trim()))
  } else { L 'WARN tunnel key not found at C:\kso\ssh\kso_tunnel' }
}catch{ L ('key perms ERR: '+$_.Exception.Message) }

# 6. harden: key-only auth (2243 is internet-exposed on the VPS via GatewayPorts)
try{
  $cfg='C:\ProgramData\ssh\sshd_config'
  if(Test-Path $cfg){
    $c=Get-Content $cfg -Raw
    $c=$c -replace '(?m)^\s*#?\s*PasswordAuthentication\s+.*$',''
    $c=$c -replace '(?m)^\s*#?\s*PubkeyAuthentication\s+.*$',''
    $c=$c.TrimEnd()+"`r`nPubkeyAuthentication yes`r`nPasswordAuthentication no`r`n"
    Set-Content -Path $cfg -Value $c -Encoding ascii
    Restart-Service sshd
    L ('sshd_config hardened (key-only); sshd='+(Get-Service sshd).Status)
  } else { L 'WARN sshd_config not found (sshd not installed?)' }
}catch{ L ('hardening ERR: '+$_.Exception.Message) }

# 7. autostart: KSOTunnel scheduled task (SYSTEM, at startup + at logon, restart on fail)
try{
  $act=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\kso\ssh\kso_tunnel.ps1'
  $t1=New-ScheduledTaskTrigger -AtStartup
  $t2=New-ScheduledTaskTrigger -AtLogOn
  $pr=New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  $set=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName 'KSOTunnel' -Action $act -Trigger $t1,$t2 -Principal $pr -Settings $set -Force | Out-Null
  L 'KSOTunnel task registered (SYSTEM, AtStartup+AtLogon)'
  Start-ScheduledTask -TaskName 'KSOTunnel'
  L 'KSOTunnel task started'
}catch{ L ('task ERR: '+$_.Exception.Message) }

L '=== KSO ssh_setup end ==='
