#!/bin/bash
# kiosk_reveal.sh — на КСО-кассе (RustDesk :99) Electron-киоск часто перекрывает cmd/1С-окна.
# Наблюдение 2026-07-02: киоск НЕ строго always-on-top — Win+D (Show Desktop) сворачивает ВСЁ,
# включая киоск, и открывает рабочий стол + таскбар. После этого окна поднимаются кликом по
# кнопке в таскбаре (если у приложения несколько окон — сначала показывается группа превью,
# нужен ВТОРОЙ клик по нужному превью).
#
# Использование:
#   kiosk_reveal.sh desktop        — Win+D (показать рабочий стол; повторный вызов вернёт окна)
#   kiosk_reveal.sh cmd            — Win+D, затем клик по иконке cmd в таскбаре (показывает превью-группу)
#   kiosk_reveal.sh restore-kiosk  — поднять свёрнутый киоск обратно на передний план (клик по его иконке)
#   kiosk_reveal.sh taskbar        — подсказка по X-координатам иконок таскбара (этот киоск)
#
# ГЕОМЕТРИЯ (портретная касса 1080x1920 в кадре :99 1920x1080):
#   удалённый экран отмасштабирован по высоте: scale = 1080/1920 = 0.5625 → ширина ≈ 607px,
#   центрирован → занимает X≈[656..1263], Y=[0..1067] кадра :99. Таскбар — снизу, Y≈1067.
#   Иконки таскбара этого киоска (Y=1067), слева направо (пины + запущенные):
#     Пуск=669 Поиск=700 Задачи=727 Edge=758 Проводник=784 cmd=813 PS=842
#     монитор=869 RustDesk=897 Electron/киоск=921 1С=944
#   (проверять скрином — при др. наборе запущенных приложений X сдвигается; см. TB_HINT ниже.)
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
Y_TB="${Y_TB:-1067}"
X_CMD="${X_CMD:-813}"
X_KIOSK="${X_KIOSK:-921}"
SCREENS="${AD_SCREENS:-/work/vnc_work/screens}"

shot(){ scrot -o "$SCREENS/${1:-kr}.png" 2>/dev/null && convert "$SCREENS/${1:-kr}.png" -quality 85 "$SCREENS/${1:-kr}.jpg" && echo "$SCREENS/${1:-kr}.jpg"; }

case "${1:-}" in
  desktop)      xdotool key --clearmodifiers super+d; sleep 1.2; shot kr_desktop ;;
  cmd)          xdotool key --clearmodifiers super+d; sleep 1.2
                xdotool mousemove "$X_CMD" "$Y_TB" click 1; sleep 1.2
                echo "[i] если открылась группа превью cmd — кликни нужное превью (обычно ~y=1025);"
                echo "    напр.: xdotool mousemove 697 1025 click 1"; shot kr_cmd ;;
  restore-kiosk) xdotool mousemove "$X_KIOSK" "$Y_TB" click 1; sleep 1.2; shot kr_kiosk ;;
  taskbar)      echo "Y_TB=$Y_TB  Пуск=669 Поиск=700 Задачи=727 Edge=758 Проводник=784 cmd=$X_CMD PS=842 монитор=869 RustDesk=897 Electron=$X_KIOSK 1С=944" ;;
  *) echo "usage: kiosk_reveal.sh desktop|cmd|restore-kiosk|taskbar" ;;
esac
