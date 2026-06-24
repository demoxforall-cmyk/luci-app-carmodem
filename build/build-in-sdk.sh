#!/bin/sh
# CarModem — сборка пакета в распакованном ImmortalWRT SDK 25.12.
# Пакет архитектурно-независим (LUCI_PKGARCH:=all) -> подходит SDK ЛЮБОГО target
# для 25.12 (например, mediatek/filogic для Banana Pi R4).
#
# Использование:
#   ./build-in-sdk.sh /путь/к/распакованному/immortalwrt-sdk-25.12.0-...
# Результат: готовый .apk печатается в конце (bin/packages/<arch>/luci/).

set -eu
SDK="${1:?укажите путь к распакованному SDK: ./build-in-sdk.sh <SDK_DIR>}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_SRC="$HERE/../luci-app-carmodem"

[ -f "$SDK/scripts/feeds" ] || { echo "Не похоже на SDK: нет $SDK/scripts/feeds"; exit 1; }

echo "[1/5] Копирую пакет в $SDK/package/luci-app-carmodem"
rm -rf "$SDK/package/luci-app-carmodem"
cp -r "$PKG_SRC" "$SDK/package/luci-app-carmodem"

echo "[2/5] Выставляю бит исполнения на скриптах (теряется на Windows)"
chmod 0755 "$SDK/package/luci-app-carmodem/root/usr/libexec/rpcd/carmodem" \
           "$SDK/package/luci-app-carmodem/root/etc/init.d/carmodem"

echo "[3/5] feeds update/install (luci)"
cd "$SDK"
./scripts/feeds update -a >/dev/null
./scripts/feeds install -a >/dev/null

echo "[4/5] Конфигурирую и собираю пакет"
make defconfig >/dev/null
make package/luci-app-carmodem/compile V=s

echo "[5/5] Готовый пакет:"
find "$SDK/bin" -name 'luci-app-carmodem*' \( -name '*.apk' -o -name '*.ipk' \) -print
