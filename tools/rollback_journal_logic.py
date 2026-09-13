"""Restore this transaction/ledger fix as a unit. Never connects to Firebase."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true')
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
args = parser.parse_args()
root = args.root.resolve()
backup = root / 'output/journal-logic-backup/20260913-010900'
before = json.loads((backup / 'before.json').read_text(encoding='utf-8'))
after = json.loads((backup / 'after.json').read_text(encoding='utf-8'))
digest = lambda data: hashlib.sha256(data).hexdigest()
pending = []
for relative, checksum in before.items():
    target, source = (root / relative).resolve(), (backup / relative).resolve()
    if not target.is_relative_to(root) or not source.is_relative_to(backup.resolve()):
        raise SystemExit('Unsafe backup path.')
    original, current = source.read_bytes(), target.read_bytes()
    if digest(original) != checksum:
        raise SystemExit('Backup checksum mismatch: ' + relative)
    if digest(current) == checksum:
        continue
    if digest(current) != after[relative]:
        raise SystemExit('Later changes detected; nothing restored: ' + relative)
    pending.append((target, source, original, current))
for target, source, original, current in pending:
    print(('RESTORE ' if args.apply else 'CHECK OK ') + str(target))
    if args.apply:
        source.with_suffix(source.suffix + '.fixed').write_bytes(current)
        target.write_bytes(original)
print('Restored. Run flutter pub get and rebuild.' if args.apply else 'Dry run only; use --apply to restore.')
print('This does not deploy security rules or change stored journal data.')
