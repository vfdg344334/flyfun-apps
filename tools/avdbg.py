#!/usr/bin/env python3

"""
Aviation Agent Debug CLI - debug prompts sent to the aviation agent.

Usage:
  python tools/avdbg.py "prompt" [options]

Mode selection:
  --offline              Run directly via Python (default, best for debugging)
  --api [URL]            Call REST API (default: http://localhost:3000)

Output selection (combinable):
  -v, --verbose          Show all debug information
  --plan                 Show plan (selected tool + arguments)
  --tool-result          Show tool execution result
  --ui                   Show ui_payload
  --tokens               Show token usage
  --thinking             Show planning/formatting reasoning

Output format:
  --json                 Output as JSON
  --no-answer            Skip showing the answer

Agent options:
  --persona ID           Persona ID for prioritization (default: ifr_touring_sr22)
  --database PATH        Path to airports.db
  --rules PATH           Path to rules.json

Examples:
  python tools/avdbg.py "Find airports near Paris"
  python tools/avdbg.py "Find airports near Paris" -v
  python tools/avdbg.py "Find airports near Paris" --plan --tool-result
  python tools/avdbg.py "Find airports near Paris" --json
  python tools/avdbg.py "Find airports near Paris" --api
  python tools/avdbg.py "Find airports near Paris" --api http://localhost:8000
"""

import argparse
import asyncio
import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

# Add project root to path for shared module imports
sys.path.insert(0, str(Path(__file__).parent.parent))

# Configure logging - default to WARNING to reduce noise
logging.basicConfig(
    level=logging.WARNING,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# ANSI styling helpers (pattern from tools/aip.py)
# ---------------------------------------------------------------------------
RESET = '\033[0m'
BOLD = '\033[1m'
CYAN = '\033[36m'
YELLOW = '\033[33m'
GREEN = '\033[32m'
RED = '\033[31m'
DIM = '\033[2m'

ENABLE_COLOR = sys.stdout.isatty()


def fmt(text: str, *styles: str) -> str:
    """Apply ANSI styles to text if color is enabled."""
    if not ENABLE_COLOR or not styles:
        return text
    return "".join(styles) + text + RESET


# ---------------------------------------------------------------------------
# Path resolution helpers (pattern from tools/aip.py)
# ---------------------------------------------------------------------------
def _resolve_database_path(path: Optional[str]) -> Path:
    """Resolve database path: explicit > AIRPORTS_DB env > airports.db"""
    if path:
        return Path(path)
    env_path = os.environ.get("AIRPORTS_DB")
    if env_path:
        return Path(env_path)
    return Path("airports.db")


def _resolve_rules_path(path: Optional[str]) -> Path:
    """Resolve rules path: explicit > RULES_JSON env > rules.json"""
    if path:
        return Path(path)
    env_path = os.environ.get("RULES_JSON")
    if env_path:
        return Path(env_path)
    return Path("rules.json")


# ---------------------------------------------------------------------------
# Data collection structure
# ---------------------------------------------------------------------------
@dataclass
class AgentDebugResult:
    """Collected debug information from agent execution."""
    answer: str = ""
    plan: Optional[Dict[str, Any]] = None
    tool_calls: List[Dict[str, Any]] = field(default_factory=list)
    ui_payload: Optional[Dict[str, Any]] = None
    thinking: Optional[str] = None
    tokens: Optional[Dict[str, Any]] = None
    error: Optional[str] = None

    # Metadata
    session_id: Optional[str] = None
    thread_id: Optional[str] = None
    run_id: Optional[str] = None


# ---------------------------------------------------------------------------
# Offline runner (direct Python invocation)
# ---------------------------------------------------------------------------
async def run_offline(prompt: str, args: argparse.Namespace) -> AgentDebugResult:
    """Run agent directly via Python."""
    # Lazy imports to avoid loading heavy dependencies when using --api mode
    from langchain_core.messages import HumanMessage
    from shared.aviation_agent.adapters import build_agent, stream_aviation_agent
    from shared.aviation_agent.config import AviationAgentSettings

    settings = AviationAgentSettings(
        enabled=True,
        airports_db=_resolve_database_path(args.database),
        rules_json=_resolve_rules_path(args.rules),
    )

    graph = build_agent(settings=settings)
    messages = [HumanMessage(content=prompt)]

    result = AgentDebugResult()

    async for event in stream_aviation_agent(messages, graph, persona_id=args.persona):
        event_type = event.get("event")
        data = event.get("data", {})

        if event_type == "plan":
            result.plan = data
        elif event_type == "thinking":
            content = data.get("content", "")
            result.thinking = (result.thinking or "") + content
        elif event_type == "tool_call_start":
            result.tool_calls.append({
                "name": data.get("name"),
                "arguments": data.get("arguments", {}),
            })
        elif event_type == "tool_call_end":
            # Update last tool call with result
            if result.tool_calls:
                result.tool_calls[-1]["result"] = data.get("result")
        elif event_type == "message":
            result.answer += data.get("content", "")
        elif event_type == "ui_payload":
            result.ui_payload = data
        elif event_type == "done":
            result.tokens = data.get("tokens")
            result.session_id = data.get("session_id")
            result.thread_id = data.get("thread_id")
            result.run_id = data.get("run_id")
        elif event_type == "error":
            result.error = data.get("message")

    return result


# ---------------------------------------------------------------------------
# Online runner (REST API)
# ---------------------------------------------------------------------------
async def run_online(prompt: str, args: argparse.Namespace, api_url: str) -> AgentDebugResult:
    """Run agent via REST API."""
    try:
        import httpx
    except ImportError:
        print(fmt("Error: httpx is required for --api mode. Install with: pip install httpx", BOLD, RED))
        sys.exit(1)

    endpoint = f"{api_url.rstrip('/')}/api/aviation-agent/chat/stream"
    payload = {
        "messages": [{"role": "user", "content": prompt}],
        "persona_id": args.persona,
    }

    result = AgentDebugResult()
    event_type: Optional[str] = None

    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            async with client.stream("POST", endpoint, json=payload) as response:
                if response.status_code != 200:
                    result.error = f"HTTP {response.status_code}: {await response.aread()}"
                    return result

                async for line in response.aiter_lines():
                    if not line:
                        continue

                    if line.startswith("event:"):
                        event_type = line.split(":", 1)[1].strip()
                    elif line.startswith("data:") and event_type:
                        try:
                            data = json.loads(line.split(":", 1)[1].strip())
                        except json.JSONDecodeError:
                            continue

                        if event_type == "plan":
                            result.plan = data
                        elif event_type == "thinking":
                            content = data.get("content", "")
                            result.thinking = (result.thinking or "") + content
                        elif event_type == "tool_call_start":
                            result.tool_calls.append({
                                "name": data.get("name"),
                                "arguments": data.get("arguments", {}),
                            })
                        elif event_type == "tool_call_end":
                            if result.tool_calls:
                                result.tool_calls[-1]["result"] = data.get("result")
                        elif event_type == "message":
                            result.answer += data.get("content", "")
                        elif event_type == "ui_payload":
                            result.ui_payload = data
                        elif event_type == "done":
                            result.tokens = data.get("tokens")
                            result.session_id = data.get("session_id")
                            result.thread_id = data.get("thread_id")
                            result.run_id = data.get("run_id")
                        elif event_type == "error":
                            result.error = data.get("message")

    except httpx.ConnectError:
        result.error = f"Could not connect to {api_url}. Is the server running?"
    except Exception as e:
        result.error = str(e)

    return result


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------
def print_rich_output(result: AgentDebugResult, args: argparse.Namespace) -> None:
    """Print formatted terminal output with colors."""

    if args.plan or args.verbose:
        print(fmt("\n=== PLAN ===", BOLD, CYAN))
        if result.plan:
            print(f"Tool: {fmt(result.plan.get('selected_tool', '?'), BOLD, YELLOW)}")
            args_str = json.dumps(result.plan.get('arguments', {}), indent=2, ensure_ascii=False)
            print(f"Arguments:\n{args_str}")
            if result.plan.get('answer_style'):
                print(f"Answer style: {result.plan.get('answer_style')}")
        else:
            print(fmt("(no plan)", DIM))

    if args.thinking or args.verbose:
        print(fmt("\n=== THINKING ===", BOLD, CYAN))
        print(result.thinking or fmt("(none)", DIM))

    if args.tool_result or args.verbose:
        print(fmt("\n=== TOOL CALLS ===", BOLD, CYAN))
        if result.tool_calls:
            for tc in result.tool_calls:
                print(f"\n{fmt(tc.get('name', '?'), BOLD, YELLOW)}:")
                args_str = json.dumps(tc.get('arguments', {}), indent=2, ensure_ascii=False)
                print(f"  Arguments:\n{_indent(args_str, 4)}")
                if tc.get("result") is not None:
                    result_str = json.dumps(tc["result"], indent=2, ensure_ascii=False)
                    # Truncate large results
                    if len(result_str) > 3000:
                        result_str = result_str[:3000] + "\n... (truncated)"
                    print(f"  Result:\n{_indent(result_str, 4)}")
        else:
            print(fmt("(no tool calls)", DIM))

    if args.ui or args.verbose:
        print(fmt("\n=== UI PAYLOAD ===", BOLD, CYAN))
        if result.ui_payload:
            print(json.dumps(result.ui_payload, indent=2, ensure_ascii=False))
        else:
            print(fmt("(none)", DIM))

    if not args.no_answer:
        print(fmt("\n=== ANSWER ===", BOLD, GREEN))
        print(result.answer or fmt("(no answer)", DIM))

    if args.tokens or args.verbose:
        print(fmt("\n=== TOKENS ===", BOLD, CYAN))
        if result.tokens:
            print(f"Input:  {result.tokens.get('input', '?')}")
            print(f"Output: {result.tokens.get('output', '?')}")
            print(f"Total:  {result.tokens.get('total', '?')}")
        else:
            print(fmt("(no token data)", DIM))

    if result.error:
        print(fmt(f"\n=== ERROR ===", BOLD, RED))
        print(fmt(result.error, RED))


def print_json_output(result: AgentDebugResult, args: argparse.Namespace) -> None:
    """Print raw JSON output."""
    # Determine what to include based on flags
    has_specific_flags = any([args.plan, args.thinking, args.tool_result, args.ui, args.tokens])

    if args.verbose or not has_specific_flags:
        # Output everything
        output = asdict(result)
    else:
        # Output only requested fields
        output = {}
        if args.plan:
            output["plan"] = result.plan
        if args.thinking:
            output["thinking"] = result.thinking
        if args.tool_result:
            output["tool_calls"] = result.tool_calls
        if args.ui:
            output["ui_payload"] = result.ui_payload
        if args.tokens:
            output["tokens"] = result.tokens

    # Always include answer unless --no-answer
    if not args.no_answer:
        output["answer"] = result.answer

    # Always include error if present
    if result.error:
        output["error"] = result.error

    print(json.dumps(output, indent=2, ensure_ascii=False))


def _indent(text: str, spaces: int) -> str:
    """Indent each line of text by the given number of spaces."""
    prefix = " " * spaces
    return "\n".join(prefix + line for line in text.split("\n"))


# ---------------------------------------------------------------------------
# Argument parser
# ---------------------------------------------------------------------------
def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Debug aviation agent prompts",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s "Find airports near Paris"
  %(prog)s "Find airports near Paris" -v
  %(prog)s "Find airports near Paris" --plan --tool-result
  %(prog)s "Find airports near Paris" --json
  %(prog)s "Find airports near Paris" --api
  %(prog)s "Find airports near Paris" --api http://localhost:8000
""",
    )

    # Positional argument
    parser.add_argument("prompt", help="The prompt to send to the agent")

    # Mode selection
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--offline", action="store_true",
        help="Run directly via Python (default)"
    )
    mode_group.add_argument(
        "--api", nargs="?", const="http://localhost:3000", metavar="URL",
        help="Call REST API (default: http://localhost:3000)"
    )

    # Output selection
    output_group = parser.add_argument_group("Output selection")
    output_group.add_argument(
        "-v", "--verbose", action="store_true",
        help="Show all debug information"
    )
    output_group.add_argument(
        "--plan", action="store_true",
        help="Show plan (selected tool + arguments)"
    )
    output_group.add_argument(
        "--tool-result", action="store_true",
        help="Show tool execution result"
    )
    output_group.add_argument(
        "--ui", action="store_true",
        help="Show ui_payload"
    )
    output_group.add_argument(
        "--tokens", action="store_true",
        help="Show token usage"
    )
    output_group.add_argument(
        "--thinking", action="store_true",
        help="Show planning/formatting reasoning"
    )

    # Output format
    format_group = parser.add_argument_group("Output format")
    format_group.add_argument(
        "--json", action="store_true",
        help="Output as JSON"
    )
    format_group.add_argument(
        "--no-answer", action="store_true",
        help="Skip showing the answer"
    )

    # Agent options
    agent_group = parser.add_argument_group("Agent options")
    agent_group.add_argument(
        "--persona", default="ifr_touring_sr22",
        help="Persona ID for prioritization (default: ifr_touring_sr22)"
    )
    agent_group.add_argument(
        "--database", type=str, default=None,
        help="Path to airports.db (default: AIRPORTS_DB env or airports.db)"
    )
    agent_group.add_argument(
        "--rules", type=str, default=None,
        help="Path to rules.json (default: RULES_JSON env or rules.json)"
    )

    # Logging
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "NONE"],
        default="WARNING",
        help="Logging level (default: WARNING)"
    )

    return parser


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    parser = create_parser()
    args = parser.parse_args()

    # Configure logging
    if args.log_level != "NONE":
        logging.getLogger().setLevel(getattr(logging, args.log_level))
    else:
        logging.disable(logging.CRITICAL)

    # Determine mode
    use_api = args.api is not None

    # Run agent
    if use_api:
        api_url = args.api
        result = asyncio.run(run_online(args.prompt, args, api_url))
    else:
        result = asyncio.run(run_offline(args.prompt, args))

    # Output
    if args.json:
        print_json_output(result, args)
    else:
        print_rich_output(result, args)

    # Exit code
    sys.exit(1 if result.error else 0)


if __name__ == "__main__":
    main()
