"""
GA Notification Agent - Parse AIP notification requirements.

This module extracts structured notification rules from AIP customs/immigration
text fields and computes hassle scores for GA friendliness.

Architecture:
- ga_notifications.db: Factual extraction from AIP (immutable truth)
  → Use NotificationBatchProcessor to populate
  → Use NotificationService to query

- ga_persona.db: Subjective scores (hassle level, etc.)
  → Use NotificationScorer to compute from parsed rules

Configuration:
  Behavior config: configs/ga_notification_agent/default.json
  Prompts: configs/ga_notification_agent/prompts/
"""

from .models import (
    NotificationRule,
    RuleType,
    NotificationType,
    ParsedNotificationRules,
    HassleScore,
    HassleLevel,
)
from .parser import NotificationParser
from .scorer import NotificationScorer
from .config import (
    NotificationAgentConfig,
    get_notification_config,
    get_default_config,
)
from .batch_processor import NotificationBatchProcessor

__all__ = [
    # Models
    "NotificationRule",
    "RuleType",
    "NotificationType",
    "ParsedNotificationRules",
    "HassleScore",
    "HassleLevel",
    # Parser and scorer
    "NotificationParser",
    "NotificationScorer",
    # Batch processing
    "NotificationBatchProcessor",
    # Config
    "NotificationAgentConfig",
    "get_notification_config",
    "get_default_config",
]

