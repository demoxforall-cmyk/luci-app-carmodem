#!/usr/bin/env bash
# CarModem — БЫСТРАЯ пересборка только пакета в уже подготовленном SDK.
# Требует, чтобы wsl-fix-build.sh уже отработал минимум один раз (.config, tmp,
# собранные зависимости на месте). Не сбрасывает конфиг и не трогает фиды —
# поэтому пакет `all` (только файлы) пересобирается за секунды.
set -uo pipefail

WORK="$HOME/carmodem-build"
SDK="$WORK/sdk"
REPO_WIN="/mnt/c/Users/demox/Documents/Code/carmodem/carmodem-repo"
OUT_WIN="/mnt/c/Users/demox/Downloads"

[ -f "$SDK/.config" ] || { echo "SDK не подготовлен — сначала прогон wsl-fix-build.sh"; exit 1; }
cd "$SDK"

echo "[1/3] Обновляю пакет из репозитория + биты +x"
rm -rf "$SDK/package/luci-app-carmodem"
cp -r "$REPO_WIN/luci-app-carmodem" "$SDK/package/luci-app-carmodem"
chmod 0755 "$SDK/package/luci-app-carmodem/root/usr/libexec/rpcd/carmodem" \
           "$SDK/package/luci-app-carmodem/root/etc/init.d/carmodem" \
           "$SDK/package/luci-app-carmodem/root/etc/init.d/carmodem-watchdog"
# Вшиваем русский перевод ПРЯМО в основной пакет (один apk): компилим .po -> .lmo
# в root/ (luci.mk копирует root/* в пакет). po/ намеренно НЕТ -> отдельный
# luci-i18n-carmodem-ru не создаётся.
PO_RU="$SDK/package/luci-app-carmodem/translations/carmodem.ru.po"
if [ -f "$PO_RU" ]; then
    mkdir -p "$SDK/package/luci-app-carmodem/root/usr/lib/lua/luci/i18n"
    "$SDK/staging_dir/hostpkg/bin/po2lmo" "$PO_RU" \
        "$SDK/package/luci-app-carmodem/root/usr/lib/lua/luci/i18n/carmodem.ru.lmo" \
        && echo "    перевод RU вшит: carmodem.ru.lmo"
fi
grep -q '^CONFIG_PACKAGE_luci-app-carmodem=m' .config || echo 'CONFIG_PACKAGE_luci-app-carmodem=m' >> .config
sed -i '/^CONFIG_PACKAGE_luci-i18n-carmodem/d' .config   # отдельный i18n-пакет больше не нужен
# Снять возможный stale-select librespeed-cli (остался от эксперимента с +dep).
# ВАЖНО: убираем строкой sed, БЕЗ `make defconfig` — defconfig раскатывает весь
# дефолтный набор пакетов (kmod'ы и пр.), и quick-сборка перестаёт быть быстрой
# (перемалывает сотни пакетов, не доходя до нашего). librespeed-cli теперь
# LUCI_EXTRA_DEPENDS (НЕ build-dep) -> compile его всё равно не трогает.
sed -i '/^CONFIG_PACKAGE_librespeed-cli=/d' .config

echo "[2/3] Пересборка ТОЛЬКО пакета (clean+compile)"
make package/luci-app-carmodem/clean >/dev/null 2>&1
make package/luci-app-carmodem/compile V=s
rc=$?
[ "$rc" -eq 0 ] || { echo "make завершился с кодом $rc"; exit "$rc"; }

echo "[3/3] Готовый пакет -> $OUT_WIN"
found=$(find "$SDK/bin" -name 'luci-app-carmodem*' \( -name '*.apk' -o -name '*.ipk' \) -print)
[ -n "$found" ] || { echo "ВНИМАНИЕ: пакет не найден в bin/"; exit 3; }
echo "$found"
echo "$found" | while read -r p; do [ -n "$p" ] && cp "$p" "$OUT_WIN/"; done
echo "=== СБОРКА УСПЕШНА ==="
ls -la "$OUT_WIN"/luci-app-carmodem* 2>/dev/null
