#!/usr/bin/env python3
"""Copies the real app logos from design/logos/ into the asset catalog.

File names (PNG or PDF, square, transparent background preferred):
  chatgpt, claude, gemini, reddit, mail, safari, messages
Each becomes an image asset named logo-<name>, which SourceTile shows
instead of its fallback symbol.

Usage: python3 scripts/import_logos.py
"""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design/logos"
CATALOG = ROOT / "Notchman/Resources/Assets.xcassets"
NAMES = ["chatgpt", "claude", "gemini", "reddit", "mail", "safari", "messages"]


def main():
    imported = []
    for name in NAMES:
        for ext in ("pdf", "png", "svg"):
            src = SOURCE / f"{name}.{ext}"
            if not src.exists():
                continue
            folder = CATALOG / f"logo-{name}.imageset"
            if folder.exists():
                shutil.rmtree(folder)
            folder.mkdir(parents=True)
            shutil.copy(src, folder / src.name)
            contents = {
                "images": [{"filename": src.name, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }
            if ext in ("pdf", "svg"):
                contents["properties"] = {"preserves-vector-representation": True}
            (folder / "Contents.json").write_text(json.dumps(contents, indent=2))
            imported.append(src.name)
            break
    missing = [n for n in NAMES if not any((SOURCE / f"{n}.{e}").exists() for e in ("pdf", "png", "svg"))]
    print("Imported:", ", ".join(imported) or "nothing")
    if missing:
        print("Missing (fallback symbols will be used):", ", ".join(missing))


if __name__ == "__main__":
    main()
