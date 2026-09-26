#!/bin/sh
# Установка адаптера RKDash на стороне Hermes-агента.
#
# Использование:
#   RKDASH_KEY=rk_live_…  sh install.sh
#   sh install.sh rk_live_…
#   curl -fsSL <ссылка на этот файл> | RKDASH_KEY=rk_live_… sh
#
# Секретов внутри нет: ключ платформы передаётся при запуске и в репозиторий не попадает.
set -eu

PANEL="${RKDASH_URL:-https://rkdash.com}"
KEY="${RKDASH_KEY:-${1:-}}"
SKILL_NAME="${RKDASH_SKILL:-rkdash}"
HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
RAW_BASE="${RKDASH_RAW:-https://raw.githubusercontent.com/geniok1980/hermes-rkdash-adapter/main}"

# Профиль агента: у него свои навыки, свой конфиг и свой .env.
PROFILE="${RKDASH_PROFILE:-${HERMES_PROFILE:-}}"
if [ -n "$PROFILE" ]; then PROFILE_ARG="-p $PROFILE"; else PROFILE_ARG=""; fi

if [ -z "$KEY" ]; then
  echo "Не передан ключ платформы." >&2
  echo "Возьмите его в панели RKDash: Цифровые сотрудники → карточка исполнителя → «Комплект для установки»." >&2
  exit 1
fi

if ! command -v hermes >/dev/null 2>&1; then
  echo "Не найден hermes. Установите Hermes Agent и повторите:" >&2
  echo "  pip install hermes-agent" >&2
  exit 1
fi

echo "1/4 Навык платформы"
hermes $PROFILE_ARG skills install "$RAW_BASE/SKILL.md" --name "$SKILL_NAME" --force \
  || echo "   навык не установился автоматически — положите SKILL.md в навыки профиля вручную"

echo "2/4 Подключение инструментов платформы (MCP)"
mkdir -p "$HOME_DIR"
# Конфиг ищем там, где его читает именно этот Hermes: у профиля — свой файл,
# у одиночной установки — общий. Путь можно задать вручную через RKDASH_CONFIG.
CONFIG="${RKDASH_CONFIG:-}"
if [ -z "$CONFIG" ]; then
  if [ -n "$PROFILE" ] && [ -d "$HOME_DIR/profiles/$PROFILE" ]; then
    CONFIG="$HOME_DIR/profiles/$PROFILE/config.yaml"
  elif [ -f "$HOME_DIR/config.yaml" ]; then
    CONFIG="$HOME_DIR/config.yaml"
  else
    ONLY_PROFILE="$(ls -1 "$HOME_DIR/profiles" 2>/dev/null | head -1)"
    if [ -z "$ONLY_PROFILE" ]; then
      echo "Не нашёл конфиг Hermes в $HOME_DIR. Укажите путь: RKDASH_CONFIG=/путь/config.yaml" >&2
      exit 1
    fi
    CONFIG="$HOME_DIR/profiles/$ONLY_PROFILE/config.yaml"
  fi
fi
mkdir -p "$(dirname "$CONFIG")"
[ -f "$CONFIG" ] || : > "$CONFIG"
echo "   конфиг: $CONFIG"

RKDASH_MCP_URL="$PANEL/api/mcp" RKDASH_MCP_KEY="$KEY" RKDASH_CONFIG="$CONFIG" python3 - <<'PY'
import os
import re

config_path = os.environ['RKDASH_CONFIG']
url = os.environ['RKDASH_MCP_URL']
key = os.environ['RKDASH_MCP_KEY']
block = (
    "  rkdash:\n"
    f"    url: {url}\n"
    "    headers:\n"
    f"      Authorization: 'Bearer {key}'\n"
    "    description: Инструменты RKDash — данные ресторана, доска задач, события.\n"
)

with open(config_path, encoding='utf-8') as handle:
    text = handle.read()

if re.search(r'^mcp_servers:\s*$', text, re.M):
    # Раздел уже есть: заменяем или добавляем только запись rkdash, не трогая чужие серверы.
    lines = text.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.strip() == 'mcp_servers:')
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].strip() and not lines[i].startswith(('  ', '\t'))), len(lines))
    section = ''.join(lines[start:end])
    section = re.sub(r'^  rkdash:\n(?:    .*\n|      .*\n)*', '', section, flags=re.M)
    section = section.rstrip('\n') + '\n' + block
    text = ''.join(lines[:start]) + section + ''.join(lines[end:])
else:
    if text and not text.endswith('\n'):
        text += '\n'
    text += "mcp_servers:\n" + block

with open(config_path, 'w', encoding='utf-8') as handle:
    handle.write(text)
print('   инструменты прописаны')
PY

echo "3/4 Проверка связи с платформой"
hermes $PROFILE_ARG mcp test rkdash || {
  echo "   проверка не прошла — сверьте ключ и доступность $PANEL/api/mcp" >&2
  echo "   в панели должен быть включён MCP-сервер: Настройки → API" >&2
}

echo "4/4 Служба агента для прогонов от платформы"
if [ "${RKDASH_SKIP_API_SERVER:-}" = "1" ]; then
  echo "   пропущено по RKDASH_SKIP_API_SERVER=1 — платформа не сможет будить агента прогоном"
else
  AGENT_ENV="$HOME_DIR/.env"
  if [ -n "$PROFILE" ] && [ -f "$HOME_DIR/profiles/$PROFILE/.env" ]; then
    AGENT_ENV="$HOME_DIR/profiles/$PROFILE/.env"
  fi
  if grep -q '^API_SERVER_ENABLED=' "$AGENT_ENV" 2>/dev/null; then
    echo "   уже настроено: $AGENT_ENV"
  else
    cat >> "$AGENT_ENV" <<'ENV'

# Позволяет платформе звать этого агента прогоном по задаче с доски.
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=9131
API_SERVER_KEY=подставьте-свой-секрет
ENV
    echo "   добавлено в $AGENT_ENV — подставьте свой секрет в API_SERVER_KEY"
  fi
fi

echo
echo "Готово. Перезапустите Hermes: навык и инструменты подхватываются при старте."
echo "Проверка:  hermes $PROFILE_ARG mcp test rkdash"
echo "Дальше в панели RKDash:"
echo "  1) Настройки → API — включить MCP-сервер;"
echo "  2) Цифровые сотрудники → Подключить агента → «Внешний агент по API server»:"
echo "     адрес этого сервера и ключ из API_SERVER_KEY."
