import importlib
from functools import lru_cache
from pathlib import Path

import pytest

from shared.airport_tools import ToolContext


def _project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _candidate_paths(filename: str):
    root = _project_root()
    directories = [
        root / "data",
        root,
        root / "mcp_server",
        root / "web" / "server",
        root / "python",
        root / "app" / "FlyFunEuroAIP" / "App" / "Data",
    ]
    for directory in directories:
        path = directory / filename
        if path.exists():
            yield path
    # Fallback to a recursive search if none of the known locations exist
    for path in root.rglob(filename):
        if path.is_file():
            yield path


def _locate_data_file(filename: str) -> Path:
    for path in _candidate_paths(filename):
        return path
    raise FileNotFoundError(f"Could not locate {filename} in repository.")


@lru_cache(maxsize=1)
def _cached_tool_context() -> ToolContext:
    airports_db = _locate_data_file("airports.db")
    rules_json = _locate_data_file("rules.json")
    return ToolContext.create(db_path=str(airports_db), rules_path=str(rules_json))


@pytest.fixture(scope="session")
def tool_context() -> ToolContext:
    return _cached_tool_context()


@pytest.fixture(scope="session")
def data_files() -> dict[str, str]:
    return {
        "airports_db": str(_locate_data_file("airports.db")),
        "rules_json": str(_locate_data_file("rules.json")),
    }


@pytest.fixture(scope="session")
def server_module(tool_context: ToolContext):
    server_mod = importlib.import_module("mcp_server.main")
    server_mod._tool_context = tool_context
    return server_mod

