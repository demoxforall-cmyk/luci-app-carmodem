# Сборка и установка / Build & Install

`luci-app-carmodem` для ImmortalWRT 25.12. Пакет архитектурно-независим
(`LUCI_PKGARCH:=all`) — собирается в SDK **любого** target 25.12.

---

## Русский

### Вариант A — в распакованном SDK
1. Скачайте ImmortalWRT **SDK 25.12.0** для любого target (например
   `mediatek/filogic` для Banana Pi R4) с downloads.immortalwrt.org и распакуйте.
2. Из корня этого репозитория:
   ```sh
   sh build/build-in-sdk.sh /путь/к/immortalwrt-sdk-25.12.0-...
   ```
   Скрипт скопирует пакет, выставит биты исполнения, обновит feeds и соберёт.
3. Готовый `luci-app-carmodem_*.apk` будет в `bin/packages/<arch>/luci/`.

### Вариант B — в контейнере (без локального тулчейна)
```sh
# узнать точный URL SDK (имя содержит версию gcc) и подставить:
docker build -f build/Dockerfile --build-arg SDK_URL="<URL_SDK>" -t carmodem-build .
docker create --name cm carmodem-build
docker cp cm:/out ./out
docker rm cm
# пакет -> ./out/luci-app-carmodem_*.apk
```

### Вариант C — WSL на Windows (проверено) ✅
Если хост — Windows: `wsl --install -d Ubuntu-24.04`, затем поставить деп-ы и
запустить `build/wsl-fix-build.sh` (скачивает SDK, ставит ТОЛЬКО нужные фиды,
собирает). Нюанс: при активном VPN включить mirrored-сеть WSL
(`%USERPROFILE%\.wslconfig` → `[wsl2]\nnetworkingMode=mirrored`, затем
`wsl --shutdown`). Готовый `.apk` (~20 КБ, `arch: noarch`) кладётся в `Downloads`.

### Установка на роутер
```sh
# скопировать пакет на устройство (dropbear: scp ОБЯЗАТЕЛЬНО с ключом -O)
scp -O luci-app-carmodem-*.apk root@192.168.1.1:/tmp/
ssh root@192.168.1.1
# ОНЛАЙН-установка (БЕЗ --no-network): apk сам докачает из репозитория ImmortalWRT
# ВСЕ зависимости, включая librespeed-cli (полный спидтест, FR-29)
apk add --allow-untrusted --force-overwrite /tmp/luci-app-carmodem-*.apk
/etc/init.d/rpcd restart    # перечитать ACL и ubus-объект
/etc/init.d/carmodem enable && /etc/init.d/carmodem start
```
**Зависимости** (`libc`, `luci-base`, `luci-proto-modemmanager`, `modemmanager`,
`librespeed-cli`) объявлены в метаданных пакета и ставятся автоматически из
репозитория ImmortalWRT при онлайн-установке. `librespeed-cli` объявлен через
`LUCI_EXTRA_DEPENDS` — в SDK он не собирается (Go-пакет берётся готовым из репо).
⚠️ С `--no-network` докачки НЕ будет: тогда зависимости должны быть установлены
заранее, иначе apk откажется ставить пакет.
Откройте LuCI → меню **Modem**. При первом применении настроек соединения
модуль делает резервную копию `/etc/config/network` (ТЗ AC-1).

### Удаление
```sh
apk del luci-app-carmodem   # или: opkg remove luci-app-carmodem
```

---

## English

### Option A — in an unpacked SDK
1. Download ImmortalWRT **SDK 25.12.0** for any target (e.g. `mediatek/filogic`)
   from downloads.immortalwrt.org and unpack it.
2. From this repo root:
   ```sh
   sh build/build-in-sdk.sh /path/to/immortalwrt-sdk-25.12.0-...
   ```
3. The resulting `luci-app-carmodem_*.apk` is in `bin/packages/<arch>/luci/`.

### Option B — containerized build
```sh
docker build -f build/Dockerfile --build-arg SDK_URL="<SDK_URL>" -t carmodem-build .
docker create --name cm carmodem-build && docker cp cm:/out ./out && docker rm cm
```

### Install on the router
```sh
scp -O out/luci-app-carmodem_*.apk root@192.168.1.1:/tmp/   # dropbear needs scp -O
ssh root@192.168.1.1
# online install (NOT --no-network) so apk pulls all deps incl. librespeed-cli
apk add --allow-untrusted --force-overwrite /tmp/luci-app-carmodem_*.apk
/etc/init.d/rpcd restart
/etc/init.d/carmodem enable && /etc/init.d/carmodem start
```
Open LuCI → **Modem** menu. On first connection-config apply the module backs up
`/etc/config/network`.

### Requirements
Runtime deps are pulled automatically: `luci-base`, `luci-proto-modemmanager`,
`modemmanager`, `librespeed-cli`. AT access is serialized via `flock` (busybox).
