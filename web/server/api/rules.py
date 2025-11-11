#!/usr/bin/env python3

from fastapi import APIRouter, HTTPException, Path
from typing import Optional, Dict, List
import logging

from shared.rules_manager import RulesManager

from .models import CountryRulesResponse, RuleCategoryResponse, RuleEntryResponse

logger = logging.getLogger(__name__)

router = APIRouter()

rules_manager: Optional[RulesManager] = None


def set_rules_manager(manager: RulesManager) -> None:
    """Set the shared RulesManager instance for the rules API."""
    global rules_manager
    rules_manager = manager
    if rules_manager and not rules_manager.loaded:
        try:
            rules_manager.load_rules()
        except Exception as exc:
            logger.error("Failed to load rules: %s", exc, exc_info=True)
            raise


@router.get(
    "/{country_code}",
    response_model=CountryRulesResponse,
    summary="Get aviation rules for a country grouped by category",
)
async def get_country_rules(
    country_code: str = Path(..., min_length=2, max_length=3, description="ISO-2 country code")
) -> CountryRulesResponse:
    """Return aviation rules grouped by category for a country."""
    if not rules_manager:
        raise HTTPException(status_code=500, detail="Rules manager not initialized")

    code = country_code.upper()
    try:
        entries = rules_manager.get_rules_for_country(code)
    except Exception as exc:
        logger.error("Error retrieving rules for %s: %s", code, exc, exc_info=True)
        raise HTTPException(status_code=500, detail=f"Failed to load rules for {code}")

    categories: Dict[str, List[RuleEntryResponse]] = {}
    for entry in entries:
        category_name = entry.get("category") or "General"
        if category_name not in categories:
            categories[category_name] = []

        rule = RuleEntryResponse(
            question_id=entry.get("question_id", ""),
            question_text=entry.get("question_text"),
            category=category_name,
            tags=entry.get("tags") or [],
            answer_html=entry.get("answer_html"),
            links=entry.get("links") or [],
            last_reviewed=entry.get("last_reviewed"),
            confidence=entry.get("confidence"),
        )
        categories[category_name].append(rule)

    category_list = [
        RuleCategoryResponse(
            name=category,
            count=len(rules),
            rules=sorted(rules, key=lambda r: r.question_text or r.question_id),
        )
        for category, rules in sorted(categories.items(), key=lambda item: item[0].lower())
    ]

    total_rules = sum(category.count for category in category_list)

    return CountryRulesResponse(
        country=code,
        total_rules=total_rules,
        categories=category_list,
    )

