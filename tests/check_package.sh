#!/bin/sh
# CarModem — статический линтер целостности пакета (без сборки/SDK).
# Сверяет: валидность JSON, меню<->вьюхи, rpc<->acl<->бэкенд, права.
# Запуск: sh tests/check_package.sh
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
PKG="$ROOT/luci-app-carmodem"
ROOTFS="$PKG/root"
RES="$PKG/htdocs/luci-static/resources"
MENU="$ROOTFS/usr/share/luci/menu.d/luci-app-carmodem.json"
ACL="$ROOTFS/usr/share/rpcd/acl.d/luci-app-carmodem.json"
RPCD="$ROOTFS/usr/libexec/rpcd/carmodem"

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   $1"; }
bad()  { fail=$((fail+1)); echo "  FAIL $1"; }

echo "CarModem package integrity"
echo

echo "[JSON валиден]"
for j in "$MENU" "$ACL"; do
  # путь передаём аргументом (Deno.args[0]) — без интерполяции в JS-строку,
  # иначе обратные слеши Windows-пути ломают парсинг
  if deno eval "JSON.parse(Deno.readTextFileSync(Deno.args[0]))" "$j" >/dev/null 2>&1; then
    ok "json $(basename "$j")"
  else
    bad "json $(basename "$j") — невалиден"
  fi
done

echo
echo "[меню -> вьюхи: каждый view-path имеет JS-файл]"
# вытащить "path": "carmodem/<x>" из меню
for v in $(grep -oE '"path"[ ]*:[ ]*"carmodem/[a-z]+"' "$MENU" | grep -oE 'carmodem/[a-z]+'); do
  f="$RES/view/$v.js"
  [ -f "$f" ] && ok "view $v -> $(basename "$f")" || bad "view $v -> нет файла $f"
done

echo
echo "[rpc <-> бэкенд <-> acl]"
# методы, объявленные во фронтенде
METHODS=$(grep -oE "method: '[a-z_]+'" "$RES/carmodem.js" | grep -oE "'[a-z_]+'" | tr -d "'" | sort -u)
# методы в list-выводе rpcd (ключи объекта)
LIST=$(sed -n '/list)/,/;;/p' "$RPCD" | grep -oE '"[a-z_]+":' | tr -d '":' | sort -u)
# методы в acl (read+write)
ACLM=$(grep -oE '"[a-z_]+"' "$ACL" | tr -d '"' | sort -u)
for m in $METHODS; do
  echo "$LIST" | grep -qx "$m" && lst=ok || lst=MISS
  echo "$ACLM"  | grep -qx "$m" && acl=ok || acl=MISS
  if [ "$lst" = ok ] && [ "$acl" = ok ]; then ok "method $m (list+acl)"; else bad "method $m: list=$lst acl=$acl"; fi
done

echo
echo "[acl: read только для get_/scan_, write для действий]"
# read-секция
READM=$(awk '/"read"/{r=1} /"write"/{r=0} r' "$ACL" | grep -oE '"[a-z_]+"' | tr -d '"' | grep -E '^(get_|scan_)' )
WRITEM=$(awk '/"write"/{w=1} w' "$ACL" | grep -oE '"[a-z_]+"' | tr -d '"' | grep -E '^(set_|send_|dial|speedtest|reset_)')
[ -n "$READM" ]  && ok "read-методы присутствуют" || bad "read-секция пуста"
[ -n "$WRITEM" ] && ok "write-методы присутствуют" || bad "write-секция пуста"
# get_telemetry не должен быть в write
if awk '/"write"/{w=1} w' "$ACL" | grep -q '"get_telemetry"'; then bad "get_telemetry ошибочно в write"; else ok "get_* не в write"; fi

echo
echo "[shebang/исполняемость скриптов на устройстве]"
for s in "$RPCD" "$ROOTFS/etc/init.d/carmodem"; do
  head -1 "$s" | grep -q '^#!' && ok "shebang $(basename "$s")" || bad "нет shebang в $s"
done

echo
echo "итого: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
