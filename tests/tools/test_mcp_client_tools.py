import pytest

from web.server.mcp_client import MCPClient


@pytest.fixture(scope="session")
def real_mcp_client(tool_context):
    client = MCPClient()
    client._tool_context = tool_context
    return client


def test_search_airports_integration(real_mcp_client):
    result = real_mcp_client._call_tool(
        "search_airports",
        {"query": "LFPG", "max_results": 5},
    )

    assert result["count"] >= 1
    assert any(airport["ident"] == "LFPG" for airport in result["airports"])


def test_find_airports_near_route_integration(real_mcp_client):
    result = real_mcp_client._call_tool(
        "find_airports_near_route",
        {"from_icao": "EGLL", "to_icao": "LFPG", "max_distance_nm": 40},
    )

    assert result["count"] >= 1
    assert result["airports"]

def test_find_airports_near_route_with_filters_integration(real_mcp_client):
    result = real_mcp_client._call_tool(
        "find_airports_near_route",
        {"from_icao": "EGTF", "to_icao": "LFMD", "max_distance_nm": 40, 
        "filters": {"trip_distance": {"from": "EGTF", "min": 350, "max": 450}}},
    )
    assert result["count"] >= 1
    assert result["airports"]
