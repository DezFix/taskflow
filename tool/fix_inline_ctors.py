"""Добавляет super.key в однострочные конструкторы виджетов.

Оставшиеся случаи после предыдущего прогона: конструктор целиком
помещается в одну строку, поэтому параметры не собирались построчно.
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

CLASS_DECL = re.compile(r"class\s+(?P<name>\w+)\s+extends\s+(?P<base>\w+)")
INLINE_CTOR = re.compile(
    r"^(?P<indent>\s*)const\s+(?P<name>\w+)\(\{(?P<params>[^{}]+)\}\);$"
)


def is_widget(base: str) -> bool:
    return any(base.endswith(name) for name in WIDGET_BASES)


def process(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    fixed = 0

    for index, line in enumerate(lines):
        match = INLINE_CTOR.match(line)
        if not match:
            continue
        params = match.group("params")
        if "super.key" in params or "key" in params:
            continue

        decl = None
        for back in range(max(0, index - 4), index):
            found = CLASS_DECL.search(lines[back])
            if found:
                decl = found
        if decl is None or decl.group("name") != match.group("name"):
            continue
        if not is_widget(decl.group("base")):
            continue

        indent = match.group("indent")
        params = " ".join(p.strip() for p in params.split(",") if p.strip())
        lines[index] = (
            f"{indent}const {match.group('name')}({{\n"
            f"{indent}  super.key,\n"
            f"{indent}  {params},\n"
            f"{indent}}});"
        )
        fixed += 1

    if fixed:
        path.write_text("\n".join(lines), encoding="utf-8")
    return fixed


def main() -> int:
    total = 0
    for path in sorted(BASE.rglob("*.dart")):
        hits = process(path)
        if hits:
            print(f"  {path.relative_to(BASE)}: {hits}")
        total += hits
    print(f"Исправлено конструкторов: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
