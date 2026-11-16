#!/usr/bin/env bash
# Установка self-hosted GitHub Actions runner.
# Идемпотентно: повторный запуск перерегистрирует runner (--replace).
#
# Переменные:
#   REPO_URL      обязательно, https://github.com/owner/repo
#   REG_TOKEN     обязательно, одноразовый токен регистрации
#   RUNNER_NAME   по умолчанию <hostname>-gpu
#   LABELS        по умолчанию self-hosted,gpu,linux
#   RUNNER_USER   по умолчанию ghrunner
#   RUNNER_HOME   по умолчанию /opt/actions-runner
#   RUNNER_VERSION по умолчанию 2.319.1
set -euo pipefail

: "${REPO_URL:?Укажи REPO_URL, например https://github.com/owner/repo}"
: "${REG_TOKEN:?Укажи REG_TOKEN (registration token)}"

RUNNER_VERSION="${RUNNER_VERSION:-2.319.1}"
RUNNER_USER="${RUNNER_USER:-ghrunner}"
RUNNER_HOME="${RUNNER_HOME:-/opt/actions-runner}"
LABELS="${LABELS:-self-hosted,gpu,linux}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-gpu}"
ARCH="$(uname -m)"

if [[ $EUID -ne 0 ]]; then
  echo "Нужны права root: sudo REPO_URL=... REG_TOKEN=... $0" >&2
  exit 1
fi

case "$ARCH" in
  x86_64)  ASSET="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" ;;
  aarch64) ASSET="actions-runner-linux-arm64-${RUNNER_VERSION}.tar.gz" ;;
  *) echo "Неизвестная архитектура: $ARCH" >&2; exit 1 ;;
esac

echo "== Проверка GPU"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader || true
else
  echo "nvidia-smi не найден: runner поднимется, но GPU-job'ы будут падать. Продолжаю." >&2
fi

echo "== Пользователь $RUNNER_USER"
if ! id -u "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$RUNNER_USER"
fi
# доступ к GPU-устройствам
for g in /dev/nvidia*; do
  [[ -e "$g" ]] && chmod 666 "$g" || true
done

echo "== Скачивание runner $RUNNER_VERSION"
mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME"
if [[ ! -f ".runner-${RUNNER_VERSION}.installed" ]]; then
  curl -fsSL -o "$ASSET" "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${ASSET}"
  tar xzf "$ASSET"
  rm -f "$ASSET"
  ./bin/installdependencies.sh
  touch ".runner-${RUNNER_VERSION}.installed"
fi
chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_HOME"

echo "== Регистрация $RUNNER_NAME ($LABELS)"
sudo -u "$RUNNER_USER" ./config.sh \
  --url "$REPO_URL" \
  --token "$REG_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$LABELS" \
  --work "_work" \
  --unattended \
  --replace

echo "== systemd-сервис"
./svc.sh install "$RUNNER_USER"
./svc.sh start
./svc.sh status || true

echo
echo "Готово. Проверка:"
echo "  systemctl status 'actions.runner.*' --no-pager"
echo "  gh api repos/${REPO_URL#https://github.com/}/actions/runners"
