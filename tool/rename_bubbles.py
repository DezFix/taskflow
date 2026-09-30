"""Делает виджеты экрана чата доступными из соседнего файла.

Приватные имена (_Bubble) не видны за пределами библиотеки, поэтому
переименовываем их в публичные.
"""

from __future__ import annotations

import re
from pathlib import Path

BASE = Path(r"D:\CODE\Task-work\taskflow\lib\ui\screens")

RENAMES = {
    "_MessageBubble": "MessageBubble",
    "_Composer": "ChatComposer",
    "_RecordingBar": "RecordingBar",
    "_PulsingDot": "PulsingDot",
    "_VoiceBubble": "VoiceBubble",
    "_ImagePreview": "ImagePreview",
    "_FileRow": "FileRow",
    "_MessageMeta": "MessageMeta",
    "_BubbleContent": "BubbleContent",
}


def rename(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    original = text
    count = 0

    for old, new in RENAMES.items():
        pattern = re.compile(rf"(?<![A-Za-z0-9_]){re.escape(old)}(?![A-Za-z0-9_])")
        text, hits = pattern.subn(new, text)
        count += hits

    if text != original:
        path.write_text(text, encoding="utf-8")
    return count


def main() -> int:
    total = 0
    for path in sorted(BASE.glob("chat_bubbles.dart")):
        hits = rename(path)
        total += hits
        print(f"{path.name}: заменено {hits}")
    print(f"Всего: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
