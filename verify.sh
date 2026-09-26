#!/bin/sh
# Проверка адаптера RKDash на стороне агента: навык, инструменты, связь, служба агента.
# Запуск:  sh verify.sh
set -u

PANEL="${RKDASH_URL:-https://rkdash.com}"
SKILL_NAME="${RKDASH_SKILL:-rkdash}"
HOME_DIR="${HERMES_HOME:-$HOME/.hermes}"
PROFILE="${RKDASH_PROFILE:-${HERMES_PROFILE:-}}"
if [ -n "$PROFILE" ]; then PROFILE_ARG="-p $PROFILE"; else PROFILE_ARG=""; fi

ok=0
bad=0
say() { printf '  %s %s\n' "$1" "$2"; }
good() { ok=$((ok + 1)); say "✓" "$1"; }
fail() { bad=$((bad + 1)); say "✗" "$1"; }

echo "Адаптер RKDash — проверка"
echo "  панель: $PANEL"
echo "  профиль: ${PROFILE:-по умолчанию}"

if command -v hermes >/dev/null 2>&1; then
  good "Hermes найден: $(hermes --version 2>/dev/null | head -1)"
else
  fail "Hermes не найден в PATH"
fi

# Навык: ищем SKILL.md в навыках профиля и в общих навыках.
SKILL_FOUND=""
for candidate in \
  "$HOME_DIR/profiles/$PROFILE/skills/$SKILL_NAME/SKILL.md" \
  "$HOME_DIR/skills/$SKILL_NAME/SKILL.md" \
  "$HOME_DIR/skills/$SKILL_NAME.md"; do
  [ -f "$candidate" ] && SKILL_FOUND="$candidate" && break
done
if [ -n "$SKILL_FOUND" ]; then
  good "навык установлен: $SKILL_FOUND"
else
  fail "навык «$SKILL_NAME» не найден в $HOME_DIR — запустите install.sh"
fi

# Инструменты: запись в конфиге и живая проверка связи.
CONFIG="${RKDASH_CONFIG:-}"
if [ -z "$CONFIG" ]; then
  if [ -n "$PROFILE" ] && [ -f "$HOME_DIR/profiles/$PROFILE/config.yaml" ]; then
    CONFIG="$HOME_DIR/profiles/$PROFILE/config.yaml"
  else
    CONFIG="$HOME_DIR/config.yaml"
  fi
fi
if grep -q 'rkdash:' "$CONFIG" 2>/dev/null; then
  good "MCP-сервер прописан: $CONFIG"
else
  fail "в $CONFIG нет записи rkdash — запустите install.sh"
fi

if command -v hermes >/dev/null 2>&1; then
  if hermes $PROFILE_ARG mcp test rkdash >/dev/null 2>&1; then
    good "связь с платформой есть, инструменты получены"
  else
    fail "hermes mcp test rkdash не прошёл: сверьте ключ и включённый MCP-сервер в панели"
  fi
fi

# Служба агента: платформа зовёт агента прогоном по задаче.
AGENT_ENV="$HOME_DIR/.env"
[ -n "$PROFILE" ] && [ -f "$HOME_DIR/profiles/$PROFILE/.env" ] && AGENT_ENV="$HOME_DIR/profiles/$PROFILE/.env"
if grep -q '^API_SERVER_ENABLED=true' "$AGENT_ENV" 2>/dev/null; then
  PORT="$(grep -E '^API_SERVER_PORT=' "$AGENT_ENV" | cut -d= -f2 | tr -d '[:space:]')"
  PORT="${PORT:-9131}"
  if python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:$PORT/health', timeout=5).status == 200 else 1)" 2>/dev/null; then
    good "служба агента отвечает на порту $PORT — платформа сможет будить его прогоном"
  else
    fail "служба агента не отвечает на порту $PORT: перезапустите Hermes и проверьте API_SERVER_KEY"
  fi
elif grep -q '^API_SERVER_ENABLED=' "$AGENT_ENV" 2>/dev/null; then
  fail "в $AGENT_ENV служба выключена (API_SERVER_ENABLED не true)"
else
  fail "в $AGENT_ENV нет блока службы — платформа не сможет будить агента прогоном"
fi

echo
if [ "$bad" -eq 0 ]; then
  echo "Всё на месте: $ok проверок."
else
  echo "Не прошло: $bad из $((ok + bad)). Что осталось — см. README.md."
fi
exit 0
