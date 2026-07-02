#!/bin/bash
# push_clip.sh <local_file> <remote_path_win>  — ONE-SHOT file transfer to the cash register via the
# RustDesk clipboard SYNC (local->remote), not via cmd-paste chunking. Much faster/robust than push_raw
# for medium files: the whole base64 rides the local->remote clipboard sync in one go; we TYPE (not paste)
# a short reader invocation so the clipboard is never clobbered, then C:\kso\c2f.ps1 reads the clipboard
# and WriteAllBytes()s the exact bytes. Verifies sha256+length. Falls back message on mismatch.
#
# Prereq: C:\kso\c2f.ps1 present on the kiosk (bootstrap once). Elevated cmd FOCUSED at TB_X,TB_Y (export).
set -u
LOCAL="$1"; REMOTE="$2"
export DISPLAY="${AD_DISPLAY:-:99}"
TBX="${TB_X:-760}"; TBY="${TB_Y:-76}"
SYNC="${SYNC:-3}"        # seconds to let RustDesk sync local->remote clipboard
RUN="${RUN:-5}"          # seconds to let the remote reader run
RC=/work/kso/chat/remote_cmd.sh
LEN=$(stat -c%s "$LOCAL"); SHA=$(sha256sum "$LOCAL" | cut -d' ' -f1 | tr 'a-f' 'A-F')
B64=$(base64 -w0 "$LOCAL"); NB=${#B64}
echo "[push_clip] $LOCAL -> $REMOTE bytes=$LEN b64=$NB sha=${SHA:0:16}"

# 1) load the whole base64 onto the local :99 clipboard (RustDesk mirrors it to the remote)
printf '%s' "$B64" | xclip -selection clipboard 2>/dev/null
sleep "$SYNC"

# 2) focus cmd, clear the input line, then TYPE (never paste) the reader invocation
xdotool mousemove "$TBX" "$TBY" click 1; sleep 0.35
xdotool key Escape; sleep 0.2
xdotool type --delay 22 "powershell -nop -ep bypass -f C:\\kso\\c2f.ps1 $REMOTE"
sleep 0.3
xdotool key Return
sleep "$RUN"

# 3) read back the reader's verdict (sha+len) via remote_cmd (paste is fine now; b64 no longer needed)
OUT=$(WAIT=8 "$RC" "powershell -nop -c \"Get-Content 'C:\\kso\\c2f.out'\"" 2>/dev/null | sed -n '/remote output/,/end -----/p' | grep -viE '^-----' | tr -d '\r')
echo "[push_clip] remote verdict: $OUT"
echo "[push_clip] local  sha=$SHA len=$LEN"
if printf '%s' "$OUT" | grep -q "$SHA" && printf '%s' "$OUT" | grep -q " $LEN"; then
  echo "[push_clip] OK (sha+len match)"
else
  echo "[push_clip] MISMATCH — clipboard sync may have truncated; retry or use push_raw.sh"
fi
