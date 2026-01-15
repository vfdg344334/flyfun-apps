/**
 * GeocodeCache - Caches geocode results for consistent search behavior
 *
 * When a locate search is performed (via chatbot or locate button), we cache
 * the search label → coordinates mapping. This allows the search handler to
 * recognize when the search box contains a geocode query and use the cached
 * coordinates instead of doing a text search on airport names.
 *
 * This solves the problem where:
 * 1. Chatbot does locate for "Brac, Croatia"
 * 2. Search box shows "Brac, Croatia"
 * 3. Debounced search fires, does text search → 0 results → overwrites airports
 *
 * With cache:
 * 1. Chatbot does locate, caches "Brac, Croatia" → {lat, lon}
 * 2. Search box shows "Brac, Croatia"
 * 3. Debounced search fires, finds cache hit → does locate search with cached coords
 */

export interface GeocodeEntry {
  lat: number;
  lon: number;
  label: string;
  timestamp: number;
}

export class GeocodeCache {
  private cache = new Map<string, GeocodeEntry>();
  private readonly maxSize: number;

  constructor(maxSize = 256) {
    this.maxSize = maxSize;
  }

  /**
   * Cache a geocode result
   * @param searchText The search text (will be used as lookup key)
   * @param lat Latitude
   * @param lon Longitude
   * @param label Display label
   */
  set(searchText: string, lat: number, lon: number, label: string): void {
    const key = this.normalizeKey(searchText);

    // Evict oldest if at capacity (and not updating existing entry)
    if (this.cache.size >= this.maxSize && !this.cache.has(key)) {
      this.evictOldest();
    }

    this.cache.set(key, { lat, lon, label, timestamp: Date.now() });
    console.log(`📍 GeocodeCache: cached "${key}" → (${lat.toFixed(4)}, ${lon.toFixed(4)})`);
  }

  /**
   * Get a cached geocode result
   * @param searchText The search text to look up
   * @returns The cached entry, or undefined if not found
   */
  get(searchText: string): GeocodeEntry | undefined {
    const key = this.normalizeKey(searchText);
    const entry = this.cache.get(key);
    if (entry) {
      console.log(`📍 GeocodeCache: hit for "${key}"`);
    }
    return entry;
  }

  /**
   * Check if a search text is in the cache
   */
  has(searchText: string): boolean {
    return this.cache.has(this.normalizeKey(searchText));
  }

  /**
   * Clear all cached entries
   */
  clear(): void {
    this.cache.clear();
    console.log('📍 GeocodeCache: cleared');
  }

  /**
   * Get the number of cached entries
   */
  get size(): number {
    return this.cache.size;
  }

  /**
   * Normalize the cache key for consistent lookups
   */
  private normalizeKey(searchText: string): string {
    return searchText.trim().toLowerCase();
  }

  /**
   * Evict the oldest entry from the cache
   */
  private evictOldest(): void {
    let oldestKey: string | undefined;
    let oldestTime = Infinity;

    for (const [key, entry] of this.cache) {
      if (entry.timestamp < oldestTime) {
        oldestTime = entry.timestamp;
        oldestKey = key;
      }
    }

    if (oldestKey) {
      this.cache.delete(oldestKey);
      console.log(`📍 GeocodeCache: evicted oldest entry "${oldestKey}"`);
    }
  }
}

// Singleton instance for use across the app
export const geocodeCache = new GeocodeCache(256);
