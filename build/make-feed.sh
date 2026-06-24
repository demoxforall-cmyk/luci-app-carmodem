#!/usr/bin/env bash
# CarModem — сборка подписанного apk-фида для установки через LuCI.
# Раскладка как у OpenWrt: <out>/<arch>/carmodem/{packages.adb, *.apk}.
# Запись репо на устройстве = ПОЛНЫЙ URL до packages.adb (см. feeds.mk).
set -uo pipefail
WORK="$HOME/carmodem-build"; SDK="$WORK/sdk"
APK="$SDK/staging_dir/host/bin/apk"
ARCH="aarch64_cortex-a53"
OUT="/mnt/c/Users/demox/Downloads/carmodem-feed"
KEYDIR="/mnt/c/Users/demox/Documents/Code/carmodem/carmodem-repo/build/feed-key"

# 1) Стабильный ключ подписи: при первом запуске сохраняем текущий ключ SDK в репо,
#    далее ВОЗВРАЩАЕМ его в SDK (чтобы подпись не менялась между пересборками SDK).
mkdir -p "$KEYDIR"
if [ ! -f "$KEYDIR/private-key.pem" ]; then
    cp "$SDK/private-key.pem" "$KEYDIR/private-key.pem"
    cp "$SDK/public-key.pem"  "$KEYDIR/public-key.pem"
    echo "[key] сохранил текущий ключ SDK в репо (build/feed-key/)"
else
    cp "$KEYDIR/private-key.pem" "$SDK/private-key.pem"
    cp "$KEYDIR/public-key.pem"  "$SDK/public-key.pem"
    echo "[key] восстановил стабильный ключ из репо в SDK"
fi

PKG=$(ls -t "$SDK"/bin/packages/$ARCH/base/luci-app-carmodem-*.apk 2>/dev/null | head -1)
[ -n "$PKG" ] || { echo "НЕТ собранного пакета — сначала build/wsl-quick.sh"; exit 1; }
echo "[pkg] $PKG"

# 2) Чистая раскладка фида
FD="$OUT/$ARCH/carmodem"
rm -rf "$OUT"; mkdir -p "$FD"
cp "$PKG" "$FD/"

# 3) Подписанный индекс. Важна подпись ИНДЕКСА (её устройство проверяет ключом
#    public-key.pem); --allow-untrusted нужен лишь чтобы mkndx проиндексировал
#    пакет, не упираясь в его собственную подпись на хосте.
( cd "$FD" && "$APK" mkndx --allow-untrusted --sign "$SDK/private-key.pem" -o packages.adb ./*.apk )
echo "[index] $FD/packages.adb"
# контроль: индекс должен верифицироваться публичным ключом
PUB=/tmp/cmpub; rm -rf "$PUB"; mkdir -p "$PUB"; cp "$SDK/public-key.pem" "$PUB/"
"$APK" verify --keys-dir "$PUB" "$FD/packages.adb" && echo "[index] подпись OK (public-key.pem)"

# 4) Публичный ключ для устройства
cp "$SDK/public-key.pem" "$OUT/carmodem-feed.pem"

# 5) Валидация: установка из фида с доверенным ключом (упасть должно ТОЛЬКО на
#    отсутствующих зависимостях — значит фид найден и подпись доверена)
echo "=== ВАЛИДАЦИЯ ==="
rm -rf /tmp/vroot; mkdir -p /tmp/vroot/etc/apk/keys; cp "$SDK/public-key.pem" /tmp/vroot/etc/apk/keys/carmodem-feed.pem
printf '%s\n' "$FD/packages.adb" > /tmp/vrepos
"$APK" add --root /tmp/vroot --initdb --usermode --arch "$ARCH" \
  --keys-dir /tmp/vroot/etc/apk/keys --repositories-file /tmp/vrepos luci-app-carmodem 2>&1 | head -12

echo "=== ГОТОВО ==="
echo "Фид: $OUT  (хостить целиком; URL репо = .../$ARCH/carmodem/packages.adb)"
ls -R "$OUT" 2>/dev/null
