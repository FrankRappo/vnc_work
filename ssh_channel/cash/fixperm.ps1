# fixperm.ps1 (elevated) - make the tunnel private key acceptable to ssh.exe when run as SYSTEM.
# ssh.exe requires the key be owned by SYSTEM/Administrators/current-user and readable only by
# SYSTEM+Administrators+owner. The KSOTunnel task runs as SYSTEM, so set owner=SYSTEM and lock the DACL.
$ErrorActionPreference='Continue'
$log='C:\kso\ssh\fixperm.log'
function L($m){ Add-Content -Path $log -Value ((Get-Date -Format o)+' '+$m) -Encoding UTF8 }
Set-Content -Path $log -Value '=== fixperm begin ===' -Encoding UTF8
$key='C:\kso\ssh\kso_tunnel'
$sys=New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')          # NT AUTHORITY\SYSTEM
$adm=New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')      # BUILTIN\Administrators
try{
  $acl=Get-Acl -Path $key
  $acl.SetOwner($sys)
  $acl.SetAccessRuleProtection($true,$false)                                       # disable inheritance, drop inherited
  @($acl.Access) | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sys,'Read','Allow')))
  $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($adm,'Read','Allow')))
  Set-Acl -Path $key -AclObject $acl
  L 'owner=SYSTEM, DACL=SYSTEM:R+Admins:R applied'
}catch{ L ('ERR: '+$_.Exception.Message) }
$out=(icacls $key 2>&1 | Out-String)
L $out
# kick the running watchdog so it retries immediately with the corrected key
try{ Stop-ScheduledTask -TaskName 'KSOTunnel' -ErrorAction SilentlyContinue; Start-ScheduledTask -TaskName 'KSOTunnel'; L 'KSOTunnel restarted' }catch{ L ('task ERR: '+$_.Exception.Message) }
L '=== fixperm end ==='
