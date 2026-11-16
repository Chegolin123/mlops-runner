#!/usr/bin/env python3
"""Парсит лог тренировки mk-ai в JSON-метрики.

Использование:
    python scripts/collect_metrics.py train.log -o metrics/run.json

Формат строк mk-ai:
    [train] устройство: cuda  эпизодов: 500
    эп  100  winner=p1  hp  31.0: 0.0  hits 9+4  idle 0+1  R  +2.10/-1.80  loss 0.041  winrate 0.52
    [done] 500 эпизодов за 812.4 c (0.6 эп/с), средние удары 7.9, победы 268

Скрипт не падает на неполном логе: чего нет — того нет в JSON.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

EP_RE = re.compile(
    r"эп\s+(?P<episode>\d+)\s+winner=(?P<winner>\S+)\s+"
    r"hp\s+(?P<hp1>[\d.]+):(?P<hp2>[\d.]+)\s+"
    r"hits\s+(?P<hits1>\d+)\+(?P<hits2>\d+)\s+"
    r".*?loss\s+(?P<loss>[\d.]+)\s+winrate\s+(?P<winrate>[\d.]+)"
)
DEVICE_RE = re.compile(r"\[train\]\s+устройство:\s+(?P<device>\S+)\s+эпизодов:\s+(?P<episodes>\d+)")
DONE_RE = re.compile(
    r"\[done\]\s+(?P<episodes>\d+)\s+эпизодов\s+за\s+(?P<duration>[\d.]+)\s+c\s+"
    r"\((?P<eps>[\d.]+)\s+эп/с\).*?средние удары\s+(?P<avg_hits>[\d.]+),\s+победы\s+(?P<wins>\d+)"
)


def parse(text: str) -> dict:
    result: dict = {}
    samples: list[dict] = []

    for line in text.splitlines():
        if m := DEVICE_RE.search(line):
            result["device"] = m.group("device")
        if m := EP_RE.search(line):
            samples.append(
                {
                    "episode": int(m.group("episode")),
                    "winner": m.group("winner"),
                    "hp": [float(m.group("hp1")), float(m.group("hp2"))],
                    "hits": [int(m.group("hits1")), int(m.group("hits2"))],
                    "loss": float(m.group("loss")),
                    "winrate": float(m.group("winrate")),
                }
            )
        if m := DONE_RE.search(line):
            episodes = int(m.group("episodes"))
            duration = float(m.group("duration"))
            result.update(
                episodes=episodes,
                duration_s=duration,
                episodes_per_s=round(episodes / duration, 3) if duration else None,
                avg_hits=float(m.group("avg_hits")),
                wins=int(m.group("wins")),
                winrate=round(int(m.group("wins")) / episodes, 3) if episodes else None,
            )

    if samples:
        last = samples[-1]
        result.setdefault("last_episode", last["episode"])
        result.setdefault("last_loss", last["loss"])
        result.setdefault("last_winrate", last["winrate"])
    result["samples"] = samples
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="mk-ai log → metrics.json")
    ap.add_argument("log", type=Path, help="файл лога тренировки")
    ap.add_argument("-o", "--out", type=Path, default=Path("metrics/run.json"))
    args = ap.parse_args()

    if not args.log.exists():
        print(f"нет файла {args.log}", file=sys.stderr)
        return 1

    data = parse(args.log.read_text(encoding="utf-8", errors="replace"))
    if not data.get("episodes"):
        print("не нашёл [done] в логе — метрики неполные", file=sys.stderr)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in data.items() if k != "samples"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
