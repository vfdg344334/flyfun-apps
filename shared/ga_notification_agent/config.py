"""
Configuration for GA notification agent.

Follows the same pattern as aviation_agent configuration:
- Behavior config (JSON) for parsing parameters, LLM settings, prompts
- Environment variables for infrastructure (database paths, API keys)
"""

from __future__ import annotations

import json
import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

# Project root for config file resolution
PROJECT_ROOT = Path(os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[2]))


class LLMConfig(BaseModel):
    """LLM configuration for notification parsing."""
    model: str = "gpt-4o-mini"
    temperature: float = Field(default=0.0, ge=0.0, le=2.0)


class ConfidenceConfig(BaseModel):
    """Confidence thresholds for different rule types."""
    h24: float = Field(default=0.95, ge=0.0, le=1.0)
    on_request: float = Field(default=0.90, ge=0.0, le=1.0)
    as_ad_hours: float = Field(default=0.90, ge=0.0, le=1.0)
    operating_hours: float = Field(default=0.90, ge=0.0, le=1.0)  # "0800 - 1800" format
    weekday_rules: float = Field(default=0.80, ge=0.0, le=1.0)
    hours_rules: float = Field(default=0.80, ge=0.0, le=1.0)
    business_day: float = Field(default=0.75, ge=0.0, le=1.0)
    llm_extracted: float = Field(default=0.85, ge=0.0, le=1.0)
    complete_threshold: float = Field(default=0.85, ge=0.0, le=1.0)


class ParsingConfig(BaseModel):
    """Parsing behavior configuration."""
    use_llm_fallback: bool = True
    complexity_threshold: int = Field(default=2, ge=0, le=10)
    text_length_threshold: int = Field(default=300, ge=50, le=1000)
    confidence: ConfidenceConfig = ConfidenceConfig()


class PromptsConfig(BaseModel):
    """Prompt file paths."""
    parser: str = "prompts/parser_v1.md"


class NotificationAgentConfig(BaseModel):
    """
    Behavior configuration for GA notification agent.

    Controls HOW the agent parses notification rules:
    - LLM model and temperature
    - Parsing thresholds and confidence levels
    - Prompt templates

    Infrastructure settings (database paths, API keys) should use
    environment variables, not this config.
    """
    version: str = "1.0"
    name: Optional[str] = None
    description: Optional[str] = None

    llm: LLMConfig = LLMConfig()
    parsing: ParsingConfig = ParsingConfig()
    prompts: PromptsConfig = PromptsConfig()

    _config_dir: Optional[Path] = None  # Internal: set by from_file()

    def load_prompt(self, prompt_key: str) -> str:
        """
        Load prompt text from file.

        Args:
            prompt_key: Key from prompts config (e.g., "parser")

        Returns:
            Prompt text content
        """
        prompt_path = getattr(self.prompts, prompt_key, None)
        if not prompt_path:
            raise ValueError(f"Prompt '{prompt_key}' not found in config")

        # Resolve relative to config directory
        if not hasattr(self, "_config_dir") or self._config_dir is None:
            raise ValueError("Config directory not set. Use from_file() to load config.")

        full_path = self._config_dir / prompt_path
        if not full_path.exists():
            raise FileNotFoundError(f"Prompt file not found: {full_path}")

        return full_path.read_text(encoding="utf-8")

    @classmethod
    def from_file(cls, path: Path) -> "NotificationAgentConfig":
        """Load config from JSON file."""
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        config = cls(**data)
        config._config_dir = path.parent
        return config

    @classmethod
    def default(cls) -> "NotificationAgentConfig":
        """Create default config with hardcoded values."""
        return cls(
            version="1.0",
            name="default",
            description="Default GA notification agent configuration",
            llm=LLMConfig(model="gpt-4o-mini", temperature=0.0),
            parsing=ParsingConfig(
                use_llm_fallback=True,
                complexity_threshold=2,
                text_length_threshold=300,
                confidence=ConfidenceConfig(),
            ),
            prompts=PromptsConfig(parser="prompts/parser_v1.md"),
        )


@lru_cache(maxsize=10)
def get_notification_config(config_name: str = "default") -> NotificationAgentConfig:
    """
    Load notification agent behavior configuration.

    Args:
        config_name: Name of config file (without .json extension)

    Returns:
        NotificationAgentConfig instance with _config_dir set for prompt loading
    """
    config_dir = PROJECT_ROOT / "configs" / "ga_notification_agent"
    config_file = config_dir / f"{config_name}.json"

    if config_file.exists():
        config = NotificationAgentConfig.from_file(config_file)
        config._config_dir = config_dir
        logger.info(f"Loaded notification agent config: {config_name}")
        return config

    # Fall back to default if specified config doesn't exist
    if config_name != "default":
        default_file = config_dir / "default.json"
        if default_file.exists():
            logger.warning(f"Config '{config_name}' not found, using 'default'")
            config = NotificationAgentConfig.from_file(default_file)
            config._config_dir = config_dir
            return config

    # Final fallback to hardcoded defaults
    logger.info(f"Using default hardcoded config (config '{config_name}' not found)")
    config = NotificationAgentConfig.default()
    config._config_dir = config_dir
    return config


def get_default_config() -> NotificationAgentConfig:
    """Get default notification agent configuration."""
    return get_notification_config("default")
