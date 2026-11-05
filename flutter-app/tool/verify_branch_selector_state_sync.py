from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BRANCH_SELECTOR = ROOT / 'lib/widgets/branch_selector.dart'


def main() -> None:
    text = BRANCH_SELECTOR.read_text(encoding='utf-8')
    required = [
        "key: ValueKey('${allowAllAuthorised}_${app.currentBranchId}'),",
        'initialValue: selected,',
        "child: Text('All Authorised Branches')",
        'selectAllAuthorisedBranches()',
    ]
    missing = [item for item in required if item not in text]
    if missing:
        rendered = '\n'.join(f'  - {item}' for item in missing)
        raise SystemExit(
            'Branch selector state-sync invariant missing:\n' + rendered
        )
    print('Branch selector state-sync invariant: PASS')


if __name__ == '__main__':
    main()
