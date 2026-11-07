"""Advance patch version only when shipping inputs change; commit after successful build."""
import hashlib, json, pathlib, sys
root = pathlib.Path('.')
state_file = root / 'version.json'
state = json.loads(state_file.read_text()) if state_file.exists() else {'version': '1.0.0', 'build': 0, 'fingerprint': ''}
h = hashlib.sha256()
files = [root / 'Package.swift']
for folder in ['Sources', 'Assets', 'scripts']:
    files += sorted(p for p in (root / folder).rglob('*') if p.is_file())
for p in files:
    h.update(str(p).encode()); h.update(p.read_bytes())
fingerprint = h.hexdigest()
if fingerprint != state['fingerprint']:
    major, minor, patch = map(int, state['version'].split('.'))
    state = {'version': f'{major}.{minor}.{patch+1}', 'build': state['build']+1, 'fingerprint': fingerprint}
if '--commit' in sys.argv:
    state_file.write_text(json.dumps(state, indent=2)+'\n')
else:
    import plistlib
    path = root / 'dist/Sticky Notes.app/Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    info['CFBundleShortVersionString'] = state['version']
    info['CFBundleVersion'] = str(state['build'])
    path.write_bytes(plistlib.dumps(info))
print(state['version'])
