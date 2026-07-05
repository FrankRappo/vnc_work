#!/bin/bash
# zdget.sh <remote> <local> — pull a file from the cash via the ksod clipboard daemon (base64, no typing).
set -u
REMOTE="$1"; LOCAL="$2"; WAIT="${WAIT:-45}"
R=$(WAIT="$WAIT" bash /work/vnc_work/zd.sh "try{[Convert]::ToBase64String([IO.File]::ReadAllBytes('$REMOTE'))}catch{'ERR '+\$_.Exception.Message}" 2>&1)
case "$R" in ERR*|*TIMEOUT*) echo "[zdget] FAIL: $R" >&2; exit 1;; esac
printf '%s' "$R" | tr -d ' \r\n\t' | base64 -d > "$LOCAL" 2>/dev/null
echo "[zdget] $REMOTE -> $LOCAL ($(stat -c%s "$LOCAL" 2>/dev/null) bytes)"
