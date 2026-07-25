"""Dynamic view discovery. A capture set = all images in a directory (N >= 1),
sorted for determinism. No hardcoded filenames, no fixed view count."""
from pathlib import Path

EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".heic"}


def discover_views(path) -> list[Path]:
    p = Path(path)
    if p.is_file():
        return [p]
    return sorted(f for f in p.iterdir() if f.is_file() and f.suffix.lower() in EXTS)
