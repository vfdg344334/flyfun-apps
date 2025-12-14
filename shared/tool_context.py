#!/usr/bin/env python3
"""
ToolContext provides access to shared resources for tool execution.

This module contains the ToolContext class which is used throughout the codebase
to provide access to airports database, rules manager, notification service, and
GA friendliness service.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional

from euro_aip.models.euro_aip_model import EuroAipModel
from euro_aip.storage.database_storage import DatabaseStorage

from .rules_manager import RulesManager


@dataclass
class ToolContext:
    """
    Context providing access to shared resources for tool execution.

    Note: ToolContext is NOT stateful - do not store user-specific state here.
    Pass user preferences (like persona) via tool function parameters or context dicts.
    """

    model: EuroAipModel
    notification_service: Optional[Any] = None  # NotificationService (lazy import to avoid circular deps)
    ga_friendliness_service: Optional[Any] = None  # GAFriendlinessService (lazy import)
    rules_manager: Optional[RulesManager] = None

    @classmethod
    def create(
        cls,
        load_airports: bool = True,
        load_rules: bool = True,
        load_notifications: bool = True,
        load_ga_friendliness: bool = True,
    ) -> "ToolContext":
        """
        Create ToolContext with all paths resolved from environment/config.
        
        All paths are resolved using centralized config functions from
        shared/aviation_agent/config.py. Services are optional and will
        gracefully degrade if not available or disabled.
        
        Args:
            load_airports: Load airports database (default: True)
            load_rules: Load rules manager (default: True)
            load_notifications: Load notification service (default: True)
            load_ga_friendliness: Load GA friendliness service (default: True)
        
        Returns:
            ToolContext instance with requested services loaded
        """
        from pathlib import Path

        # Get all paths from centralized config
        from shared.aviation_agent.config import (
            _default_airports_db,
            _default_rules_json,
            get_ga_notifications_db_path,
            get_ga_meta_db_path,
        )

        # Load core model (required if load_airports is True)
        model = None
        if load_airports:
            airports_db_path = _default_airports_db()
            storage = DatabaseStorage(str(airports_db_path))
            model = storage.load_model()
        else:
            raise ValueError("load_airports must be True - airports database is required")

        # Initialize NotificationService (optional)
        notification_service = None
        if load_notifications:
            try:
                from shared.ga_notification_agent.service import NotificationService
                notification_service = NotificationService()
            except Exception:
                pass  # Service is optional

        # Initialize GAFriendlinessService (optional)
        ga_friendliness_service = None
        if load_ga_friendliness:
            try:
                from shared.ga_friendliness.service import GAFriendlinessService
                ga_meta_db = get_ga_meta_db_path()
                if ga_meta_db and Path(ga_meta_db).exists():
                    ga_friendliness_service = GAFriendlinessService(ga_meta_db, readonly=True)
            except Exception:
                pass  # Service is optional

        # Initialize RulesManager (optional)
        rules_manager = None
        if load_rules:
            rules_path = _default_rules_json()
            rules_manager = RulesManager(str(rules_path))
            rules_manager.load_rules()

        return cls(
            model=model,
            notification_service=notification_service,
            ga_friendliness_service=ga_friendliness_service,
            rules_manager=rules_manager,
        )

    def ensure_rules_manager(self) -> RulesManager:
        if not self.rules_manager:
            self.rules_manager = RulesManager()
            self.rules_manager.load_rules()
        elif not self.rules_manager.loaded:
            self.rules_manager.load_rules()
        return self.rules_manager

