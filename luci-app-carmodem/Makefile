# luci-app-carmodem — управление и мониторинг RM520N для ImmortalWRT
# SPDX-License-Identifier: GPL-2.0
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI app for RM520N modem (CarModem)
# Зависимости рантайма (попадают в поле depends: метаданных .apk -> при ОНЛАЙН-
# установке `apk add` apk сам докачивает их из репозитория ImmortalWRT):
#  luci-proto-modemmanager + modemmanager — бэкенд соединения (ТЗ 3.1).
LUCI_DEPENDS:=+luci-base +luci-proto-modemmanager +modemmanager
LUCI_PKGARCH:=all
PKG_VERSION:=3.4
PKG_LICENSE:=GPL-2.0
PKG_MAINTAINER:=CarModem project

include $(TOPDIR)/feeds/luci/luci.mk

# ВАЖНО: бит исполнения на root/usr/libexec/rpcd/carmodem и root/etc/init.d/carmodem
# должен быть выставлен ДО сборки (в репозитории на Windows бит x теряется).
# Сборочная обёртка build/build-in-sdk.sh делает это автоматически.

# call BuildPackage - OpenWrt buildroot signature
