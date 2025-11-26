"""
Caching utility for remote data sources.

Provides caching for JSON data to avoid repeated downloads/processing.
"""

import gzip
import json
import logging
from abc import ABC, abstractmethod
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Optional, Tuple

from .exceptions import CacheError

logger = logging.getLogger(__name__)


class CachedDataLoader(ABC):
    """
    Base class for data loaders that implement caching.
    
    Similar pattern to euro_aip's CachedSource, but independent.
    Provides caching for remote data to avoid repeated downloads.
    
    Usage:
        class MyLoader(CachedDataLoader):
            def fetch_data(self, key: str, **kwargs) -> Any:
                # Fetch from remote source
                return data
        
        loader = MyLoader(cache_dir=Path("/path/to/cache"))
        data = loader.get_cached("my_key", max_age_days=7)
    """

    def __init__(self, cache_dir: Path):
        """
        Initialize cached loader.
        
        Args:
            cache_dir: Base directory for caching
        """
        self.cache_dir = cache_dir
        self._force_refresh = False
        self._never_refresh = False

        # Create cache directory
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def set_force_refresh(self, force_refresh: bool = True) -> None:
        """Set whether to force refresh of cached data."""
        self._force_refresh = force_refresh
        if force_refresh:
            self._never_refresh = False

    def set_never_refresh(self, never_refresh: bool = True) -> None:
        """Set whether to never refresh cached data (use cache if exists)."""
        self._never_refresh = never_refresh
        if never_refresh:
            self._force_refresh = False

    def _get_cache_file(self, key: str, ext: str = "json") -> Path:
        """Get cache file path for a key."""
        # Sanitize key for filename
        safe_key = key.replace("/", "_").replace("\\", "_").replace(":", "_")
        return self.cache_dir / f"{safe_key}.{ext}"

    def _is_cache_valid(
        self,
        cache_file: Path,
        max_age_days: Optional[int] = None
    ) -> Tuple[bool, Optional[str]]:
        """
        Check if cache file is valid.
        
        Returns:
            (is_valid, reason_if_invalid)
        """
        # Check force_refresh flag
        if self._force_refresh:
            return False, "force_refresh enabled"

        # Check if file exists
        if not cache_file.exists():
            return False, "cache file does not exist"

        # Check never_refresh flag
        if self._never_refresh:
            return True, None

        # Check age if max_age_days provided
        if max_age_days is not None:
            mtime = datetime.fromtimestamp(cache_file.stat().st_mtime)
            age = datetime.now() - mtime
            if age > timedelta(days=max_age_days):
                return False, f"cache expired (age: {age.days} days, max: {max_age_days})"

        return True, None

    def _save_to_cache(self, data: Any, key: str, ext: str = "json") -> None:
        """Save data to cache."""
        cache_file = self._get_cache_file(key, ext)

        try:
            if ext.endswith(".gz"):
                # Gzip compressed JSON
                with gzip.open(cache_file, "wt", encoding="utf-8") as f:
                    json.dump(data, f)
            else:
                # Plain JSON
                with open(cache_file, "w", encoding="utf-8") as f:
                    json.dump(data, f, indent=2)
        except Exception as e:
            raise CacheError(f"Failed to save to cache: {e}")

    def _load_from_cache(self, key: str, ext: str = "json") -> Any:
        """Load data from cache."""
        cache_file = self._get_cache_file(key, ext)

        try:
            if ext.endswith(".gz"):
                # Gzip compressed JSON
                with gzip.open(cache_file, "rt", encoding="utf-8") as f:
                    return json.load(f)
            else:
                # Plain JSON
                with open(cache_file, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception as e:
            raise CacheError(f"Failed to load from cache: {e}")

    @abstractmethod
    def fetch_data(self, key: str, **kwargs: Any) -> Any:
        """
        Fetch data from remote source.
        
        Must be implemented by subclasses.
        
        Args:
            key: Cache key identifying the data
            **kwargs: Additional arguments for fetching
            
        Returns:
            Fetched data
        """
        pass

    def get_cached(
        self,
        key: str,
        max_age_days: Optional[int] = None,
        ext: str = "json",
        **kwargs: Any
    ) -> Any:
        """
        Get data from cache or fetch if needed.
        
        Args:
            key: Cache key
            max_age_days: Maximum age of cache (None = no limit)
            ext: File extension (json, json.gz)
            **kwargs: Arguments to pass to fetch_data()
        
        Returns:
            Cached or freshly fetched data
        """
        cache_file = self._get_cache_file(key, ext)
        is_valid, reason = self._is_cache_valid(cache_file, max_age_days)

        if is_valid:
            logger.debug(f"Loading from cache: {key}")
            return self._load_from_cache(key, ext)

        logger.debug(f"Cache miss for {key}: {reason}")

        # Fetch fresh data
        data = self.fetch_data(key, **kwargs)

        # Save to cache
        self._save_to_cache(data, key, ext)

        return data

    def clear_cache(self, key: Optional[str] = None) -> None:
        """
        Clear cached data.
        
        Args:
            key: Specific key to clear, or None to clear all
        """
        if key:
            # Clear specific key
            for ext in ["json", "json.gz"]:
                cache_file = self._get_cache_file(key, ext)
                if cache_file.exists():
                    cache_file.unlink()
        else:
            # Clear all cache files
            for cache_file in self.cache_dir.glob("*"):
                if cache_file.is_file():
                    cache_file.unlink()

    def get_cache_info(self, key: str, ext: str = "json") -> Optional[dict]:
        """
        Get information about cached data.
        
        Returns:
            Dict with cache info or None if not cached
        """
        cache_file = self._get_cache_file(key, ext)
        if not cache_file.exists():
            return None

        stat = cache_file.stat()
        return {
            "path": str(cache_file),
            "size_bytes": stat.st_size,
            "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            "age_days": (datetime.now() - datetime.fromtimestamp(stat.st_mtime)).days,
        }

