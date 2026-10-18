"""Compress color WebP sources and 2D imports without changing asset geometry.

Dry run by default. --apply requires an external backup directory.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--backup', type=Path)
    parser.add_argument('--quality', type=int, default=80)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if not 1 <= args.quality <= 100:
        parser.error('quality must be 1..100')
    if args.apply and (not args.backup or args.backup.resolve().is_relative_to(root)):
        parser.error('--apply requires --backup outside the project')
    report = {'quality': args.quality, 'sources': [], 'imports': []}

    def backup(path):
        target = args.backup / path.relative_to(root)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            raise FileExistsError(f'Backup already exists: {target}')
        shutil.copy2(path, target)

    def excluded(path):
        parts = path.relative_to(root).parts
        return any(part in parts for part in ('models', 'characters2.5D', 'icons', 'logos'))

    for path in sorted((root / 'assets').rglob('*.webp')):
        if excluded(path):
            continue
        original = path.read_bytes()
        with Image.open(io.BytesIO(original)) as image:
            if image.is_animated:
                continue
            alpha = image.getchannel('A').tobytes() if image.mode == 'RGBA' else None
            buffer = io.BytesIO()
            image.save(buffer, format='WEBP', quality=args.quality, method=4, exact=True)
            encoded = buffer.getvalue()
            if len(encoded) >= len(original) * 0.95:
                continue
            with Image.open(io.BytesIO(encoded)) as check:
                assert check.size == image.size and check.mode == image.mode
                if alpha is not None:
                    assert check.getchannel('A').tobytes() == alpha
            report['sources'].append({
                'path': path.relative_to(root).as_posix(),
                'before': len(original), 'after': len(encoded),
                'original_sha256': hashlib.sha256(original).hexdigest(),
                'size': list(image.size), 'alpha_preserved': alpha is not None,
            })
        if args.apply:
            backup(path)
            temporary = path.with_suffix('.webp.part')
            temporary.write_bytes(encoded)
            temporary.replace(path)

    for path in sorted((root / 'assets').rglob('*.import')):
        if excluded(path):
            continue
        original = path.read_text(encoding='utf-8')
        if 'importer="texture"' not in original or 'compress/mode=0' not in original:
            continue
        updated = original.replace('compress/mode=0', 'compress/mode=1')
        updated = re.sub(r'compress/lossy_quality=[^\r\n]+',
                         f'compress/lossy_quality={args.quality / 100}', updated)
        report['imports'].append(path.relative_to(root).as_posix())
        if args.apply:
            backup(path)
            path.write_text(updated, encoding='utf-8')

    before = sum(row['before'] for row in report['sources'])
    after = sum(row['after'] for row in report['sources'])
    print(f'Color sources: {len(report["sources"])}; {before:,} -> {after:,} bytes')
    print(f'2D imports: {len(report["imports"])}; geometry and alpha preserved')
    if args.apply:
        args.backup.mkdir(parents=True, exist_ok=True)
        (args.backup / 'compression-report.json').write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'Originals and report: {args.backup}')


if __name__ == '__main__':
    main()
