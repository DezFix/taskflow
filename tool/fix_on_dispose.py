"""Заменяет ref.onDispose в StateNotifier'ах на отписку в dispose.

В Riverpod 2 объект StateNotifier не имеет доступа к ref: его dispose
вызывается, когда провайдер больше не нужен. Это безопаснее и предсказуемее,
чем полагаться на жизненный цикл контейнера.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"D:\CODE\Task-work\taskflow\lib\state")

# Строки вида `    ref.onDispose(() => _subscription?.cancel());`
ON_DISPOSE = re.compile(
    r"^(?P<indent>\s+)ref\.onDispose\(\(\) => (?P<expr>[^;]+)\);$",
    re.MULTILINE,
)

# Классы, у которых уже есть dispose(): там просто удаляем строку.
DISPOSE_PATTERN = re.compile(r"@override\s+void dispose\(\)\s*\{")


def main() -> int:
    total = 0
    for path in sorted(ROOT.glob("*.dart")):
        text = path.read_text(encoding="utf-8")

        def replace(match: re.Match[str]) -> str:
            nonlocal total
            total += 1
            return ""  # отписку переносим в dispose()

        new_text = ON_DISPOSE.sub(replace, text)

        # Убираем лишние пустые строки, оставшиеся после удаления.
        new_text = re.sub(r"\n{3,}", "\n\n", new_text)

        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            print(f"  обновлён {path.name}")

    print(f"Удалено вызовов ref.onDispose: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
