#!/bin/bash
# shot1.sh <label> — capture the cash's real session-1 screen (native 1024x768) via a scheduled
# task, pull the PNG to /work/vnc_work/screens/<label>.png (+ .jpg), print the local jpg path.
# Reliable, pixel-accurate (unlike RustDesk's upscaled :99 frame). Run WITHOUT sandbox concerns
# for the ssh/scp parts (this script calls kso_ssh/kso_scp which need dangerouslyDisableSandbox
# when invoked by the agent — so call THIS script itself with dangerouslyDisableSandbox=true).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
L="${1:-shot1}"
OUT="$DIR/screens"
mkdir -p "$OUT"
# register + run the capture task in session 1
read -r -d '' PS <<'EOF'
$ErrorActionPreference="SilentlyContinue"
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File C:\kso\kso_capture_screen.ps1'
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)
$principal=New-ScheduledTaskPrincipal -UserId 'SCO_M210' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'KSOCapture' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'KSOCapture'
Start-Sleep -Seconds 2
(Get-Item C:\kso\screen_capture.png).LastWriteTime.ToString('HH:mm:ss')
EOF
B64=$(printf '%s' "$PS" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/kso_ssh.sh" "powershell -NoProfile -EncodedCommand $B64" 2>/dev/null | grep -avE '<Objs|CLIXML|_x000D_' >/dev/null
sleep 1
bash "$DIR/kso_scp.sh" kso:C:/kso/screen_capture.png "$OUT/$L.png" >/dev/null 2>&1
if [ -f "$OUT/$L.png" ]; then
  convert "$OUT/$L.png" -quality 90 "$OUT/$L.jpg" 2>/dev/null
  echo "$OUT/$L.jpg"
else
  echo "CAPTURE_FAILED"
fi
