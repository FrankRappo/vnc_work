#!/bin/bash
# kso_ps.sh <local.ps1>   OR   kso_ps.sh -c '<powershell code>'
# Run a PowerShell script on the KSO cash via -EncodedCommand — bypasses all bash/ssh/cmd/powershell
# quoting AND is Cyrillic-safe (script is carried as UTF-16LE base64; no console codepage in the path).
# The script's stdout returns over ssh; prepend [Console]::OutputEncoding=[Text.Encoding]::UTF8 in your
# script (or rely on this wrapper doing it) so Cyrillic comes back as UTF-8, not cp866.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "-c" ]; then
  BODY="$2"
else
  BODY="$(cat "$1")"
fi
# Force UTF-8 stdout so Cyrillic returns intact, silence progress CLIXML noise, then run the body.
FULL="\$OutputEncoding=[Console]::OutputEncoding=[Text.Encoding]::UTF8
\$ProgressPreference='SilentlyContinue'
${BODY}"
B64=$(printf '%s' "$FULL" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
exec bash "$DIR/kso_ssh.sh" "powershell -NoProfile -EncodedCommand $B64"
