"""Добавляет параметр super.key в конструкторы виджетов с параметрами.

Скрипт работает построчно и проверяет, что класс действительно является
виджетом: только в этом случае параметр key уместен.
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
)

CLASS_DECL = re.compile(
    r"class\s+(?P<name>\w+)\s+extends\s+(?P<base>\w+)"
)
CTOR_START = re.compile(r"^(?P<indent>\s*)const\s+(?P<name>\w+)\(\{$")


def is_widget(base: str) -> bool:
    return any(base.endswith(name) for name in WIDGET_BASES)


def process(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    out: list[str] = []
    fixed = 0
    index = 0

    while index < len(lines):
        line = lines[index]
        match = CTOR_START.match(line)
        if not match:
            out.append(line)
            index += 1
            continue

        indent = match.group("indent")
        ctor = match.group("name")

        # Копируем строки параметров до закрывающей `});` того же отступа.
        params: list[str] = []
        cursor = index + 1
        closing = re.compile(rf"^{indent}\}}\);")
        while cursor < len(lines) and not closing.match(lines[cursor]):
            params.append(lines[cursor])
            cursor += 1

        if cursor >= len(lines):
            out.append(line)
            index += 1
            continue

        # Ищем объявление класса рядом.
        decl = None
        for back in range(max(0, index - 6), index):
            found = CLASS_DECL.search(lines[back])
            if found:
                decl = found
        if decl is None or decl.group("name") != ctor or not is_widget(decl.group("base")):
            out.extend(lines[index : cursor + 1])
            index = cursor + 1
            continue

        if any("super.key" in p for p in params):
            out.extend(lines[index : cursor + 1])
            index = cursor + 1
            continue

        param_indent = re.match(r"\s*", params[0]).group(0) if params else indent + "  "
        out.append(line)
        out.append(f"{param_indent}super.key,")
        out.extend(params)
        out.append(lines[cursor])
        fixed += 1
        index = cursor + 1

    if fixed:
        path.write_text("\n".join(out), encoding="utf-8")
    return fixed


def main() -> int:
    total = 0
    for path in sorted(BASE.rglob("*.dart")):
        hits = process(path)
        if hits:
            print(f"  {path.relative_to(BASE)}: {hits}")
        total += hits
    print(f"Добавлено параметров key: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
