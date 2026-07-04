# luci-app-carmodem

LuCI-модуль мониторинга и управления 5G-модемом **Quectel RM520N-GL** для **ImmortalWRT 25.12** (apk, BPI-R4 / `aarch64_cortex-a53`).

Один пакет, два языка (русский/английский — по системному языку LuCI). Бэкенд — ModemManager + AT через сериализованный демон.

## Возможности

Три раздела в меню **Modem**:

### Status (`admin/modem/info`)
Дашборд: оператор + живой бейдж соединения, трафик/сессия, сила сигнала с побарными метриками (RSRP/RSRQ/SINR/RSSI, цветовые пороги), параметры соты, информация об устройстве (модель/прошивка/IMEI/ICCID/телефон/температура), по-антенные Rx0–3, агрегация несущих (CA), соседние соты, ссылка на соту на карте. Опрос активного экрана ~3 c.

### Messages (`admin/modem/sms`)
SMS/USSD-мессенджер: контакты слева, переписка справа; **живое обновление входящих** (без перезагрузки страницы) с плашкой «новые ↓» и счётчиком непрочитанных; цветные аватары, разделители дат, время сообщений; три режима хранилища (SIM / Modem / Combined) с индикаторами заполнения; новое сообщение на новый номер; удаление с выделением; USSD внизу списка.

### Advanced (`admin/modem/control`)
Дизайн «Console RF» (приборная панель): RAT-режим (пилюли), SIM-слот/TTL, **band-lock** LTE/NR LED-чипами с живым счётчиком, Connection (статус опрашивается раз в секунду) + **живой журнал дозвона**, поиск операторов (асинхронный), **AT-консоль** (чёрный терминал + реестр частых команд RM520N, включая смену интерфейса USB/PCIe/QMI/MBIM).

Тёмная/светлая тема — один CSS (`currentColor`/`color-mix`, без `prefers-color-scheme`).

## Установка

Подробно — [`docs/BUILD_INSTALL.md`](docs/BUILD_INSTALL.md). Кратко (на устройстве, онлайн — зависимости подтянутся сами):

```sh
# 1) скопировать пакет на роутер (dropbear — обязателен флаг -O):
scp -O luci-app-carmodem-3.7-r1.apk root@192.168.1.1:/tmp/
# 2) поставить без сертификата (зависимости подтянутся сами; можно из веб-терминала LuCI):
apk add --allow-untrusted /tmp/luci-app-carmodem-3.7-r1.apk
/etc/init.d/rpcd restart
```
Готовый `.apk` и подписанный фид — в [`dist/`](dist/). Русский перевод **вшит** в пакет (отдельный `luci-i18n-*` не нужен); язык переключается в System → Language.

## Сборка

ImmortalWRT SDK в WSL. Скрипты в [`build/`](build/):
- `wsl-quick.sh` — быстрая пересборка пакета;
- `make-feed.sh` — сборка подписанного apk-фида;
- `i18n_gen.mjs` — генерация русского перевода (`deno run -A build/i18n_gen.mjs`).

`CONFIG_SIGNED_PACKAGES=y`; перевод — исходники EN + `luci-app-carmodem/translations/carmodem.ru.po` (компилится в `.lmo` в составе пакета).

## Структура
- `luci-app-carmodem/` — пакет: Makefile, rpcd-бэкенд `root/usr/libexec/rpcd/carmodem`, шелл-логика `root/usr/share/carmodem/`, фронтенд `htdocs/luci-static/resources/`, ACL, меню, перевод.
- `docs/` — ТЗ, статус, BUILD_INSTALL, карта MM↔AT, тест-кейсы, [CHANGELOG](docs/CHANGELOG.md).
- `tests/` — юнит-тесты на фикстурах реальных AT-ответов RM520N-GL.
- `build/` — сборочные/вспомогательные скрипты.
- `dist/` — собранный `.apk` и подписанный фид.

## Тесты
Без железа, на фикстурах:
```sh
sh tests/run_control.sh && sh tests/run_backend.sh && sh tests/check_package.sh
deno run --allow-read tests/check_js.mjs
```

## Лицензия
GPL-2.0
