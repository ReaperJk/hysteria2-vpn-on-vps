#!/usr/bin/env bash
#
# Автоматическая установка Hysteria2 с маскировкой под сайт-заглушку. (v5)
# Добавлено (v3): автоматическая настройка swap-файла по объёму RAM.
# Добавлено (v4):
#   - Swap теперь спрашивается (y/n), с кратким пояснением что это такое.
#     Если свободной RAM при обычной нагрузке < 1 ГБ — swap обязателен.
#   - Мониторинг обрыва службы hysteria-server: если сервис падает,
#     на указанную почту через SMTP-реле (msmtp) автоматически
#     отправляются последние строки логов.
# Добавлено (v5):
#   - Ограничены права доступа (chmod) на все файлы с паролями/секретами:
#     config.yaml, msmtprc, hysteria-alert.sh, msmtp.log — теперь читать
#     их может только root.
# Запускать от root: bash install_hysteria2_v5.sh
#
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[*]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   error "Запустите скрипт от root (sudo -i, затем bash install_hysteria2_v5.sh)"
   exit 1
fi

echo "=========================================="
echo "   Установка Hysteria2 — автонастройка (v5)"
echo "=========================================="
echo
warn "ПЕРЕД ПРОДОЛЖЕНИЕМ УБЕДИТЕСЬ:"
echo "  1. У вас есть домен, и его A-запись уже указывает на IP этого сервера."
echo "     (Проверить можно на https://dnschecker.org)"
echo "  2. DNS уже успел обновиться (обычно от 5 минут до пары часов)."
echo "  3. Порты 80 и 443 не заняты другим веб-сервером (nginx/apache и т.д.)."
echo
read -rp "Всё готово? Продолжить? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Остановлено. Настройте домен и запустите скрипт снова."
    exit 0
fi

# ---------- Сбор данных от пользователя ----------
echo
read -rp "Введите ваш домен (например vpn.example.com): " DOMAIN
read -rp "Введите ваш email (для Let's Encrypt): " EMAIL

echo
echo "Настройка пользователей (логин/пароль для подключения к VPN)."
echo "Можно добавить несколько — просто оставьте логин пустым, чтобы закончить."
declare -A USERS

while true; do
    read -rp "Имя пользователя (Enter — закончить ввод): " UNAME
    if [[ -z "$UNAME" ]]; then
        if [[ ${#USERS[@]} -eq 0 ]]; then
            warn "Нужен хотя бы один пользователь."
            continue
        fi
        break
    fi
    read -rp "Пароль для ${UNAME} (Enter — сгенерировать случайный): " UPASS
    if [[ -z "$UPASS" ]]; then
        UPASS=$(openssl rand -hex 16)
        info "Сгенерирован пароль для ${UNAME}: ${UPASS}"
    fi
    USERS["$UNAME"]="$UPASS"
done

# Порт SSH — подсказываем текущее значение из sshd_config, если найдём
# ВАЖНО: добавлен "|| true" — без него, если строка "Port" не найдена
# (это норма для Ubuntu 24.04 со стандартным портом 22), grep возвращает
# код выхода 1, и из-за "set -e" весь скрипт молча завершался именно тут.
CURRENT_SSH_PORT=$(grep -iE '^\s*Port\s+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tail -1 || true)
CURRENT_SSH_PORT=${CURRENT_SSH_PORT:-22}
echo
read -rp "На каком порту у вас SSH? (Enter — использовать ${CURRENT_SSH_PORT}): " SSH_PORT
SSH_PORT=${SSH_PORT:-$CURRENT_SSH_PORT}

# ---------- Уведомления на почту об обрыве сервера ----------
echo
read -rp "Настроить отправку уведомлений на почту при обрыве VPN-сервера? (y/n): " SETUP_ALERTS
SETUP_ALERTS=${SETUP_ALERTS:-n}

if [[ "$SETUP_ALERTS" == "y" || "$SETUP_ALERTS" == "Y" ]]; then
    ALERTS_ENABLED=1
    echo
    info "Письма будут отправляться через внешний SMTP-сервер (например Gmail/Yandex)."
    info "Нужен НЕ основной пароль, а 'пароль приложения' (генерируется в настройках"
    info "безопасности почты). Локальная отправка через sendmail часто попадает в спам,"
    info "поэтому используем внешний SMTP."
    echo
    read -rp "На какой email слать уведомления об обрыве? (Enter — использовать ${EMAIL}): " ALERT_EMAIL
    ALERT_EMAIL=${ALERT_EMAIL:-$EMAIL}

    echo "Выберите почтовый провайдер для отправки:"
    echo "  1) Gmail (smtp.gmail.com:587)"
    echo "  2) Yandex (smtp.yandex.ru:587)"
    echo "  3) Другой (ввести вручную)"
    read -rp "Выбор [1-3]: " SMTP_CHOICE
    case "$SMTP_CHOICE" in
        1) SMTP_HOST="smtp.gmail.com"; SMTP_PORT="587" ;;
        2) SMTP_HOST="smtp.yandex.ru"; SMTP_PORT="587" ;;
        3) read -rp "SMTP-сервер (например smtp.mail.ru): " SMTP_HOST
           read -rp "SMTP-порт (обычно 587): " SMTP_PORT
           SMTP_PORT=${SMTP_PORT:-587} ;;
        *) SMTP_HOST="smtp.gmail.com"; SMTP_PORT="587" ;;
    esac

    echo
    info "SMTP-логин — это ваш полный email-адрес (например Gmail), с которого"
    info "будут отправляться письма. На этот же адрес обычно и приходят логи,"
    info "если вы указали его же в качестве адреса для уведомлений выше."
    read -rp "SMTP-логин (ваш email-адрес): " SMTP_USER

    if [[ "$SMTP_HOST" == "smtp.gmail.com" ]]; then
        echo
        info "Для Gmail нужен НЕ обычный пароль от аккаунта, а отдельный"
        info "'пароль приложения'. Чтобы его получить:"
        info "  1. Включите двухфакторную аутентификацию (2FA) на аккаунте Google,"
        info "     если она ещё не включена: https://myaccount.google.com/security"
        info "  2. Перейдите на https://myaccount.google.com/apppasswords"
        info "  3. Создайте новый пароль приложения и скопируйте его сюда."
    fi
    read -rsp "Пароль приложения для SMTP: " SMTP_PASS
    echo
else
    ALERTS_ENABLED=0
fi

# ---------- 1) Настройка swap ----------
info "Проверка swap..."
CURRENT_SWAP_KB=$(awk '/SwapTotal/ {print $2}' /proc/meminfo)
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
AVAIL_MB=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)

if [[ "$CURRENT_SWAP_KB" -gt 0 ]]; then
    info "Swap уже настроен ($((CURRENT_SWAP_KB / 1024)) МиБ), пропускаю."
else
    echo
    info "Swap (подкачка) — это область на диске, которую система использует как"
    info "'дополнительную RAM', когда обычной памяти не хватает. Работает медленнее"
    info "настоящей RAM, но спасает сервер от падения программ при нехватке памяти."
    info "Сейчас: всего RAM ~${RAM_MB} МиБ, свободно (доступно) ~${AVAIL_MB} МиБ."

    if [[ "$AVAIL_MB" -lt 1024 ]]; then
        warn "Свободной RAM меньше 1 ГБ — swap ОБЯЗАТЕЛЕН, иначе сервер может"
        warn "падать/зависать под нагрузкой. Будет создан автоматически."
        MAKE_SWAP="y"
    else
        read -rp "Создать swap-файл? (y/n): " MAKE_SWAP
        MAKE_SWAP=${MAKE_SWAP:-y}
    fi

    if [[ "$MAKE_SWAP" == "y" || "$MAKE_SWAP" == "Y" ]]; then
        # Правило: swap = RAM, но не больше 2048 МиБ и не меньше 512 МиБ
        if   [[ "$RAM_MB" -le 512 ]];  then SWAP_MB=1024
        elif [[ "$RAM_MB" -le 2048 ]]; then SWAP_MB=$RAM_MB
        else SWAP_MB=2048
        fi

        info "Создаю swap-файл ${SWAP_MB} МиБ..."
        fallocate -l "${SWAP_MB}M" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q '^/swapfile ' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        info "Swap создан и подключён:"
        free -h
    else
        warn "Swap пропущен по вашему выбору. Не рекомендуется при малом объёме RAM."
    fi
fi

# ---------- 2) Обновление системы ----------
info "Обновление пакетов..."
apt update && apt upgrade -y

# ---------- 3) Установка Hysteria2 ----------
info "Установка Hysteria2..."
warn "Иногда во время этого шага SSH-сессия может кратковременно оборваться"
warn "(например из-за обновления openssh-server) — это не ошибка."
warn "Если соединение разорвётся — просто зайдите на сервер заново и"
warn "перезапустите скрипт: он спросит данные заново, это не страшно."
bash <(curl -fsSL https://get.hy2.sh/)

# ---------- 4) Сайт-заглушка ----------
info "Создание сайта-заглушки для маскировки..."
mkdir -p /var/www/masq
tee /var/www/masq/index.html >/dev/null <<'HTML'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Please wait</title><style>body{background:#080808;height:100vh;margin:0;display:flex;flex-direction:column;align-items:center;justify-content:center;font-family:sans-serif}.dots{display:flex;gap:15px;margin-bottom:30px}.d{width:20px;height:20px;background:#fff;border-radius:50%;animation:b 1.4s infinite ease-in-out both}.d:nth-child(1){animation-delay:-0.32s}.d:nth-child(2){animation-delay:-0.16s}@keyframes b{0%,80%,100%{transform:scale(0);opacity:0.2}40%{transform:scale(1);opacity:1}}.t{color:#555;font-size:14px;letter-spacing:2px;font-weight:600}</style></head><body><div class="dots"><div class="d"></div><div class="d"></div><div class="d"></div></div><div class="t">RETRYING CONNECTION</div></body></html>
HTML

# ---------- 5) Конфигурация ----------
info "Создание конфигурации /etc/hysteria/config.yaml..."
mkdir -p /etc/hysteria

{
    echo "listen: 0.0.0.0:443"
    echo ""
    echo "acme:"
    echo "  type: http"
    echo "  domains:"
    echo "    - ${DOMAIN}"
    echo "  email: ${EMAIL}"
    echo ""
    echo "auth:"
    echo "  type: userpass"
    echo "  userpass:"
    for UNAME in "${!USERS[@]}"; do
        echo "    ${UNAME}: ${USERS[$UNAME]}"
    done
    echo ""
    echo "masquerade:"
    echo "  type: file"
    echo "  file:"
    echo "    dir: /var/www/masq"
    echo "  listenHTTP: :80"
    echo "  listenHTTPS: :443"
    echo "  forceHTTPS: true"
} > /etc/hysteria/config.yaml
chmod 600 /etc/hysteria/config.yaml

info "Конфиг создан:"
echo "----------------------------------------"
cat /etc/hysteria/config.yaml
echo "----------------------------------------"

# ---------- 6) Запуск службы ----------
info "Запуск службы hysteria-server..."
systemctl daemon-reload
systemctl enable --now hysteria-server.service

# ---------- 6.1) Уведомления об обрыве службы на почту ----------
if [[ "$ALERTS_ENABLED" -eq 1 ]]; then
    info "Настройка отправки уведомлений на почту при обрыве сервиса..."
    apt install -y msmtp msmtp-mta mailutils >/dev/null 2>&1 || apt install -y msmtp msmtp-mta

    cat > /etc/msmtprc <<MSMTP
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        hysteria_alert
host           ${SMTP_HOST}
port           ${SMTP_PORT}
from           ${SMTP_USER}
user           ${SMTP_USER}
password       ${SMTP_PASS}

account default : hysteria_alert
MSMTP
    chmod 600 /etc/msmtprc

    # Лог-файл создаём заранее с ограниченными правами, чтобы msmtp не создал
    # его сам с правами по умолчанию (644) при первой отправке письма
    touch /var/log/msmtp.log
    chmod 600 /var/log/msmtp.log

    # Скрипт, который собирает последние логи и отправляет письмо
    cat > /usr/local/bin/hysteria-alert.sh <<ALERTSCRIPT
#!/usr/bin/env bash
LOGS=\$(journalctl -u hysteria-server.service -n 100 --no-pager)
HOST=\$(hostname)
{
    echo "To: ${ALERT_EMAIL}"
    echo "From: ${SMTP_USER}"
    echo "Subject: [ALERT] Hysteria2 упал на \${HOST}"
    echo
    echo "Служба hysteria-server остановилась/упала на сервере \${HOST} (${DOMAIN})."
    echo "Время: \$(date '+%Y-%m-%d %H:%M:%S')"
    echo
    echo "Последние строки лога:"
    echo "----------------------------------------"
    echo "\$LOGS"
} | msmtp "${ALERT_EMAIL}"
ALERTSCRIPT
    chmod 700 /usr/local/bin/hysteria-alert.sh

    # systemd unit, который срабатывает, когда hysteria-server.service падает (OnFailure)
    cat > /etc/systemd/system/hysteria-alert.service <<UNIT
[Unit]
Description=Отправка письма при обрыве Hysteria2

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hysteria-alert.sh
UNIT

    # Привязываем OnFailure к основному сервису
    mkdir -p /etc/systemd/system/hysteria-server.service.d
    cat > /etc/systemd/system/hysteria-server.service.d/override.conf <<OVERRIDE
[Unit]
OnFailure=hysteria-alert.service
OVERRIDE

    systemctl daemon-reload
    info "Уведомления настроены: письмо на ${ALERT_EMAIL} будет отправлено при падении службы."
    warn "Проверить вручную можно так: systemctl start hysteria-alert.service"
fi

# ---------- 7) Настройка ufw ----------
info "Проверка наличия ufw..."
if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw не найден, устанавливаю..."
    apt install ufw -y
fi

info "Настройка firewall (ufw)..."
ufw allow "${SSH_PORT}/tcp"
ufw allow 80/tcp
ufw allow 443/udp
ufw allow 443/tcp
ufw --force enable

echo
info "Firewall настроен. Статус:"
ufw status verbose

# ---------- Проверка службы ----------
sleep 2
echo
if systemctl is-active --quiet hysteria-server.service; then
    info "Служба hysteria-server запущена и активна."
else
    error "Служба не запустилась! Проверьте вывод: systemctl status hysteria-server.service"
    error "И логи: journalctl -u hysteria-server.service -n 50 --no-pager"
fi

# Проверка ACME/сертификата
echo
if journalctl -u hysteria-server.service --no-pager 2>/dev/null | grep -qi "authorization finalized"; then
    info "Сертификат Let's Encrypt успешно выпущен."
else
    warn "Не удалось подтвердить выпуск сертификата в логах."
    warn "Проверьте вручную: journalctl -u hysteria-server.service | grep -i acme"
fi

# ---------- Итог ----------
echo
echo "=========================================="
echo "   Установка завершена"
echo "=========================================="
echo
echo "Данные для подключения:"
echo "  Домен: ${DOMAIN}"
echo "  Порт:  443"
for UNAME in "${!USERS[@]}"; do
    echo "  Пользователь: ${UNAME} / Пароль: ${USERS[$UNAME]}"
done
echo
if [[ "$ALERTS_ENABLED" -eq 1 ]]; then
    info "Уведомления об обрыве сервиса: включены, отправка на ${ALERT_EMAIL}"
else
    warn "Уведомления об обрыве сервиса: не настроены (пропущено при установке)"
fi
echo
warn "ЧТО НУЖНО ПРОВЕРИТЬ ВРУЧНУЮ:"
echo "  1. Если предупреждение про сертификат появилось выше — проверьте:"
echo "     journalctl -u hysteria-server.service | grep -i acme"
echo "     (если ошибка — проверьте, что домен действительно указывает на IP"
echo "      этого сервера и порт 80/443 ничем больше не занят)"
echo
echo "  2. Настройте клиент (телефон/ПК) с данными выше — вручную в приложении"
echo "     Hysteria2/NekoBox/v2rayNG и т.п.: сервер = ${DOMAIN}, порт 443,"
echo "     протокол Hysteria2, логин/пароль — см. выше."
echo
echo "  3. Если хотите добавить ещё пользователей позже — отредактируйте"
echo "     /etc/hysteria/config.yaml вручную и выполните:"
echo "     systemctl restart hysteria-server.service"
echo
