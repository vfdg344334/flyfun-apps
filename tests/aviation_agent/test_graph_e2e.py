from __future__ import annotations

from shared.aviation_agent.adapters.langgraph_runner import run_aviation_agent


def test_agent_runner_produces_ui_payload(
    agent_settings,
    sample_messages,
    planner_llm_stub,
    formatter_llm_stub,
):
    # Note: Routing behavior is controlled by behavior_config, not function params.
    # The sample_messages fixture asks about IFR routing, which routes to database path.
    state = run_aviation_agent(
        sample_messages,
        settings=agent_settings,
        planner_llm=planner_llm_stub,
        formatter_llm=formatter_llm_stub,
    )

    plan = state.get("plan")
    assert plan is not None, "Plan should be present in state"
    assert plan.selected_tool == "search_airports"
    assert state.get("final_answer") is not None, "Final answer should be present"
    ui_payload = state.get("ui_payload")
    assert ui_payload is not None, "UI payload should be present"
    assert ui_payload["kind"] == "route"

