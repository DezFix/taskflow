"""Откат неудачного добавления параметра key.

Скрипт add_key_params.py вставлял super.key в конструкторы обычных
классов, а не только виджетов. Здесь убираем всё лишнее и возвращаем
конструкторы к исходному виду.
"""

from __future__ import annotations

import re
from pathlib import Path

BASE = Path(r"D:\CODE\Task-work\taskflow\lib")

# Конструктор без параметров, в который был добавлен key
INLINE_KEY = re.compile(r"const (\w+)\(\{super\.key\}\);")
# Многострочный список параметров с добавленной строкой super.key,
KEY_LINE = re.compile(r"^\s*super\.key,\s*$")


def revert(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    original = text

    text = INLINE_KEY.sub(r"const \1({});", text)

    lines = text.split("\n")
    cleaned: list[str] = []
    for line in lines:
        if KEY_LINE.match(line):
            continue
        cleaned.append(line)

    text = "\n".join(cleaned)

    if text != original:
        path.write_text(text, encoding="utf-8")
    return 0 if text == original else 1


def main() -> int:
    total = 0
    for path in sorted(BASE.rglob("*.dart")):
        total += revert(path)
    print(f"Восстановлено файлов: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
