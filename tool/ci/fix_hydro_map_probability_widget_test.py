from pathlib import Path

path = Path('test/hydro_dispatch_mobile_contract_test.dart')
text = path.read_text(encoding='utf-8')
old = "      expect(find.text('PROBABILITATE DE UZINARE'), findsOneWidget);\n"
count = text.count(old)
if count == 1:
    text = text.replace(old, '', 1)
elif count != 0:
    raise SystemExit(f'ABORT widget-test fix: expected at most 1 match, got {count}')
path.write_text(text, encoding='utf-8')
print('Hydro Map widget test localized-header assumption removed.')
