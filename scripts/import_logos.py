#!/usr/bin/env python3
"""Imports logo overrides from design/logos/ into the asset catalog.

You don't need this for most apps: Notchman finds logos automatically
(site icons for web content, App Store icons for apps). Use it only when you
want a specific image for a source. Name the file after the source as shown in
Notchman, e.g. "ChatGPT.png", "WhatsApp.pdf", "nytimes.com.png"; letters and
digits are kept, so it becomes the asset logo-chatgpt, logo-whatsapp, logo-nytimescom.

Usage: python3 scripts/import_logos.py
"""
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "design/logos"
CATALOG = ROOT / "Notchman/Resources/Assets.xcassets"


def slug(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def main():
    imported = []
    for src in sorted(SOURCE.glob("*")):
        if src.suffix.lower() not in (".png", ".pdf", ".svg", ".jpg", ".jpeg"):
            continue
        folder = CATALOG / f"logo-{slug(src.stem)}.imageset"
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        shutil.copy(src, folder / src.name)
        contents = {"images": [{"filename": src.name, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
        if src.suffix.lower() in (".pdf", ".svg"):
            contents["properties"] = {"preserves-vector-representation": True}
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2))
        imported.append(f"{src.name} -> logo-{slug(src.stem)}")
    print("\n".join(imported) or "No logo files in design/logos.")


if __name__ == "__main__":
    main()
