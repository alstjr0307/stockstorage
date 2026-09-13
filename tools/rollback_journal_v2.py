"""Restore only the journal entry point; no database or unrelated files touched."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true', help='Restore after checksum validation')
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
root = args.root.resolve()
backup = root / 'output/journal-v2-backup/20260913-002149'
manifest = json.loads((backup / 'manifest.json').read_text(encoding='utf-8'))
changes = []
digest = lambda data: hashlib.sha256(data).hexdigest()
for relative, checksums in manifest['files'].items():
    target = (root / relative).resolve()
    source = (backup / relative).resolve()
    if not target.is_relative_to(root) or not source.is_relative_to(backup.resolve()):
        raise SystemExit('Unsafe manifest path; nothing restored.')
    original = source.read_bytes()
    current = target.read_bytes()
    if digest(original) != checksums['beforeSha256']:
        raise SystemExit('Backup checksum mismatch; nothing restored.')
    if digest(current) == checksums['beforeSha256']:
        continue
    if digest(current) != checksums['afterSha256']:
        raise SystemExit('File changed after this task. Refusing to overwrite: ' + relative)
    changes.append((target, source, original, current))
for target, source, original, current in changes:
    print(('RESTORE ' if args.apply else 'CHECK OK ') + str(target))
    if args.apply:
        source.with_suffix(source.suffix + '.v2').write_bytes(current)
        target.write_bytes(original)
print('Restored.' if args.apply else 'Dry run only. Pass --apply to restore.')
print('New V2 modules remain unused. No stored trade data is changed.')
