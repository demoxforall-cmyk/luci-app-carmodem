#!/usr/bin/env bash
# CarModem — пересборка в УЖЕ распакованном SDK с ВЫБОРОЧНОЙ установкой фидов.
# Причина: `feeds install -a` тащит весь base/packages (uboot-mediatek prereq,
# рекурсивные зависимости nginx) и ломает make prereq. Ставим только наши деп-ы.
set -uo pipefail

WORK="$HOME/carmodem-build"
SDK="$WORK/sdk"
REPO_WIN="/mnt/c/Users/demox/Documents/Code/carmodem/carmodem-repo"
OUT_WIN="/mnt/c/Users/demox/Downloads"

[ -f "$SDK/scripts/feeds" ] || { echo "Нет SDK в $SDK — сначала прогон wsl-build.sh"; exit 1; }
cd "$SDK"

echo "[1/7] Обновляю пакет из репозитория + биты +x"
rm -rf "$SDK/package/luci-app-carmodem"
cp -r "$REPO_WIN/luci-app-carmodem" "$SDK/package/luci-app-carmodem"
chmod 0755 "$SDK/package/luci-app-carmodem/root/usr/libexec/rpcd/carmodem" \
           "$SDK/package/luci-app-carmodem/root/etc/init.d/carmodem"

echo "[2/7] Чищу прошлую установку фидов и конфиг"
./scripts/feeds clean >/dev/null 2>&1 || rm -rf package/feeds
rm -f .config .config.old
rm -rf tmp

echo "[3/7] feeds update (индексы; быстро, уже скачано)"
./scripts/feeds update -a >/dev/null 2>&1

echo "[4/7] Выборочная установка ТОЛЬКО зависимостей"
./scripts/feeds install luci-base luci-proto-modemmanager modemmanager

echo "[5/7] defconfig + включаю наш пакет"
make defconfig >/dev/null 2>&1
echo 'CONFIG_PACKAGE_luci-app-carmodem=m' >> .config
make defconfig >/dev/null 2>&1

if ! grep -q '^CONFIG_PACKAGE_luci-app-carmodem=m' .config; then
    echo "ОШИБКА: пакет не выбран в .config (не разрешилась зависимость). Диагностика:"
    grep -E 'luci-app-carmodem|luci-proto-modemmanager|librespeed-cli|^CONFIG_PACKAGE_modemmanager' .config | head
    exit 2
fi
echo "  пакет включён: $(grep '^CONFIG_PACKAGE_luci-app-carmodem' .config)"

echo "[6/7] Сборка пакета"
make package/luci-app-carmodem/compile V=s -j"$(nproc)"
rc=$?
if [ "$rc" -ne 0 ]; then echo "make завершился с кодом $rc"; exit "$rc"; fi

echo "[7/7] Готовый пакет -> $OUT_WIN"
mkdir -p "$OUT_WIN"
found=$(find "$SDK/bin" -name 'luci-app-carmodem*' \( -name '*.apk' -o -name '*.ipk' \) -print)
if [ -z "$found" ]; then echo "ВНИМАНИЕ: пакет не найден в bin/"; exit 3; fi
echo "$found"
echo "$found" | while read -r p; do [ -n "$p" ] && cp "$p" "$OUT_WIN/"; done
echo "=== СБОРКА УСПЕШНА ==="
ls -la "$OUT_WIN"/luci-app-carmodem* 2>/dev/null
