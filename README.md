# FastXray — быстрая установка VPN-сервера

Автоматическая установка и настройка VPN-сервера на Debian с использованием:
- **Xray** (VLESS+REALITY, Shadowsocks)
- **Telegram MTProto-прокси** (mtg)
- **UFW** (firewall)

## Требования

- Debian 10+ или Ubuntu 18+
- root доступ (sudo)
- Минимум 512 MB RAM
- Открытые порты: 22 (SSH), 443, 8443, 2040, 8444

## Быстрая установка

**One-liner (скопируй и выполни):**
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/Dev-PGVAA/FastXray_Telegram_MTProto/refs/heads/main/setup_vpn.sh)"
```

**Или вручную:**
```bash
wget https://raw.githubusercontent.com/Dev-PGVAA/FastXray_Telegram_MTProto/refs/heads/main/setup_vpn.sh
sudo bash setup_vpn.sh
```

## Что делает скрипт

Во время установки скрипт спросит тебя:

1. **Название сервера** (страна/описание)
   - По умолчанию: `🇳🇱 Netherlands`
   - Пример: `My VPN UA`, `Germany`, `Custom Server`

2. **Создать нового пользователя?** (y/n)
   - Если да → введи имя, выбери способ входа
   - Варианты входа:
     - **Только пароль** — вход через `ssh user@ip`
     - **Только ключ** — безопаснее, по паролю не зайти
     - **И пароль, и ключ** — оба способа работают

3. **Отключить SSH доступ для root?** (y/n)
   - Рекомендуется: `y` (безопаснее)
   - Вход будет только через созданного пользователя

4. **Telegram MTProto-прокси?** (y/n)
   - Если да → дополнительный способ обхода через Telegram

После этого скрипт:
- Обновит систему, установит нужные пакеты
- Установит Xray с VLESS+REALITY на портах 443/8443
- Установит Shadowsocks на порту 2040 (резервной)
- Опционально установит MTProto-прокси на порту 8444
- Настроит UFW firewall
- Выведет готовые ссылки для клиентов

**Логирование:**
```bash
tail -f /var/log/vpn-setup.log
```

---

## 🔑 SSH-ключи: как добавить публичный ключ

Если ты выбрал вход **только по ключу** или **по ключу+пароль**, нужно добавить свой SSH-ключ на сервер.

### Вариант 1: На компьютере уже есть ключ

```bash
# Проверь есть ли ключ
ls ~/.ssh/id_*.pub

# Если есть, скопируй его на сервер
ssh-copy-id -i ~/.ssh/id_ed25519.pub username@your.server.ip
# (замени username на созданного пользователя, your.server.ip на IP)
```

### Вариант 2: Нужно создать новый ключ

На своём компе:
```bash
# Сгенерируй ключ
ssh-keygen -t ed25519 -C "your_email@example.com"
# Просто нажимай Enter на все вопросы

# Скопируй на сервер
ssh-copy-id -i ~/.ssh/id_ed25519.pub username@your.server.ip
```

Скрипт спросит пароль — введи пароль, который был выведен при установке.

### Вариант 3: Вручную через SSH

```bash
# Подключись к серверу
ssh username@your.server.ip
# Введи пароль

# Добавь свой публичный ключ
cat >> ~/.ssh/authorized_keys
# Вставь содержимое своего ~/.ssh/id_ed25519.pub
# Нажми Ctrl+D для выхода
```

### Проверка

После добавления ключа:
```bash
ssh username@your.server.ip
# Если не просит пароль — всё работает ✅
```

---

## 📱 Конфиги клиентов

После установки скрипт выведет:

**VLESS-ссылки:**
- `vless://...@ip:443?...` — основной (443)
- `vless://...@ip:8443?...` — резервной (8443)

**Shadowsocks:**
- `ss://...@ip:2040#...` — запасной вариант

**Telegram MTProto** (если выбрал y):
- `tg://proxy?server=ip&port=8444&secret=...`
- `https://t.me/proxy?server=ip&port=8444&secret=...`

**Base64-блок** со всеми ссылками сразу (для импорта подпиской)

### Где найти данные после установки

```bash
cat /usr/local/etc/xray/client_configs/README.txt
```

---

## 📲 Приложения клиентов

| ОС | Приложения |
|---|---|
| **Android** | v2RayTun, NekoBox, Hiddify, v2rayNG |
| **iOS** | Streisand, Shadowrocket, Stash |
| **Windows** | v2RayN, Nekoray, Hiddify, Clash for Windows |
| **macOS** | Hiddify, Nekoray, V2Box |
| **Linux** | Nekoray, Clash, v2rayA |

---

## 🛠️ Управление сервисами

```bash
# Xray
systemctl status xray
systemctl restart xray
journalctl -u xray -n 50

# MTProto (если установлен)
systemctl status mtg
systemctl restart mtg
journalctl -u mtg -n 50

# Firewall
ufw status numbered
ufw reload
```

---

## 📋 Файлы конфигов на сервере

```
/usr/local/etc/xray/config.json              # Xray конфиг
/usr/local/etc/xray/client_configs/README.txt # Все ссылки
/usr/local/etc/mtg/mtg.toml                 # MTProto конфиг (если установлен)
/var/log/vpn-setup.log                      # Логи установки
```

---

## 🔒 Безопасность

После установки:

1. **Отключи вход по паролю для root** (если выбрал y при установке)
   - Вход через созданного пользователя
   - Root доступ только через `sudo`

2. **Используй SSH-ключи** вместо паролей
   - Генерируй ключ локально
   - Добавь публичный ключ на сервер
   - Никогда не делись приватным ключом

3. **Меняй стандартные пароли**
   - Если был создан пользователь с паролем
   - Используй `passwd` для смены

---

## 🐛 Troubleshooting

### Установка упала с ошибкой
```bash
# Смотри полный лог
cat /var/log/vpn-setup.log
tail -f /var/log/vpn-setup.log
```

### Не могу подключиться по SSH
```bash
# Проверь что порт 22 открыт
sudo ufw status numbered
sudo ufw allow 22

# Проверь sshd статус
sudo systemctl status ssh
```

### Xray не работает
```bash
sudo systemctl restart xray
sudo journalctl -u xray -n 50
sudo xray test -c /usr/local/etc/xray/config.json
```

### MTProto не запускается
```bash
sudo systemctl restart mtg
sudo journalctl -u mtg -n 50
```

### Забыл пароль пользователя
```bash
# От root переустанови пароль
sudo passwd username
```

---

## 📝 Важные примечания

- Каждый запуск скрипта генерирует **новые ключи** и параметры
- SSH открыт на **порту 22** (не закрывается firewall)
- Firewall по умолчанию закрывает входящий трафик, открывает только нужные порты
- Все данные выводятся в финальном экране — **сохрани их перед закрытием терминала**
- README также сохраняется на сервере для справки

---

## 📄 Лицензия

MIT

## 🤝 Поддержка

Если есть проблемы:
1. Проверь логи: `/var/log/vpn-setup.log`
2. Убедись что скрипт запущен от root
3. Проверь наличие интернета и доступ к GitHub

---

**FastXray** — простая и быстрая установка VPN с поддержкой modern протоколов.
