# CarModem — сборка .apk «одной командой» в контейнере (без локального тулчейна).
# Пакет архитектурно-независим, поэтому годится SDK любого target 25.12.
#
# 1) Узнайте точный URL SDK на downloads.immortalwrt.org для 25.12.0
#    (targets/<target>/<subtarget>/immortalwrt-sdk-25.12.0-*.tar.zst|.tar.xz).
#    Пример для Banana Pi R4 (mediatek/filogic) подставлен по умолчанию —
#    при необходимости поправьте версию gcc в имени файла.
# 2) Сборка:
#    docker build -f build/Dockerfile --build-arg SDK_URL="<URL>" -t carmodem-build .
# 3) Достать пакет из образа:
#    docker create --name cm carmodem-build && \
#    docker cp cm:/out ./out && docker rm cm
#
# Готовый luci-app-carmodem_*.apk окажется в ./out.

FROM debian:12-slim

# Подтверждённый URL SDK 25.12.0 (mediatek/filogic) на 2026-06; при смене
# версии gcc в релизе — поправьте имя файла.
ARG SDK_URL=https://downloads.immortalwrt.org/releases/25.12.0/targets/mediatek/filogic/immortalwrt-sdk-25.12.0-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64.tar.zst

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential libncurses-dev zlib1g-dev gawk git gettext \
        libssl-dev xsltproc rsync wget unzip python3 file ca-certificates \
        zstd xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Сборка под непривилегированным пользователем (требование OpenWrt buildroot)
RUN useradd -m build
USER build
WORKDIR /home/build

RUN wget -q "$SDK_URL" -O sdk.tar \
    && mkdir sdk \
    && (tar --use-compress-program=unzstd -xf sdk.tar -C sdk --strip-components=1 \
        || tar -xf sdk.tar -C sdk --strip-components=1) \
    && rm sdk.tar

COPY --chown=build:build luci-app-carmodem /home/build/sdk/package/luci-app-carmodem
COPY --chown=build:build build/build-in-sdk.sh /home/build/build-in-sdk.sh

RUN chmod 0755 sdk/package/luci-app-carmodem/root/usr/libexec/rpcd/carmodem \
               sdk/package/luci-app-carmodem/root/etc/init.d/carmodem \
    && cd sdk \
    && ./scripts/feeds update -a >/dev/null \
    && ./scripts/feeds install -a >/dev/null \
    && make defconfig >/dev/null \
    && make package/luci-app-carmodem/compile V=s \
    && mkdir -p /home/build/out \
    && find bin -name 'luci-app-carmodem*' \( -name '*.apk' -o -name '*.ipk' \) -exec cp {} /home/build/out/ \;

# /out содержит готовый пакет
