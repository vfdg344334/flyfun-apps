"""
Conversation logging adapter for aviation agent.

Simple post-execution logging approach - extracts data from final agent state
and saves to JSON log files (one file per day).
"""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from langchain_core.messages import BaseMessage

logger = logging.getLogger(__name__)


def log_conversation_from_state(
    session_id: str,
    state: Dict[str, Any],
    messages: List[BaseMessage],
    start_time: float,
    end_time: float,
    log_dir: Path,
    run_id: Optional[str] = None,
) -> None:
    """
    Log conversation from final agent state (simple post-execution approach).
    
    Args:
        session_id: Unique session identifier
        state: Final AgentState from agent execution
        messages: Conversation messages
        start_time: Request start timestamp (from time.time())
        end_time: Request end timestamp (from time.time())
        log_dir: Directory to save log files
        run_id: Optional run_id for LangSmith feedback tracking
    """
    try:
        # Extract data from state
        plan = state.get("plan")
        tool_result = state.get("tool_result")
        final_answer = state.get("final_answer", "")
        thinking = state.get("thinking", "")
        ui_payload = state.get("ui_payload")
        error = state.get("error")
        
        # Build tool_calls list
        tool_calls = []
        if plan and tool_result:
            # Handle both Pydantic model and dict
            if hasattr(plan, "selected_tool"):
                tool_name = plan.selected_tool
                tool_args = plan.arguments if hasattr(plan, "arguments") else {}
            else:
                tool_name = plan.get("selected_tool", "")
                tool_args = plan.get("arguments", {})
            
            tool_calls.append({
                "name": tool_name,
                "arguments": tool_args,
                "result": tool_result
            })
        
        # Extract user question from last message
        question = ""
        if messages:
            last_message = messages[-1]
            if hasattr(last_message, "content"):
                question = last_message.content
            elif isinstance(last_message, dict):
                question = last_message.get("content", "")
        
        # Calculate duration
        duration_seconds = end_time - start_time
        
        # Build log entry (reuse existing format for backward compatibility)
        log_entry = {
            "session_id": session_id,
            "timestamp": datetime.fromtimestamp(start_time).isoformat(),
            "timestamp_end": datetime.fromtimestamp(end_time).isoformat(),
            "duration_seconds": round(duration_seconds, 2),
            "question": question,
            "answer": final_answer,
            "thinking": thinking,
            "tool_calls": tool_calls,
            "metadata": {
                "has_visualizations": ui_payload is not None,
                "num_tool_calls": len(tool_calls),
                "has_error": error is not None,
            }
        }
        
        # Add run_id if provided (for feedback tracking)
        if run_id:
            log_entry["run_id"] = run_id
        
        # Add error if present
        if error:
            log_entry["error"] = error
        
        # Save to file
        _save_log_entry(log_entry, log_dir)
        
    except Exception as e:
        logger.error(f"Error logging conversation: {e}", exc_info=True)
        # Don't fail request if logging fails


def _save_log_entry(log_entry: Dict[str, Any], log_dir: Path) -> None:
    """
    Save log entry to JSON file (one file per day).
    
    Format: conversation_logs/YYYY-MM-DD.json
    """
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        
        # Create filename: YYYY-MM-DD.json (one file per day)
        timestamp_str = log_entry["timestamp"]
        if isinstance(timestamp_str, str):
            timestamp = datetime.fromisoformat(timestamp_str)
        else:
            timestamp = datetime.fromtimestamp(timestamp_str)
        
        date_str = timestamp.strftime("%Y-%m-%d")
        log_file = log_dir / f"{date_str}.json"
        
        # Read existing logs for today
        logs = []
        if log_file.exists():
            try:
                with open(log_file, 'r', encoding='utf-8') as f:
                    logs = json.load(f)
            except json.JSONDecodeError:
                logger.warning(f"Could not read existing log file {log_file}, starting fresh")
                logs = []
        
        # Append new entry
        logs.append(log_entry)
        
        # Write back
        with open(log_file, 'w', encoding='utf-8') as f:
            json.dump(logs, f, indent=2, ensure_ascii=False)
        
        logger.info(f"💾 Conversation logged to {log_file} (duration: {log_entry['duration_seconds']:.2f}s)")
        
    except Exception as e:
        logger.error(f"Error saving log entry: {e}", exc_info=True)
        # Don't fail request if logging fails


def find_conversation_by_run_id(run_id: str, log_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Find a conversation log entry by run_id.
    
    Searches through conversation log files to find the entry with the matching run_id.
    
    Args:
        run_id: The run_id to search for
        log_dir: Directory containing conversation log files
        
    Returns:
        The conversation log entry if found, None otherwise
    """
    try:
        if not log_dir.exists():
            logger.warning(f"Log directory {log_dir} does not exist")
            return None
        
        # Search through recent log files (last 7 days)
        from datetime import datetime, timedelta
        today = datetime.now()
        
        for days_ago in range(7):
            date = today - timedelta(days=days_ago)
            date_str = date.strftime("%Y-%m-%d")
            log_file = log_dir / f"{date_str}.json"
            
            if not log_file.exists():
                continue
            
            try:
                with open(log_file, 'r', encoding='utf-8') as f:
                    logs = json.load(f)
                    
                # Search for entry with matching run_id
                for entry in logs:
                    if entry.get("run_id") == run_id:
                        logger.info(f"Found conversation for run_id {run_id} in {log_file}")
                        return entry
            except json.JSONDecodeError:
                logger.warning(f"Could not read log file {log_file}")
                continue
            except Exception as e:
                logger.warning(f"Error reading log file {log_file}: {e}")
                continue
        
        logger.warning(f"Could not find conversation for run_id {run_id}")
        return None
        
    except Exception as e:
        logger.error(f"Error searching for conversation by run_id: {e}", exc_info=True)
        return None


def log_feedback(
    run_id: str,
    score: int,
    comment: Optional[str],
    conversation_entry: Optional[Dict[str, Any]],
    log_dir: Path,
) -> None:
    """
    Log user feedback to a separate feedback log file.
    
    Format: conversation_logs/YYYY-MM-DD-feedback.json
    
    Args:
        run_id: The run_id for the conversation
        score: Feedback score (1=thumbs up, 0=thumbs down)
        comment: Optional comment from user
        conversation_entry: Optional conversation log entry (if found)
        log_dir: Directory to save log files
    """
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        
        # Create filename: YYYY-MM-DD-feedback.json (one file per day)
        date_str = datetime.now().strftime("%Y-%m-%d")
        feedback_file = log_dir / f"{date_str}-feedback.json"
        
        # Build feedback entry
        feedback_entry = {
            "run_id": run_id,
            "timestamp": datetime.now().isoformat(),
            "feedback": "up" if score == 1 else "down",
            "score": score,
            "comment": comment,
        }
        
        # Include conversation data if available
        if conversation_entry:
            feedback_entry["question"] = conversation_entry.get("question", "")
            feedback_entry["answer"] = conversation_entry.get("answer", "")
            feedback_entry["tool_calls"] = conversation_entry.get("tool_calls", [])
            feedback_entry["session_id"] = conversation_entry.get("session_id")
            feedback_entry["conversation_timestamp"] = conversation_entry.get("timestamp")
        else:
            # If we couldn't find the conversation, log what we have
            feedback_entry["question"] = None
            feedback_entry["answer"] = None
            feedback_entry["tool_calls"] = []
            logger.warning(f"Could not find conversation data for run_id {run_id}, logging feedback only")
        
        # Read existing feedback logs for today
        feedback_logs = []
        if feedback_file.exists():
            try:
                with open(feedback_file, 'r', encoding='utf-8') as f:
                    feedback_logs = json.load(f)
            except json.JSONDecodeError:
                logger.warning(f"Could not read existing feedback file {feedback_file}, starting fresh")
                feedback_logs = []
        
        # Append new entry
        feedback_logs.append(feedback_entry)
        
        # Write back
        with open(feedback_file, 'w', encoding='utf-8') as f:
            json.dump(feedback_logs, f, indent=2, ensure_ascii=False)
        
        logger.info(f"💾 Feedback logged to {feedback_file} (run_id: {run_id}, score: {score})")
        
    except Exception as e:
        logger.error(f"Error saving feedback entry: {e}", exc_info=True)
        # Don't fail request if logging fails

