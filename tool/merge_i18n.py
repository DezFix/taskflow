"""Сливает переводы из фрагментов в ARB-файлы.

Фрагменты собирают агенты по экранам, а ARB-файлы общие. Слияние идёт
разово, поэтому скрипт заодно проверяет, что:

* каждый ключ из фрагмента реально используется в коде;
* каждый используемый ключ имеет перевод на всех трёх языках;
* нет расхождений между фрагментами по одному и тому же ключу.

Так ошибка агента не попадёт в приложение молча.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARB_DIR = ROOT / "lib" / "l10n" / "arb"
FRAGMENTS = sorted((ROOT / "tool" / "i18n").glob("*.json"))
LOCALES = ("ru", "uk", "en")

# Псевдоним, которым код называет объект локализации:
#   final l10n = AppLocalizations.of(context);
ALIAS_DECL = re.compile(
    r"(?:final|var|const)\s+(\w+)\s*=\s*AppLocalizations\.of\(",
)

# Прямой вызов: AppLocalizations.of(context).key
DIRECT = re.compile(r"AppLocalizations\.of\(context\)\.(\w+)")


def used_keys() -> set[str]:
    """Собирает ключи, реально используемые в коде.

    Код обращается к переводам двумя способами: напрямую
    `AppLocalizations.of(context).key` и через локальный псевдоним
    `l10n.key`. Учитываем оба, иначе посчитаем ключи неиспользуемыми.
    """
    keys: set[str] = set()
    for path in (ROOT / "lib").rglob("*.dart"):
        if "l10n" in path.parts:
            continue
        text = path.read_text(encoding="utf-8")
        keys.update(DIRECT.findall(text))
        for alias in set(ALIAS_DECL.findall(text)):
            keys.update(re.findall(rf"\b{re.escape(alias)}\.(\w+)", text))
    return keys


def load_arb(locale: str) -> dict:
    path = ARB_DIR / f"app_{locale}.arb"
    return json.loads(path.read_text(encoding="utf-8"))


def save_arb(locale: str, data: dict) -> None:
    path = ARB_DIR / f"app_{locale}.arb"
    header = {
        "ru": "Переводы интерфейса TaskFlow. Русский — язык по умолчанию.",
        "uk": "Переклади інтерфейсу TaskFlow. Українська.",
        "en": "TaskFlow interface translations. English is the template locale.",
    }[locale]
    ordered: dict = {"@@locale": locale}
    if locale == "en":
        ordered["@@description"] = header
    for key, value in data.items():
        if key.startswith("@@"):
            continue
        ordered[key] = value
    path.write_text(
        json.dumps(ordered, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    used = used_keys()
    merged: dict[str, dict] = {}
    conflicts: list[str] = []
    unused: list[str] = []

    for fragment in FRAGMENTS:
        data = json.loads(fragment.read_text(encoding="utf-8"))
        for item in data.get("keys", []):
            key = item["key"]
            if key not in used:
                unused.append(f"{key} ({fragment.name})")
                continue
            entry = {loc: item[loc] for loc in LOCALES}
            if key in merged:
                if merged[key] != entry:
                    conflicts.append(key)
                continue
            merged[key] = entry

    if conflicts:
        print("Расхождения между фрагментами:")
        for key in conflicts:
            print(f"  {key}")
            print(f"    было : {merged[key]}")
        return 1

    if unused:
        print("Ключи без использования в коде (пропущены):")
        for key in sorted(set(unused)):
            print(f"  {key}")

    arbs = {loc: load_arb(loc) for loc in LOCALES}
    for locale in LOCALES:
        base = {k: v for k, v in arbs[locale].items() if not k.startswith("@@") and not k.startswith("@")}
        for key, entry in merged.items():
            base[key] = entry[locale]
        arbs[locale] = base

    # Проверка полноты: используемый ключ должен быть во всех языках.
    problems: list[str] = []
    for locale in LOCALES:
        for key in sorted(used):
            if key not in arbs[locale]:
                problems.append(f"{locale}: нет ключа {key}")
            elif not arbs[locale][key]:
                problems.append(f"{locale}: пустое значение {key}")
    if problems:
        print("Неполные переводы:")
        for line in problems[:40]:
            print(f"  {line}")
        if len(problems) > 40:
            print(f"  ...ещё {len(problems) - 40}")
        return 1

    # Ключи, объявленные в ARB, но не используемые: оставляем служебные.
    for locale in LOCALES:
        save_arb(locale, arbs[locale])

    total = len(merged)
    print(f"Добавлено ключей: {total}")
    for locale in LOCALES:
        count = len([k for k in arbs[locale] if not k.startswith("@")])
        print(f"  app_{locale}.arb: {count} записей")
    return 0


if __name__ == "__main__":
    sys.exit(main())
