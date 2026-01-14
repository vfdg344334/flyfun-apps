/**
 * Legend Classification Utilities
 *
 * Generic functions for classifying data using legend configurations.
 * These utilities ensure consistent classification between legend display
 * and marker coloring.
 *
 * @see designs/LEGEND_DESIGN.md for architecture documentation
 */

import type { LegendConfig, LegendEntry } from '../store/types';

/**
 * Find the first matching legend entry for a data item.
 * First match wins - order of entries matters.
 *
 * @param data - The data item to classify (e.g., Airport)
 * @param entries - Ordered legend entries with match functions
 * @returns The first matching entry, or undefined if no match
 */
export function classifyData<TData>(
  data: TData,
  entries: LegendEntry<TData>[]
): LegendEntry<TData> | undefined {
  return entries.find(entry => entry.match(data));
}

/**
 * Get the color for a data item based on a legend configuration.
 *
 * @param data - The data item to classify
 * @param config - Legend configuration with ordered entries
 * @param fallbackColor - Color to use if no entry matches (default: gray)
 * @returns The color hex string
 */
export function getColorFromConfig<TData>(
  data: TData,
  config: LegendConfig<TData>,
  fallbackColor: string = '#95a5a6'
): string {
  const entry = classifyData(data, config.entries);
  return entry?.color ?? fallbackColor;
}

/**
 * Get style (color and radius) for a data item based on a legend configuration.
 *
 * @param data - The data item to classify
 * @param config - Legend configuration with ordered entries
 * @param baseRadius - Base radius for markers (default: 7)
 * @returns Object with color and radius
 */
export function getStyleFromConfig<TData>(
  data: TData,
  config: LegendConfig<TData>,
  baseRadius: number = 7
): { color: string; radius: number } {
  const entry = classifyData(data, config.entries);
  return {
    color: entry?.color ?? '#95a5a6',
    radius: Math.round(baseRadius * (entry?.radiusMultiplier ?? 1.0)),
  };
}

/**
 * Get the bucket ID for a data item based on a legend configuration.
 * Useful for analytics or grouping.
 *
 * @param data - The data item to classify
 * @param config - Legend configuration with ordered entries
 * @returns The bucket ID string, or 'unknown' if no match
 */
export function getBucketId<TData>(
  data: TData,
  config: LegendConfig<TData>
): string {
  const entry = classifyData(data, config.entries);
  return entry?.id ?? 'unknown';
}
