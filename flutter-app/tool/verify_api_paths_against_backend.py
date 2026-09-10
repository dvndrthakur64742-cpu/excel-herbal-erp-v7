from pathlib import Path
import re

FLUTTER_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = FLUTTER_ROOT.parent
API_PATHS = FLUTTER_ROOT / 'lib/core/api_paths.dart'
ROUTE_REGISTRY = REPO_ROOT / 'src/Http/RouteRegistry.php'


def quoted_routes(text: str) -> set[str]:
    return set(re.findall(r"['\"](/[^'\"]+)['\"]", text))


def normalize_flutter(path: str) -> str:
    return re.sub(r'\$[A-Za-z_]\w*', '{#}', path)


def normalize_backend(path: str) -> str:
    return re.sub(r'\(\?P<[^>]+>\\\\?d\+\)', '{#}', path)


def main() -> None:
    flutter_routes = quoted_routes(API_PATHS.read_text(encoding='utf-8'))
    backend_routes = quoted_routes(ROUTE_REGISTRY.read_text(encoding='utf-8'))
    normalized_backend = {normalize_backend(route) for route in backend_routes}

    missing = sorted(
        route
        for route in flutter_routes
        if normalize_flutter(route) not in normalized_backend
    )
    if missing:
        rendered = '\n'.join(f'  - {route}' for route in missing)
        raise SystemExit(
            'Flutter API paths missing from v7 backend RouteRegistry:\n' + rendered
        )

    print(
        'Flutter/backend API path contract: PASS '
        f'({len(flutter_routes)} Flutter paths checked against '
        f'{len(backend_routes)} backend route patterns)'
    )


if __name__ == '__main__':
    main()
