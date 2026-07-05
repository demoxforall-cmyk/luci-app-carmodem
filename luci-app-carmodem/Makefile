# luci-app-carmodem — управление и мониторинг RM520N для ImmortalWRT
# SPDX-License-Identifier: GPL-2.0
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI app for RM520N modem (CarModem)
# Зависимости РАНТАЙМА. ВАЖНО: `+pkg` в LUCI_DEPENDS — это Kconfig select +
# build-prerequisite, т.е. SDK пытается СОБРАТЬ зависимость. У modemmanager это
# тянет за собой linux-firmware (сотни МБ) и делает сборку очень долгой.
# Поэтому модемные пакеты держим в LUCI_EXTRA_DEPENDS (объявлены в depends:
# метаданных .apk, но НЕ собираются) — `apk add` сам докачает их из репозитория
# ImmortalWRT. apk-путь требует version-constraint строго в формате "pkg (>=0)".
LUCI_DEPENDS:=+luci-base
LUCI_EXTRA_DEPENDS:=luci-proto-modemmanager (>=0), modemmanager (>=0)
LUCI_PKGARCH:=all
PKG_VERSION:=4.0
PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=CarModem project

include $(TOPDIR)/feeds/luci/luci.mk

# ВАЖНО: бит исполнения на root/usr/libexec/rpcd/carmodem и root/etc/init.d/carmodem
# должен быть выставлен ДО сборки (в репозитории на Windows бит x теряется).
# Сборочная обёртка build/build-in-sdk.sh делает это автоматически.

# call BuildPackage - OpenWrt buildroot signature
