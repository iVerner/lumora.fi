#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from list_album_derivatives import load_album


def main() -> int:
    album_dir = Path(sys.argv[1])
    album_path = album_dir / "album.toml"
    if not album_path.is_file():
        print(f"Missing album sidecar: {album_path}", file=sys.stderr)
        return 1

    album = load_album(album_path)

    images = album.get("images", [])
    if not images:
        return 0

    width = max(3, len(str(len(images))))
    for idx, image in enumerate(images):
        source_file = image.get("file", "")
        if not source_file:
            continue
        seq = f"{idx + 1:0{width}d}"
        print(f"{source_file}\t{seq}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
