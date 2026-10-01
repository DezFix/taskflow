"""Добавляет ключи в ARB-файлы из одного JSON-описания.

Нужен для оставшихся экранов: вкладки, подписи статусов, даты и
тексты ошибок. Ключи с плейсхолдерами требуют описаний в @-секции
шаблона, иначе gen-l10n не соберёт подстановку.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARB_DIR = ROOT / "lib" / "l10n" / "arb"
LOCALES = ("ru", "uk", "en")


def main() -> int:
    source = ROOT / "tool" / "i18n" / "remaining.json"
    data = json.loads(source.read_text(encoding="utf-8"))

    for locale in LOCALES:
        path = ARB_DIR / f"app_{locale}.arb"
        current = json.loads(path.read_text(encoding="utf-8"))
        for item in data["keys"]:
            key = item["key"]
            current[key] = item[locale]
            if locale == "en" and "placeholders" in item:
                meta = {"description": item.get("description", "")}
                placeholders = {}
                for name in item["placeholders"]:
                    placeholders[name] = {}
                meta["placeholders"] = placeholders
                current[f"@{key}"] = meta
        path.write_text(
            json.dumps(current, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    print(f"Добавлено ключей: {len(data['keys'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
