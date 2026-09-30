"""Чинит параметры конструкторов, склеенные в одну строку.

Предыдущий скрипт объединял параметры через пробел, из-за чего
`required this.a, required this.b` превратилось в
`required this.a required this.b`. Разделяем такие параметры обратно.
"""

from __future__ import annotations

import re
from pathlib import Path

BASE = Path(r"D:\CODE\Task-work\taskflow\lib")

# Строка параметров: один или больше `required this.x` / `this.x` / `super.x`
BROKEN = re.compile(
    r"^(?P<indent>\s+)(?P<params>(?:required\s+)?(?:this|super)\.\w+"
    r"(?:\s*=\s*[^,]+)?(?:\s*[,)]?\s*)+)+?,?$"
)
SEPARATOR = re.compile(r"(?P<prefix>(?:required\s+)?(?:this|super)\.\w+(?:\s*=\s*[^,]+)?)\s+(?=required\s+)")


def process(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    out: list[str] = []
    fixed = 0
    in_ctor = False

    for line in lines:
        stripped = line.strip()

        if re.match(r"^\s*const\s+\w+\(\{$", line):
            in_ctor = True
            out.append(line)
            continue

        if in_ctor:
            if re.match(r"^\s*\}\);", line):
                in_ctor = False
                out.append(line)
                continue

            if "required" in stripped and stripped.count("required") > 1:
                # Разделяем склеенные параметры.
                indent = re.match(r"\s*", line).group(0)
                pieces = re.split(r"(?=required\s+)", stripped)
                for piece in pieces:
                    piece = piece.strip().rstrip(",").strip()
                    if piece:
                        out.append(f"{indent}{piece},")
                fixed += 1
                continue

        out.append(line)

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
    print(f"Исправлено строк параметров: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
