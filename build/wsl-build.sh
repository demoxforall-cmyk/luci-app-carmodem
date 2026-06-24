#!/usr/bin/env bash
# CarModem — полная сборка .apk внутри WSL Ubuntu (без sudo; деп-ы ставятся отдельно).
# Запускается мной через wsl.exe. Копирует репозиторий с /mnt/c в ext4 (на 9p
# сборка медленная и ломает права), качает SDK, собирает, кладёт .apk в Downloads.
set -euo pipefail

REPO_WIN="/mnt/c/Users/demox/Documents/Code/carmodem/carmodem-repo"
OUT_WIN="/mnt/c/Users/demox/Downloads"
WORK="$HOME/carmodem-build"
SDK_URL="https://downloads.immortalwrt.org/releases/25.12.0/targets/mediatek/filogic/immortalwrt-sdk-25.12.0-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64.tar.zst"
SDK_DIR="$WORK/sdk"

echo "[1/6] Готовлю рабочий каталог в ext4: $WORK"
mkdir -p "$WORK"
rsync -a --delete "$REPO_WIN/luci-app-carmodem" "$WORK/"
rsync -a "$REPO_WIN/build/build-in-sdk.sh" "$WORK/"

echo "[2/6] Скачиваю SDK (если ещё нет)"
cd "$WORK"
if [ ! -f sdk.tar.zst ]; then wget -q --show-progress "$SDK_URL" -O sdk.tar.zst; fi

echo "[3/6] Распаковываю SDK -> $SDK_DIR"
if [ ! -f "$SDK_DIR/scripts/feeds" ]; then
	rm -rf "$SDK_DIR"; mkdir -p "$SDK_DIR"
	tar --use-compress-program=unzstd -xf sdk.tar.zst -C "$SDK_DIR" --strip-components=1
fi

echo "[4/6] Копирую пакет в SDK + биты исполнения"
rm -rf "$SDK_DIR/package/luci-app-carmodem"
cp -r "$WORK/luci-app-carmodem" "$SDK_DIR/package/luci-app-carmodem"
chmod 0755 "$SDK_DIR/package/luci-app-carmodem/root/usr/libexec/rpcd/carmodem" \
           "$SDK_DIR/package/luci-app-carmodem/root/etc/init.d/carmodem"

echo "[5/6] feeds + сборка"
cd "$SDK_DIR"
./scripts/feeds update -a >/dev/null
./scripts/feeds install -a >/dev/null
make defconfig >/dev/null
make package/luci-app-carmodem/compile V=s

echo "[6/6] Готовый пакет -> $OUT_WIN"
mkdir -p "$OUT_WIN"
found=$(find "$SDK_DIR/bin" -name 'luci-app-carmodem*' \( -name '*.apk' -o -name '*.ipk' \) -print)
echo "$found"
echo "$found" | while read -r p; do [ -n "$p" ] && cp "$p" "$OUT_WIN/"; done
echo "ГОТОВО. Пакет в $OUT_WIN"
