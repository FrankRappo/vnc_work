#!/bin/bash
# Примитивы управления дисплеем :99 (RustDesk-сессия). Скрины полноразмерные (реальные коорд 1920x1080).
DISP=:99
U(){ runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY=$DISP "$@"; }
case "${1:-}" in
  click) U xdotool mousemove "$2" "$3" click 1; echo "click $2 $3";;
  dbl)   U xdotool mousemove "$2" "$3" click --repeat 2 --delay 90 1; echo "dbl $2 $3";;
  type)  U xdotool type --delay 60 -- "$2"; echo "typed";;
  key)   shift; U xdotool key "$@"; echo "key $*";;
  shot)  U scrot -o /tmp/x99.png 2>/dev/null && convert /tmp/x99.png -quality 88 /tmp/x99.jpg && echo "/tmp/x99.jpg";;
  zoom)  U scrot -o /tmp/x99.png 2>/dev/null; convert /tmp/x99.png -crop "$2" -resize "${3:-250%}" -quality 88 /tmp/x99z.jpg && echo "/tmp/x99z.jpg";;
  wins)  for w in $(U xdotool search --name . 2>/dev/null); do echo "$w: $(U xdotool getwindowname $w 2>/dev/null)"; done;;
esac
