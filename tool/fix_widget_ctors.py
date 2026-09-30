"""Возвращает виджетам корректный конструктор с параметром key.

После отката осталось `const Имя({});` — такой конструктор недействителен.
Для классов, наследующих виджет, заменяем на `const Имя({super.key});`.
"""

from __future__ import annotations

import re
from pathlib import Path

BASE = Path(r"D:\CODE\Task-work\taskflow\lib")

WIDGET_BASES = (
    "StatelessWidget",
    "StatefulWidget",
    "ConsumerWidget",
    "ConsumerStatefulWidget",
    "HookWidget",
    "HookConsumerWidget",
)

# `class Имя extends База {` в строке выше конструктора
CLASS_DECL = re.compile(
    r"class\s+(?P<name>\w+)\s+extends\s+(?P<base>\w+)\s*(?:with\s+[^{]+?)?\{"
)
BROKEN_CTOR = re.compile(r"^(\s*)const\s+(\w+)\(\{\}\);$")


def is_widget_base(base: str) -> bool:
    return any(base.endswith(name) for name in WIDGET_BASES)


def repair(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    fixed = 0

    for index, line in enumerate(lines):
        match = BROKEN_CTOR.match(line)
        if not match:
            continue

        indent, ctor_name = match.group(1), match.group(2)

        # Ищем объявление класса выше по тексту.
        class_match = None
        for back in range(index - 1, max(-1, index - 6), -1):
            found = CLASS_DECL.search(lines[back])
            if found:
                class_match = found
                break

        if class_match is None:
            continue
        if class_match.group("name") != ctor_name:
            continue
        if not is_widget_base(class_match.group("base")):
            continue

        lines[index] = f"{indent}const {ctor_name}({{super.key}});"
        fixed += 1

    if fixed:
        path.write_text("\n".join(lines), encoding="utf-8")
    return fixed


def main() -> int:
    total = 0
    for path in sorted(BASE.rglob("*.dart")):
        hits = repair(path)
        if hits:
            print(f"  {path.relative_to(BASE)}: {hits}")
        total += hits
    print(f"Исправлено конструкторов: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
