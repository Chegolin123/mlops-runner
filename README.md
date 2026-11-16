# mlops-runner

Self-hosted GitHub Actions runner на **RTX 2070 SUPER**: ночные тренировки RL-агента, метрики и артефакты — без «у меня локально работает».

CI/CD с реальным GPU, а не имитацией в облаке: workflow приходит из GitHub, обучение идёт на домашней видеокарте, результат возвращается артефактом в тот же прогон.

## Зачем

- Облачные GPU-раннеры дорогие на ночь, а ПК всё равно простаивает.
- Нужны честные прогоны PyTorch с CUDA, а не CPU-заглушка.
- Артефакты (метрики, логи, чекпоинты) должны жить рядом с workflow, а не в чьей-то папке.

## Как это устроено

```
GitHub workflow (nightly-train.yml)
        │  job: runs-on: [self-hosted, gpu]
        ▼
GitHub Actions ← long-poll ← свой runner (systemd, пользователь ghrunner)
        │
        ├── checkout mk-ai
        ├── python + torch cu124 (venv)
        ├── python game.py --headless --episodes N
        ├── scripts/collect_metrics.py → metrics/*.json
        └── upload-artifact + job summary
```

Runner не открывает входящих портов: он сам ходит на `github.com` и забирает задания. Поэтому публичный IP и проброс не нужны.

## Быстрый старт

### 1. Токен регистрации (одноразовый, 1 час)

```bash
gh api -X POST repos/Chegolin123/mk-ai/actions/runners/registration-token --jq .token
```

### 2. Установка runner'а на машину с GPU

```bash
sudo REPO_URL=https://github.com/Chegolin123/mk-ai \
     REG_TOKEN=<токен из шага 1> \
     LABELS=self-hosted,gpu,linux \
     ./scripts/install-runner.sh
```

Скрипт идемпотентный: создаёт пользователя `ghrunner`, ставит runner в `/opt/actions-runner`, регистрирует и поднимает systemd-сервис. Повторный запуск перерегистрирует runner (`--replace`).

### 3. Проверка

```bash
systemctl status actions.runner.* --no-pager
gh api repos/Chegolin123/mk-ai/actions/runners --jq '.runners[] | "\(.name) \(.status) \(.labels[].name)"'
```

В GitHub: **Settings → Actions → Runners** — runner должен быть `Idle`.

### 4. Запуск тренировки

```bash
gh workflow run nightly-train.yml -f episodes=500 -f speed=4
gh run watch
```

## Метрики

`scripts/collect_metrics.py` парсит лог тренировки и складывает JSON:

```json
{
  "episodes": 500,
  "duration_s": 812.4,
  "episodes_per_s": 0.62,
  "wins": 268,
  "winrate": 0.536,
  "avg_hits": 7.9,
  "device": "cuda",
  "samples": [{"episode": 5, "winrate": 0.6, "loss": 0.041, "hp": [42.0, 0.0]}]
}
```

Дальше — артефакт прогона и короткая сводка в Job Summary. Историю можно строить по артефактам, без отдельной БД.

## Docker-вариант

Если не хочется ставить runner в систему:

```bash
REPO_URL=https://github.com/Chegolin123/mk-ai \
REG_TOKEN=<токен> \
docker compose -f deploy/docker-compose.yml up -d
```

Нужен `nvidia-container-toolkit` на хосте. Runner в контейнере видит GPU через `--gpus all`.

## Безопасность

- Токен регистрации одноразовый и живёт час; в конфиг попадает только после обмена на долгоживущий runner-токен.
- Runner запускается от отдельного пользователя `ghrunner`, не от root и не от твоего аккаунта.
- Публичные форки не должны попадать на этот runner: в настройках репозитория оставь **Require approval for all outside collaborators** и не включай `runs-on` для `pull_request` с внешних форков.
- Секреты (токены, ключи) — только в GitHub Secrets, никогда в workflow-файле.
- Runner видит твою домашнюю сеть. Если ПК не выделенный — поднимай runner в отдельном контейнере/VM с ограниченным доступом к сети.

## Что дальше

- [ ] Кэш pip/torch между прогонами (сейчас зависимости ставятся каждый раз)
- [ ] Чекпоинты `policy.pt` как артефакт с retention 30 дней
- [ ] Сравнение winrate между ночами и график в README
- [ ] Второй runner на CPU для лёгких job'ов

## Стек

`GitHub Actions` · `bash` · `systemd` · `Docker` · `Python` · `PyTorch CUDA 12.4` · `nvidia-container-toolkit`

## Лицензия

MIT
