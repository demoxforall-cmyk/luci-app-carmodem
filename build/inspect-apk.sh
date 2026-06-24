#!/usr/bin/env bash
APK=/mnt/c/Users/demox/Downloads/luci-app-carmodem-0.1-r1.apk
APKTOOL="$HOME/carmodem-build/sdk/staging_dir/host/bin/apk"
echo "=== depends (полный список) ==="
"$APKTOOL" adbdump "$APK" 2>/dev/null | awk '/depends:/{f=1;next} /provides:|scripts:|triggers:/{f=0} f && /name:/{print "  "$2}'
echo "=== биты исполнения на ключевых скриптах ==="
"$APKTOOL" adbdump "$APK" 2>/dev/null | grep -B1 -iE 'mode: 0?755' | grep -iE 'name:|mode:' | grep -iE 'carmodem|mode' | head
echo "=== режимы для rpcd/init.d (ищем по контексту) ==="
"$APKTOOL" adbdump "$APK" 2>/dev/null | grep -A3 -E '- name: carmodem$' | grep -iE 'name:|mode:'
