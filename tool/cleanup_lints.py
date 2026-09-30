"""Убирает super.key из приватных виджетов и лишние импорты.

Приватные виджеты (имя с подчёркиванием) создаются только внутри своего
файла, поэтому параметр key им не нужен. Заодно удаляются импорты,
которые анализатор признал неиспользуемыми: список берём из вывода
flutter analyze, а не пытаемся угадать.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANALYZE = ROOT / "analyze.txt"

CLASS_DECL = re.compile(r"^class\s+(?P<name>\w+)\s+extends\s+")
UNUSED_IMPORT = re.compile(
    r"^\s*warning - Unused import: '(?P<path>[^']+)'.* - (?P<file>[\w\\.]+):"
)


def read_findings() -> dict[str, list[str]]:
    """Читает analyze.txt и возвращает неиспользуемые импорты по файлам."""
    if not ANALYZE.exists():
        return {}

    result: dict[str, list[str]] = {}
    for line in ANALYZE.read_text(encoding="utf-8", errors="replace").split("\n"):
        match = UNUSED_IMPORT.search(line)
        if not match:
            continue
        target = match.group("file").replace("\\", "/")
        result.setdefault(target, []).append(match.group("path"))
    return result


def strip_key_from_private(path: Path) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    out: list[str] = []
    fixed = 0
    current_class = ""

    for line in lines:
        decl = CLASS_DECL.match(line)
        if decl:
            current_class = decl.group("name")

        if current_class.startswith("_") and re.match(
            r"^\s*super\.key,\s*$", line
        ):
            fixed += 1
            continue

        out.append(line)

    if fixed:
        path.write_text("\n".join(out), encoding="utf-8")
    return fixed


def remove_imports(path: Path, imports: list[str]) -> int:
    lines = path.read_text(encoding="utf-8").split("\n")
    targets = {f"import '{item}';" for item in imports}
    out = [line for line in lines if line.strip() not in targets]
    removed = len(lines) - len(out)
    if removed:
        path.write_text("\n".join(out), encoding="utf-8")
    return removed


def main() -> int:
    findings = read_findings()
    if not findings:
        print("analyze.txt не найден или нет замечаний об импортах")
        return 1

    total_keys = 0
    total_imports = 0

    for relative, imports in findings.items():
        target = ROOT / "lib" / relative if not relative.startswith("lib") else ROOT / relative
        target = ROOT / Path(relative.replace("\\", "/"))
        if not target.exists():
            continue
        removed = remove_imports(target, imports)
        if removed:
            print(f"  {relative}: убрано импортов {removed}")
        total_imports += removed

    for path in sorted((ROOT / "lib").rglob("*.dart")):
        hits = strip_key_from_private(path)
        if hits:
            print(f"  {path.relative_to(ROOT)}: убрано super.key {hits}")
        total_keys += hits

    print(f"Импортов удалено: {total_imports}, super.key удалено: {total_keys}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
