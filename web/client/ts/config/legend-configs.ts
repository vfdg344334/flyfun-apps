/**
 * Legend Configuration
 *
 * This file defines shared legend configurations that ensure
 * legend display and marker coloring are always in sync.
 *
 * Architecture:
 * - Each legend mode has a config with ordered entries
 * - First match wins - order matters
 * - Both legend rendering and marker coloring use the same config
 *
 * @see designs/LEGEND_DESIGN.md for full documentation
 */

import type {
  Airport,
  LegendConfig,
  LegendEntry,
  LegendDisplayBucket,
  NotificationBucketId,
  AirportTypeBucketId,
  RunwayLengthBucketId,
  CountryBucketId,
  ProcedurePrecisionBucketId,
} from '../store/types';

// =============================================================================
// Notification Legend Configuration
// =============================================================================

/**
 * Notification color palette
 * Semantic meaning based on pilot hassle level
 */
export const NOTIFICATION_COLORS = {
  green: '#28a745',   // Easy - no/minimal notice required
  blue: '#007bff',    // Moderate - call ahead or 13-24h notice
  yellow: '#ffc107',  // Hassle - 25-48h or business day notice
  red: '#dc3545',     // Difficult - >48h notice or not available
  gray: '#95a5a6',    // Unknown - no data
} as const;

/**
 * Notification legend entries - ORDER MATTERS (first match wins).
 *
 * This configuration preserves the exact logic from the original
 * getNotificationColor() function in visualization-engine.ts.
 *
 * Classification order:
 * 1. No notification data -> gray (unknown)
 * 2. H24 operations -> green (no notice)
 * 3. Not available -> red (difficult)
 * 4. On request -> blue (moderate - must call)
 * 5. Business day notice -> yellow (hassle)
 * 6. Hours type with no hours_notice -> green (operating hours only)
 * 7. Hours null/undefined -> gray (unknown)
 * 8. Hours <= 12 -> green (easy)
 * 9. Hours 13-24 -> blue (moderate)
 * 10. Hours 25-48 -> yellow (hassle)
 * 11. Hours > 48 -> red (difficult)
 */
export const NOTIFICATION_LEGEND_ENTRIES: LegendEntry<Airport>[] = [
  // 1. No notification data
  {
    id: 'unknown' as NotificationBucketId,
    label: 'No notification data',
    color: NOTIFICATION_COLORS.gray,
    radiusMultiplier: 0.85,
    match: (airport) => !airport.notification,
  },
  // 2. H24 operations - no notice required
  {
    id: 'h24' as NotificationBucketId,
    label: 'H24 (No notice required)',
    color: NOTIFICATION_COLORS.green,
    radiusMultiplier: 1.1,
    match: (airport) => airport.notification?.is_h24 === true,
  },
  // 3. Not available
  {
    id: 'difficult' as NotificationBucketId,
    label: 'Not available',
    color: NOTIFICATION_COLORS.red,
    radiusMultiplier: 1.0,
    match: (airport) => airport.notification?.notification_type === 'not_available',
  },
  // 4. On request - must call ahead
  {
    id: 'moderate' as NotificationBucketId,
    label: 'On request',
    color: NOTIFICATION_COLORS.blue,
    radiusMultiplier: 1.0,
    match: (airport) => airport.notification?.is_on_request === true,
  },
  // 5. Business day notice
  {
    id: 'hassle' as NotificationBucketId,
    label: 'Business day notice',
    color: NOTIFICATION_COLORS.yellow,
    radiusMultiplier: 1.0,
    match: (airport) => airport.notification?.notification_type === 'business_day',
  },
  // 6. Hours type with no hours_notice = operating hours only
  {
    id: 'easy' as NotificationBucketId,
    label: 'Operating hours only',
    color: NOTIFICATION_COLORS.green,
    radiusMultiplier: 1.0,
    match: (airport) => {
      const n = airport.notification;
      return n?.notification_type === 'hours' &&
             (n.hours_notice === null || n.hours_notice === undefined);
    },
  },
  // 7. Hours null/undefined with other types = unknown
  {
    id: 'unknown' as NotificationBucketId,
    label: 'Unknown hours',
    color: NOTIFICATION_COLORS.gray,
    radiusMultiplier: 0.85,
    match: (airport) => {
      const n = airport.notification;
      return n?.hours_notice === null || n?.hours_notice === undefined;
    },
  },
  // 8. Hours <= 12 = easy
  {
    id: 'easy' as NotificationBucketId,
    label: '<=12h notice',
    color: NOTIFICATION_COLORS.green,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.notification?.hours_notice ?? Infinity) <= 12,
  },
  // 9. Hours 13-24 = moderate
  {
    id: 'moderate' as NotificationBucketId,
    label: '13-24h notice',
    color: NOTIFICATION_COLORS.blue,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.notification?.hours_notice ?? Infinity) <= 24,
  },
  // 10. Hours 25-48 = hassle
  {
    id: 'hassle' as NotificationBucketId,
    label: '25-48h notice',
    color: NOTIFICATION_COLORS.yellow,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.notification?.hours_notice ?? Infinity) <= 48,
  },
  // 11. Hours > 48 = difficult (default fallback)
  {
    id: 'difficult' as NotificationBucketId,
    label: '>48h notice',
    color: NOTIFICATION_COLORS.red,
    radiusMultiplier: 1.0,
    match: () => true, // Default case - catches everything else
  },
];

/**
 * Notification legend display buckets.
 *
 * Simplified view for the legend panel - groups related conditions
 * into 5 user-friendly categories.
 */
export const NOTIFICATION_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'easy', label: 'H24 / <=12h notice', color: NOTIFICATION_COLORS.green },
  { id: 'moderate', label: '13-24h / On request', color: NOTIFICATION_COLORS.blue },
  { id: 'hassle', label: '25-48h / Business day', color: NOTIFICATION_COLORS.yellow },
  { id: 'difficult', label: '>48h / Not available', color: NOTIFICATION_COLORS.red },
  { id: 'unknown', label: 'Unknown', color: NOTIFICATION_COLORS.gray },
];

/**
 * Complete notification legend configuration.
 */
export const NOTIFICATION_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'notification',
  displayType: 'color',
  entries: NOTIFICATION_LEGEND_ENTRIES,
};

// =============================================================================
// Airport Type Legend Configuration
// =============================================================================

/**
 * Airport type color palette
 */
export const AIRPORT_TYPE_COLORS = {
  green: '#28a745',   // Border crossing (point of entry)
  yellow: '#ffc107',  // Has instrument procedures
  red: '#dc3545',     // No instrument procedures
} as const;

/**
 * Airport type legend entries - ORDER MATTERS (first match wins).
 * Priority: border crossing > has procedures > no procedures
 */
export const AIRPORT_TYPE_LEGEND_ENTRIES: LegendEntry<Airport>[] = [
  {
    id: 'border-crossing' as AirportTypeBucketId,
    label: 'Border Crossing',
    color: AIRPORT_TYPE_COLORS.green,
    radiusMultiplier: 1.15,
    match: (airport) => airport.point_of_entry === true,
  },
  {
    id: 'with-procedures' as AirportTypeBucketId,
    label: 'Airport with Procedures',
    color: AIRPORT_TYPE_COLORS.yellow,
    radiusMultiplier: 1.0,
    match: (airport) => airport.has_procedures === true,
  },
  {
    id: 'without-procedures' as AirportTypeBucketId,
    label: 'Airport without Procedures',
    color: AIRPORT_TYPE_COLORS.red,
    radiusMultiplier: 0.85,
    match: () => true, // Default fallback
  },
];

/**
 * Airport type legend display buckets.
 */
export const AIRPORT_TYPE_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'border-crossing', label: 'Border Crossing', color: AIRPORT_TYPE_COLORS.green },
  { id: 'with-procedures', label: 'Airport with Procedures', color: AIRPORT_TYPE_COLORS.yellow },
  { id: 'without-procedures', label: 'Airport without Procedures', color: AIRPORT_TYPE_COLORS.red },
];

/**
 * Complete airport type legend configuration.
 */
export const AIRPORT_TYPE_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'airport-type',
  displayType: 'color',
  entries: AIRPORT_TYPE_LEGEND_ENTRIES,
};

// =============================================================================
// Runway Length Legend Configuration
// =============================================================================

/**
 * Runway length color palette
 */
export const RUNWAY_LENGTH_COLORS = {
  green: '#28a745',   // Long runway (>8000 ft)
  yellow: '#ffc107',  // Medium runway (4000-8000 ft)
  red: '#dc3545',     // Short runway (<4000 ft)
  gray: '#6c757d',    // Unknown length
} as const;

/**
 * Runway length legend entries - ORDER MATTERS (first match wins).
 */
export const RUNWAY_LENGTH_LEGEND_ENTRIES: LegendEntry<Airport>[] = [
  {
    id: 'unknown' as RunwayLengthBucketId,
    label: 'Unknown Length',
    color: RUNWAY_LENGTH_COLORS.gray,
    radiusMultiplier: 0.6,
    match: (airport) => !airport.longest_runway_length_ft,
  },
  {
    id: 'long' as RunwayLengthBucketId,
    label: 'Long Runway (>8000ft)',
    color: RUNWAY_LENGTH_COLORS.green,
    radiusMultiplier: 1.4,
    match: (airport) => (airport.longest_runway_length_ft ?? 0) > 8000,
  },
  {
    id: 'medium' as RunwayLengthBucketId,
    label: 'Medium Runway (4000-8000ft)',
    color: RUNWAY_LENGTH_COLORS.yellow,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.longest_runway_length_ft ?? 0) > 4000,
  },
  {
    id: 'short' as RunwayLengthBucketId,
    label: 'Short Runway (<4000ft)',
    color: RUNWAY_LENGTH_COLORS.red,
    radiusMultiplier: 0.7,
    match: () => true, // Default fallback
  },
];

/**
 * Runway length legend display buckets.
 */
export const RUNWAY_LENGTH_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'long', label: 'Long Runway (>8000ft)', color: RUNWAY_LENGTH_COLORS.green },
  { id: 'medium', label: 'Medium Runway (4000-8000ft)', color: RUNWAY_LENGTH_COLORS.yellow },
  { id: 'short', label: 'Short Runway (<4000ft)', color: RUNWAY_LENGTH_COLORS.red },
  { id: 'unknown', label: 'Unknown Length', color: RUNWAY_LENGTH_COLORS.gray },
];

/**
 * Complete runway length legend configuration.
 */
export const RUNWAY_LENGTH_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'runway-length',
  displayType: 'color',
  entries: RUNWAY_LENGTH_LEGEND_ENTRIES,
};

// =============================================================================
// Country Legend Configuration
// =============================================================================

/**
 * Country color palette
 */
export const COUNTRY_COLORS = {
  blue: '#007bff',    // France (LF)
  red: '#dc3545',     // United Kingdom (EG)
  green: '#28a745',   // Germany (ED)
  yellow: '#ffc107',  // Other countries
} as const;

/**
 * Country legend entries - ORDER MATTERS (first match wins).
 * Based on ICAO prefix matching.
 */
export const COUNTRY_LEGEND_ENTRIES: LegendEntry<Airport>[] = [
  {
    id: 'france' as CountryBucketId,
    label: 'France (LF)',
    color: COUNTRY_COLORS.blue,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.ident || '').startsWith('LF'),
  },
  {
    id: 'uk' as CountryBucketId,
    label: 'United Kingdom (EG)',
    color: COUNTRY_COLORS.red,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.ident || '').startsWith('EG'),
  },
  {
    id: 'germany' as CountryBucketId,
    label: 'Germany (ED)',
    color: COUNTRY_COLORS.green,
    radiusMultiplier: 1.0,
    match: (airport) => (airport.ident || '').startsWith('ED'),
  },
  {
    id: 'other' as CountryBucketId,
    label: 'Other Countries',
    color: COUNTRY_COLORS.yellow,
    radiusMultiplier: 0.85,
    match: () => true, // Default fallback
  },
];

/**
 * Country legend display buckets.
 */
export const COUNTRY_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'france', label: 'France (LF)', color: COUNTRY_COLORS.blue },
  { id: 'uk', label: 'United Kingdom (EG)', color: COUNTRY_COLORS.red },
  { id: 'germany', label: 'Germany (ED)', color: COUNTRY_COLORS.green },
  { id: 'other', label: 'Other Countries', color: COUNTRY_COLORS.yellow },
];

/**
 * Complete country legend configuration.
 */
export const COUNTRY_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'country',
  displayType: 'color',
  entries: COUNTRY_LEGEND_ENTRIES,
};

// =============================================================================
// Procedure Precision Legend Configuration
// =============================================================================

/**
 * Procedure precision color palette.
 * Note: These colors are for procedure LINES, not markers.
 * Markers are transparent in this mode.
 */
export const PROCEDURE_PRECISION_COLORS = {
  yellow: '#ffff00',  // ILS (Precision)
  blue: '#0000ff',    // RNP/RNAV
  white: '#ffffff',   // VOR/NDB (Non-Precision)
  transparent: 'rgba(128, 128, 128, 0.3)', // Marker color (transparent)
} as const;

/**
 * Procedure precision legend display buckets.
 * Note: This mode uses transparent markers and colored procedure lines.
 * The entries below are for the legend display and procedure line coloring,
 * NOT for marker classification.
 */
export const PROCEDURE_PRECISION_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'precision', label: 'ILS (Precision)', color: PROCEDURE_PRECISION_COLORS.yellow },
  { id: 'rnp', label: 'RNP/RNAV (RNP)', color: PROCEDURE_PRECISION_COLORS.blue },
  { id: 'non-precision', label: 'VOR/NDB (Non-Precision)', color: PROCEDURE_PRECISION_COLORS.white },
];

/**
 * Complete procedure precision legend configuration.
 * Note: useTransparentMarkers=true means airport markers are transparent,
 * and procedure lines are colored instead.
 */
export const PROCEDURE_PRECISION_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'procedure-precision',
  displayType: 'line',
  entries: [], // No marker-based entries - uses transparent markers
  useTransparentMarkers: true,
};
