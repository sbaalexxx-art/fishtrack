from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
lib = root / 'lib'
errors = []

for path in lib.rglob('*.dart'):
    text = path.read_text(encoding='utf-8', errors='replace')
    if re.search(r'^part of\s+', text, re.M):
        errors.append(f'orphan/active part file not allowed: {path.relative_to(root)}')
    if 'Icons.rainy_rounded' in text:
        errors.append(f'unsupported icon getter: {path.relative_to(root)}')

expected = [
    lib / 'features/figma_complete/presentation/figma_environment_pages.dart',
    lib / 'features/figma_complete/presentation/figma_foundation.dart',
    lib / 'features/commercial_home/presentation/commercial_home_page.dart',
]
for path in expected:
    if not path.exists():
        errors.append(f'missing required Figma file: {path.relative_to(root)}')

if errors:
    print('\n'.join(errors))
    sys.exit(1)
print('RC4.1 static preflight PASS')
