from pathlib import Path
import re

FLUTTER_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = FLUTTER_ROOT.parent
API_PATHS = FLUTTER_ROOT / 'lib/core/api_paths.dart'
ROUTE_REGISTRY = REPO_ROOT / 'src/Http/RouteRegistry.php'
ROUTE_CONTRACT = FLUTTER_ROOT / 'tool/v7_backend_route_contract.txt'


def quoted_routes(text: str) -> set[str]:
    return set(re.findall(r"['\"](/[^'\"]+)['\"]", text))


def snapshot_routes(text: str) -> set[str]:
    return {
        line.strip()
        for line in text.splitlines()
        if line.strip().startswith('/')
    }


def normalize_flutter(path: str) -> str:
    return re.sub(r'\$[A-Za-z_]\w*', '{#}', path)


def normalize_backend(path: str) -> str:
    return re.sub(r'\(\?P<[^>]+>\\\\?d\+\)', '{#}', path)


def load_backend_routes() -> tuple[set[str], str]:
    if ROUTE_REGISTRY.exists():
        return quoted_routes(ROUTE_REGISTRY.read_text(encoding='utf-8')), str(ROUTE_REGISTRY)

    if not ROUTE_CONTRACT.exists():
        raise SystemExit(
            'Neither backend RouteRegistry nor frozen v7 backend route contract is available.'
        )

    routes = snapshot_routes(ROUTE_CONTRACT.read_text(encoding='utf-8'))
    if len(routes) != 160:
        raise SystemExit(
            f'Frozen v7 backend route contract is incomplete: expected 160 routes, found {len(routes)}.'
        )
    return routes, str(ROUTE_CONTRACT)


def main() -> None:
    flutter_routes = quoted_routes(API_PATHS.read_text(encoding='utf-8'))
    backend_routes, backend_source = load_backend_routes()
    normalized_backend = {normalize_backend(route) for route in backend_routes}

    missing = sorted(
        route
        for route in flutter_routes
        if normalize_flutter(route) not in normalized_backend
    )
    if missing:
        rendered = '\n'.join(f'  - {route}' for route in missing)
        raise SystemExit(
            'Flutter API paths missing from v7 backend RouteRegistry contract:\n' + rendered
        )

    print(
        'Flutter/backend API path contract: PASS '
        f'({len(flutter_routes)} Flutter paths checked against '
        f'{len(backend_routes)} backend route patterns; source={backend_source})'
    )


if __name__ == '__main__':
    main()
