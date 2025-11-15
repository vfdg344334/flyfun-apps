#!/usr/bin/env python3
"""
Internal MCP Client for Chatbot Service
Calls the MCP server's tools and returns results for the LLM.

See `shared/README.md` for more information on the shared tooling and how to add/update tools.
"""

import httpx
import logging
import os
import requests
from typing import Dict, Any, List, Optional
from bs4 import BeautifulSoup
import re

from shared.airport_tools import (
    ToolContext,
    ToolSpec,
    get_shared_tool_specs,
)

logger = logging.getLogger(__name__)


class MCPClient:
    """Client for calling MCP server tools internally."""

    def __init__(self, mcp_base_url: str = "http://localhost:8002"):
        self.mcp_base_url = mcp_base_url
        self.client = httpx.Client(timeout=30.0)
        self._tool_context: Optional[ToolContext] = None
        self._tool_specs: Dict[str, ToolSpec] = get_shared_tool_specs()

    def _ensure_context(self) -> ToolContext:
        if self._tool_context is None:
            db_path = os.getenv("AIRPORTS_DB", "airports.db")
            rules_path = os.getenv("RULES_JSON", "rules.json")
            self._tool_context = ToolContext.create(db_path=db_path, rules_path=rules_path)
            logger.info(
                "Tool context initialized: %d airports loaded, %d rules available",
                len(self._tool_context.model.airports),
                len(self._tool_context.rules_manager.rules if self._tool_context.rules_manager else []),
            )
        return self._tool_context

    def _call_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """
        Call an MCP tool via internal HTTP request.
        For now, we'll use the euro_aip model directly instead of HTTP.
        """
        import time

        try:
            self._ensure_context()
            exec_start = time.time()
            logger.info(f"⏱️ MCP: Executing {tool_name}...")

            spec = self._tool_specs.get(tool_name)

            if spec:
                ctx = self._ensure_context()
                result = spec["handler"](ctx, **arguments)
            elif tool_name == "web_search":
                result = self._web_search(**arguments)
            else:
                result = {"error": f"Unknown tool: {tool_name}"}

            exec_end = time.time()
            logger.info(f"⏱️ MCP: {tool_name} execution took {exec_end - exec_start:.2f}s")
            return result

        except Exception as e:
            logger.error(f"Error calling tool {tool_name}: {e}", exc_info=True)
            return {"error": str(e)}

    def _web_search(self, query: str, max_results: int = 5) -> Dict[str, Any]:
        """
        Perform actual web search using DuckDuckGo HTML scraping.
        Returns real search results from the web.
        """
        try:
            # Use DuckDuckGo HTML search
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            }

            search_url = f"https://html.duckduckgo.com/html/?q={requests.utils.quote(query)}"
            response = requests.get(search_url, headers=headers, timeout=15)
            response.raise_for_status()

            # Parse HTML results
            soup = BeautifulSoup(response.text, 'html.parser')
            results = []

            # Find search result divs
            result_divs = soup.find_all('div', class_='result')

            for div in result_divs[:max_results]:
                try:
                    # Extract title and URL
                    title_link = div.find('a', class_='result__a')
                    if not title_link:
                        continue

                    title = title_link.get_text(strip=True)
                    url = title_link.get('href', '')

                    # Extract snippet
                    snippet_div = div.find('a', class_='result__snippet')
                    snippet = snippet_div.get_text(strip=True) if snippet_div else ""

                    # Clean up snippet
                    snippet = re.sub(r'\s+', ' ', snippet).strip()

                    if title and url:
                        results.append({
                            "title": title[:200],  # Limit title length
                            "snippet": snippet[:500] if snippet else "No description available",  # Limit snippet
                            "url": url,
                            "source": "Web Search"
                        })
                except Exception as e:
                    logger.debug(f"Error parsing search result: {e}")
                    continue

            # If no results, provide helpful message
            if not results:
                results.append({
                    "title": "No Results Found",
                    "snippet": f"No web results found for '{query}'. Please try: 1) Checking the airport operator's official website, 2) Reviewing AIP supplements, 3) Contacting handling agents directly, 4) Using official aviation databases like EUROCONTROL.",
                    "url": f"https://duckduckgo.com/?q={requests.utils.quote(query)}",
                    "source": "Search Guidance"
                })

            return {
                "query": query,
                "count": len(results),
                "results": results,
                "message": "⚠️ IMPORTANT: Always verify web search results with official aviation sources before making operational decisions."
            }

        except Exception as e:
            logger.error(f"Error in web search: {e}", exc_info=True)
            return {
                "query": query,
                "error": str(e),
                "message": "Web search unavailable. Please check official aviation sources directly.",
                "results": [{
                    "title": "Web Search Error",
                    "snippet": f"Could not perform web search: {str(e)}. For aviation information, check official sources like AIP, airport operator websites, or EUROCONTROL.",
                    "url": "https://www.eurocontrol.int/",
                    "source": "Error Message"
                }]
            }

    def get_available_tools(self) -> List[Dict[str, Any]]:
        """
        Return tool definitions in OpenAI function calling format.
        These will be provided to the LLM so it knows what tools it can call.
        """

        tools: List[Dict[str, Any]] = []
        for spec in self._tool_specs.values():
            if not spec.get("expose_to_llm", True):
                continue
            tools.append(
                {
                    "type": "function",
                    "function": {
                        "name": spec["name"],
                        "description": spec["description"],
                        "parameters": spec["parameters"],
                    },
                }
            )

        tools.append(
            {
                "type": "function",
                "function": {
                    "name": "web_search",
                    "description": "Search the web for aviation information not captured in the internal database (fees, NOTAMs, weather, current restrictions). Always remind pilots to verify results with official sources.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "Search text such as 'LFPG landing fees 2024'.",
                            },
                            "max_results": {
                                "type": "integer",
                                "description": "Maximum number of results to return.",
                                "default": 5,
                            },
                        },
                        "required": ["query"],
                    },
                },
            }
        )

        return tools
