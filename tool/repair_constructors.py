"""Чинит конструкторы, повреждённые скриптом добавления параметра key.

Скрипт вставлял `super.key,` перед списком параметров, но для некоторых
конструкторов закрывающая скобка `});` дублировалась. Убираем подряд
идущие одинаковые закрывающие строки.
"""

from __future__ import annotations

import re
from pathlib import Path

BASE = Path(r"D:\CODE\Task-work\taskflow\lib")


def repair(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    cleaned: list[str] = []
    fixed = 0

    for line in lines:
        # Закрывающая скобка сразу после такой же — лишняя.
        if (
            cleaned
            and re.match(r"^\s*\}\);\s*$", line)
            and re.match(r"^\s*\}\);\s*$", cleaned[-1])
        ):
            fixed += 1
            continue
        cleaned.append(line)

    if fixed:
        path.write_text("\n".join(cleaned), encoding="utf-8")
    return fixed


def main() -> int:
    total = 0
    for path in sorted(BASE.rglob("*.dart")):
        hits = repair(path)
        if hits:
            print(f"  {path.relative_to(BASE)}: убрано дублей {hits}")
        total += hits
    print(f"Исправлено дублирующихся закрывающих строк: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
