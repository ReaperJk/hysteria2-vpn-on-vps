# Hysteria2 Auto-Install Script (v5)

Скрипт для автоматической установки [Hysteria2](https://hysteria.network/) на Ubuntu-сервер с маскировкой под обычный сайт-заглушку, автонастройкой swap и опциональными email-уведомлениями при падении службы.
Весь скрипт был написан ии(claude, sonnet 5), изначальные команды для установки впн брал с данного видео на ютубе(https://youtu.be/4zeqK0tLvw0?si=iEtj72aikxKANMaP).

## Что делает скрипт

- Устанавливает Hysteria2 и настраивает TLS-сертификат через Let's Encrypt (ACME) по вашему домену
- Создаёт сайт-заглушку для маскировки трафика под обычный HTTP(S)-сайт
- Настраивает одного или нескольких пользователей (логин/пароль) для подключения
- Автоматически создаёт swap-файл, если свободной RAM мало (или спрашивает, если RAM достаточно)
- Настраивает firewall (ufw): открывает SSH, 80 и 443 порты
- Опционально: настраивает отправку email-уведомлений через внешний SMTP (Gmail/Yandex/другой), если служба Hysteria2 упадёт

## Требования

- Чистый сервер на **Ubuntu 24.04** (не тестировалось на других версиях/дистрибутивах)
- Root-доступ
- Домен, у которого A-запись уже указывает на IP сервера
- Порты 80 и 443 свободны (не заняты nginx/apache и т.п.)

## Скачивание
[![Download](https://img.shields.io/badge/Download-install__hysteria2.sh-brightgreen?style=for-the-badge&logo=gnubash)](https://github.com/ReaperJk/hysteria2-vpn-on-vps/releases/download/v0.1/install_hysteria2.sh)

## Установка

<details>
<summary><b>Android</b> (нажми, чтобы развернуть инструкцию)</summary>
- весь гайд также есть в видео которое я указал в описании, но автор все делает вручную, я автоматизировал

- 1.Арендуйте vps(персональный виртуальный сервер) на одном из сайтов для аренды серверов(советую арендовывать с малоизвестных сайтов). Минимальные требования к серверу:
Процессор: Intel® Xeon™ 1 vCPU core
Оперативная память: 500 MB
Диск: 2-3 GB SSD
OS: Ubuntu 24.04(устанавливайте именно чистую OS, не OS+Control panel)

- 2.Подождите пока сервер развернется и будет активен, пока это происходит зарегестрируйте домен на сайте freedns(https://freedns.afraid.org/), советую сделать короткий домен
 
- 3.Установите Termux из google play(play market)
 
- 4.Скачайте скрипт с данной страницы(https://github.com/ReaperJk/hysteria2-vpn-on-vps/releases/tag/v0.1)
 
- 5.Откройте Termux и выполните команды(перед этим убедитесь что скачанный скрипт находится в папке "загрузки"):
 
```bash
pkg install openssh
termux-setup-storage
scp ~/storage/downloads/install_hysteria2.sh root@ip вашего сервера:~/
```
- вам потребуется ipv4 и пароль для доступа к серверу(когда вы вводите пароль в терминале он невидим), сервис/сайт для аренды серверов предоставит их вам на домашней странице с настройками сервера или в электронном письме, после выполнения команд выше, выполните следующие команды в терминале:
 
```bash
ssh root@ip вашего сервера
bash install_hysteria2_v5.sh
```
- когда вылезет меню выберите "keep the local version"(или что то типа того) и нажмите enter, если вылезет ошибка по типу "bash: scp: command not found", найдите в интернете что требуется установить, команда установки: "pkg install openssh"
 
- скрипт задаст вопросы: домен, email, логины/пароли пользователей(они нужны для создания конфигов, по которым вы будете подключаться через впн клиент, т.е через сами впн-приложения с кнопкой "подключиться"), порт SSH, и (опционально) настройки email-уведомлений.

- 6.Откройте сайт https://hysteriaconfig.xyz, укажите там имя и пароль пользователя, пример :"vpn:67e521c8dac3eac9b2f0fe409b33955b"
 
- 7.Скачайте впн клиент на ядре mihomo, вот список:
- FlClash—https://github.com/chen08209/FlClash
- ClashMi—https://github.com/KaringX/clashmi (сборка не воспроизводимая)
- FlyClash—https://github.com/GtxFury/FlyClash-Android (закрытый код)
- YumeBox—https://github.com/YumeLira/YumeBox
- Bettbox—https://github.com/appshubcc/Bettbox
- FlClashX—https://github.com/pluralplay/FlClashX
- clash-xiaoy—https://github.com/aimy1/clash-xiaoy
- MonadBox—https://github.com/MonadBoxLab/MonadBox
- ClashFest—https://github.com/Nemu-x/ClashFest
- AsteriskMETA—https://github.com/Asterisk4Magisk/AsteriskMETA
- SlClash—https://github.com/songzhengpei/Slclash
- MikuBox—https://github.com/HatsuneMikuUwU/MikuBoxForAndroid
- 8.Вставьте туда свой конфиг и переключите прокси на vpb ![Скриншот](./assets/screenshot.png)
</details>

## Дисклеймер

Этот скрипт разворачивает прокси/VPN-инструмент, который может использоваться для обхода сетевых ограничений. Использование подобных инструментов регулируется законодательством вашей страны — убедитесь, что вы соблюдаете применимые законы. Автор скрипта не несёт ответственности за то, как он используется.

## Актуальность

Скрипт тянет официальный установщик Hysteria2 напрямую с `get.hy2.sh`, поэтому версия самого Hysteria2 всегда актуальная. Формат `config.yaml` в редких случаях может меняться при крупных обновлениях Hysteria2 — если после обновления что-то не работает, сверьтесь с [официальной документацией](https://v2.hysteria.network/docs/getting-started/Server/).

## Лицензия

MIT — см. [LICENSE](./LICENSE).
