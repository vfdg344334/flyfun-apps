"""
Server-side route state management for multi-stop route planning.

This module stores route planning state keyed by thread_id, independent of LLM parameter passing.
This ensures reliable state tracking even if LLM fails to pass correct parameters.
"""

import threading
import time
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
import logging

logger = logging.getLogger(__name__)

# TTL for route state entries (30 minutes)
ROUTE_STATE_TTL_SECONDS = 30 * 60


@dataclass
class RouteState:
    """State for a multi-stop route planning session."""
    thread_id: str
    original_departure: str
    destination: str
    original_num_stops: int
    confirmed_stops: List[str] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    
    @property
    def confirmed_stops_count(self) -> int:
        return len(self.confirmed_stops)
    
    @property
    def remaining_stops(self) -> int:
        return max(0, self.original_num_stops - self.confirmed_stops_count)
    
    @property
    def is_complete(self) -> bool:
        return self.confirmed_stops_count >= self.original_num_stops
    
    def confirm_stop(self, icao: str) -> None:
        """Add a confirmed stop."""
        if icao not in self.confirmed_stops:
            self.confirmed_stops.append(icao)
            self.updated_at = time.time()
            logger.info(f"[RouteState] Confirmed stop {icao}, total confirmed: {self.confirmed_stops_count}/{self.original_num_stops}")
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "thread_id": self.thread_id,
            "original_departure": self.original_departure,
            "destination": self.destination,
            "original_num_stops": self.original_num_stops,
            "confirmed_stops": self.confirmed_stops,
            "confirmed_stops_count": self.confirmed_stops_count,
            "remaining_stops": self.remaining_stops,
            "is_complete": self.is_complete,
        }


class RouteStateStorage:
    """Thread-safe in-memory storage for route states."""
    
    def __init__(self):
        self._states: Dict[str, RouteState] = {}
        self._lock = threading.Lock()
    
    def get(self, thread_id: str) -> Optional[RouteState]:
        """Get route state for thread_id, or None if not exists or expired."""
        with self._lock:
            state = self._states.get(thread_id)
            if state:
                # Check TTL
                if time.time() - state.updated_at > ROUTE_STATE_TTL_SECONDS:
                    del self._states[thread_id]
                    logger.info(f"[RouteState] Expired state for thread {thread_id}")
                    return None
                return state
            return None
    
    def create(
        self,
        thread_id: str,
        original_departure: str,
        destination: str,
        original_num_stops: int,
    ) -> RouteState:
        """Create a new route state. Overwrites any existing state for this thread."""
        with self._lock:
            state = RouteState(
                thread_id=thread_id,
                original_departure=original_departure,
                destination=destination,
                original_num_stops=original_num_stops,
            )
            self._states[thread_id] = state
            logger.info(f"[RouteState] Created state for thread {thread_id}: {original_departure} -> {destination}, {original_num_stops} stops")
            return state
    
    def update(self, thread_id: str, **kwargs) -> Optional[RouteState]:
        """Update route state fields."""
        with self._lock:
            state = self._states.get(thread_id)
            if state:
                for key, value in kwargs.items():
                    if hasattr(state, key):
                        setattr(state, key, value)
                state.updated_at = time.time()
                return state
            return None
    
    def confirm_stop(self, thread_id: str, icao: str) -> Optional[RouteState]:
        """Confirm a stop for the route."""
        with self._lock:
            state = self._states.get(thread_id)
            if state:
                state.confirm_stop(icao)
                return state
            return None
    
    def delete(self, thread_id: str) -> bool:
        """Delete route state for thread_id."""
        with self._lock:
            if thread_id in self._states:
                del self._states[thread_id]
                return True
            return False
    
    def cleanup_expired(self) -> int:
        """Remove expired states. Returns count of removed states."""
        with self._lock:
            now = time.time()
            expired = [
                tid for tid, state in self._states.items()
                if now - state.updated_at > ROUTE_STATE_TTL_SECONDS
            ]
            for tid in expired:
                del self._states[tid]
            if expired:
                logger.info(f"[RouteState] Cleaned up {len(expired)} expired states")
            return len(expired)


# Global singleton instance
_route_state_storage: Optional[RouteStateStorage] = None


def get_route_state_storage() -> RouteStateStorage:
    """Get the global route state storage instance."""
    global _route_state_storage
    if _route_state_storage is None:
        _route_state_storage = RouteStateStorage()
    return _route_state_storage
