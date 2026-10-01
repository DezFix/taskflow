"""Считает объём пользовательских надписей в клиенте TaskFlow.

Нужно, чтобы оценить трудоёмкость перевода интерфейса на несколько
языков и решить, хватает ли ручного словаря или нужен gen-l10n.
"""

from __future__ import annotations

import collections
import pathlib
import re

# Строковый литерал с кириллицей внутри.
PATTERN = re.compile(
    r"'((?:[^'\\\n]|\\.)*(?:[А-Яа-яЁё](?:[^'\\\n]|\\.)*))'"
    r'|"((?:[^"\\\n]|\\.)*(?:[А-Яа-яЁё](?:[^"\\\n]|\\.)*))"'
)

# Технические строки, которые переводить не нужно.
SKIP_PREFIX = ("http", "/api", "assets/", "Bearer", "text/csv", "utf-8")
SKIP_EXACT = {
    "ru", "uk", "en",
    "Отправить",  # встретится как пример, помечаем отдельно при разборе
}
TECHNICAL = re.compile(r"^[A-Za-z0-9_./:@?=&%+\-\s]+$")


def collect() -> tuple[set[str], collections.Counter[str]]:
    per_file: collections.Counter[str] = collections.Counter()
    unique: set[str] = set()

    for path in sorted(pathlib.Path("lib").rglob("*.dart")):
        # Генерируемые переводы не считаем: они и есть результат перевода.
        if "l10n" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        found: set[str] = set()
        for match in PATTERN.finditer(text):
            value = (match.group(1) or match.group(2) or "").strip()
            if len(value) < 2:
                continue
            if value.startswith(SKIP_PREFIX):
                continue
            if TECHNICAL.match(value):
                continue
            found.add(value)
        if found:
            per_file[str(path)] = len(found)
            unique |= found

    return unique, per_file


def main() -> int:
    unique, per_file = collect()
    for name, count in per_file.most_common(15):
        print(f"{count:4d}  {name}")
    print("-" * 46)
    print(f"уникальных надписей: {len(unique)}")
    print(f"для ru + uk + en нужно записей: {len(unique) * 3}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
