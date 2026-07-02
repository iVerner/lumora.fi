#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

from list_album_derivatives import load_album


ROOT = Path(__file__).resolve().parents[1]


def parse_size(value: str) -> tuple[int, int]:
    width, height = value.lower().split("x", 1)
    return int(width), int(height)


def jpeg_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        if handle.read(2) != b"\xff\xd8":
            raise ValueError(f"Not a JPEG file: {path}")

        while True:
            marker_start = handle.read(1)
            if not marker_start:
                break
            if marker_start != b"\xff":
                continue

            marker = handle.read(1)
            while marker == b"\xff":
                marker = handle.read(1)
            if marker in {b"\xd8", b"\xd9"}:
                continue

            length_bytes = handle.read(2)
            if len(length_bytes) != 2:
                break
            segment_length = struct.unpack(">H", length_bytes)[0]
            if segment_length < 2:
                break

            marker_value = marker[0]
            if marker_value in {
                0xC0,
                0xC1,
                0xC2,
                0xC3,
                0xC5,
                0xC6,
                0xC7,
                0xC9,
                0xCA,
                0xCB,
                0xCD,
                0xCE,
                0xCF,
            }:
                data = handle.read(5)
                if len(data) != 5:
                    break
                height, width = struct.unpack(">HH", data[1:5])
                return width, height

            handle.seek(segment_length - 2, 1)

    raise ValueError(f"Could not read JPEG dimensions: {path}")


def fit_dimensions(width: int, height: int, max_width: int, max_height: int) -> dict[str, int]:
    scale = min(max_width / width, max_height / height, 1)
    return {
        "width": max(1, round(width * scale)),
        "height": max(1, round(height * scale)),
    }


def _seq_width(images: list) -> int:
    return max(3, len(str(len(images))))


def _cover_seq(album: dict, width: int) -> str | None:
    cover_file = album.get("cover")
    if not isinstance(cover_file, str):
        return None
    for idx, image in enumerate(album.get("images", [])):
        if isinstance(image, dict) and image.get("file") == cover_file:
            return f"{idx + 1:0{width}d}"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Write generated album image dimensions for Zola templates.")
    parser.add_argument("--gallery", default="gallery", help="Gallery source directory")
    parser.add_argument("--output", default="static/gallery", help="Generated gallery output directory")
    parser.add_argument("--full-size", default="2000x2000", help="Full image bounding box")
    parser.add_argument("--preview-size", default="1200x1200", help="Preview image bounding box")
    args = parser.parse_args()

    gallery_dir = ROOT / args.gallery
    output_dir = ROOT / args.output
    full_max = parse_size(args.full_size)
    preview_max = parse_size(args.preview_size)

    for album_dir in sorted(path for path in gallery_dir.iterdir() if path.is_dir()):
        album_path = album_dir / "album.toml"
        if not album_path.is_file():
            raise SystemExit(f"Missing album sidecar: {album_path}")

        album = load_album(album_path)
        raw_images = album.get("images", [])
        width = _seq_width(raw_images)
        images = []
        for idx, image in enumerate(raw_images):
            if not isinstance(image, dict):
                continue
            file_name = image.get("file")
            if not isinstance(file_name, str) or not file_name:
                raise SystemExit(f"Missing image file in {album_path}")

            source = album_dir / file_name
            w, h = jpeg_dimensions(source)
            seq = f"{idx + 1:0{width}d}"
            images.append(
                {
                    "seq": seq,
                    "full": fit_dimensions(w, h, *full_max),
                    "preview": fit_dimensions(w, h, *preview_max),
                }
            )

        album_output_dir = output_dir / album_dir.name
        album_output_dir.mkdir(parents=True, exist_ok=True)

        payload: dict = {"images": images}
        cover_seq = _cover_seq(album, width)
        if cover_seq:
            payload["cover_seq"] = cover_seq

        (album_output_dir / "dimensions.json").write_text(
            json.dumps(payload, indent=2) + "\n",
            encoding="utf-8",
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
