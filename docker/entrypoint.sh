#!/usr/bin/env bash
# Entrypoint контейнерного runner'а.
# Первый запуск: регистрация по одноразовому токену. Дальше — просто run.sh.
set -euo pipefail

: "${REPO_URL:?REPO_URL не задан}"
: "${ACCESS_TOKEN:?ACCESS_TOKEN (registration token) не задан}"

cd /actions-runner

if [[ ! -f .runner ]]; then
  echo "== Регистрация $(hostname) в $REPO_URL"
  ./config.sh \
    --url "$REPO_URL" \
    --token "$ACCESS_TOKEN" \
    --name "${RUNNER_NAME:-$(hostname)}" \
    --labels "${LABELS:-self-hosted,gpu,linux}" \
    --work _work \
    --unattended \
    --replace
fi

# Конфиг содержит долгоживущий токен — не показываем его в логах
unset ACCESS_TOKEN || true

exec ./run.sh
