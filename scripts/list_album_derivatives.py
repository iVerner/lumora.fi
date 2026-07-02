#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_album(path: Path) -> dict:
    try:
        import tomllib
    except ModuleNotFoundError:
        return load_album_fallback(path)

    with path.open("rb") as handle:
        return tomllib.load(handle)


def load_album_fallback(path: Path) -> dict:
    album: dict = {"images": []}
    current_image: dict | None = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line == "[[images]]":
            current_image = {}
            album["images"].append(current_image)
            continue
        if "=" not in line:
            continue

        key, raw_value = [part.strip() for part in line.split("=", 1)]
        if raw_value in {"true", "false"}:
            value: str | bool = raw_value == "true"
        else:
            value = raw_value.strip('"')

        target = current_image if current_image is not None else album
        target[key] = value

    return album


def _seq_width(count: int) -> int:
    return max(3, len(str(count)))


def emit_asset(slug: str, album_dir: Path, file_name: str, seq_stem: str) -> None:
    source = album_dir / file_name
    if not source.is_file():
        raise SystemExit(f"Missing source image referenced by album metadata: {source}")
    print(f"{slug}\t{file_name}\t{seq_stem}")


def main() -> int:
    parser = argparse.ArgumentParser(description="List album images that need generated derivatives.")
    parser.add_argument("kind", choices=["cover", "featured", "home_hero"])
    parser.add_argument("--gallery", default="gallery", help="Gallery source directory")
    args = parser.parse_args()

    gallery_dir = ROOT / args.gallery
    if not gallery_dir.is_dir():
        raise SystemExit(f"Missing gallery source directory: {gallery_dir}")

    seen: set[tuple[str, str]] = set()
    for album_dir in sorted(path for path in gallery_dir.iterdir() if path.is_dir()):
        album_path = album_dir / "album.toml"
        if not album_path.is_file():
            raise SystemExit(f"Missing album sidecar: {album_path}")

        album = load_album(album_path)
        slug = album_dir.name
        images = album.get("images", [])
        width = _seq_width(len(images))

        if args.kind == "cover":
            cover_file = album.get("cover")
            if not isinstance(cover_file, str) or not cover_file:
                raise SystemExit(f"Missing cover in {album_path}")
            asset = (slug, cover_file)
            if asset in seen:
                continue
            cover_idx = next(
                (i for i, img in enumerate(images) if isinstance(img, dict) and img.get("file") == cover_file),
                None,
            )
            if cover_idx is None:
                raise SystemExit(f"Cover {cover_file} not found in [[images]] of {album_path}")
            seq_stem = f"{cover_idx + 1:0{width}d}"
            emit_asset(slug, album_dir, cover_file, seq_stem)
            seen.add(asset)
            continue

        image_flag = "featured" if args.kind == "featured" else "home_hero"
        for idx, image in enumerate(images):
            if not isinstance(image, dict) or image.get(image_flag) is not True:
                continue
            file_name = image.get("file")
            if not isinstance(file_name, str) or not file_name:
                raise SystemExit(f"Missing {image_flag} image file in {album_path}")
            asset = (slug, file_name)
            if asset in seen:
                continue
            seq_stem = f"{idx + 1:0{width}d}"
            emit_asset(slug, album_dir, file_name, seq_stem)
            seen.add(asset)

    return 0


if __name__ == "__main__":
    sys.exit(main())
