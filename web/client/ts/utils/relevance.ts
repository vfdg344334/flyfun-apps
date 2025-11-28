/**
 * Relevance utilities for GA friendliness scoring.
 * 
 * Handles dynamic quartile calculation and bucket assignment.
 */

import type { 
  AirportGAScore, 
  QuartileThresholds, 
  RelevanceBucket, 
  RelevanceBucketConfig,
  Airport
} from '../store/types';

/**
 * Compute quartile thresholds from actual score distribution.
 * 
 * Benefits:
 * - Always produces meaningful buckets regardless of scoring formula
 * - Works for any persona (different weight combinations)
 * - Adapts to score distribution changes
 * 
 * @param scores Map of ICAO -> AirportGAScore
 * @returns Quartile thresholds or null if insufficient data
 */
export function computeQuartileThresholds(
  scores: Map<string, AirportGAScore>
): QuartileThresholds | null {
  // Extract valid scores (has_data and score is not null)
  const validScores = Array.from(scores.values())
    .filter(s => s.has_data && s.score !== null)
    .map(s => s.score as number)
    .sort((a, b) => a - b);
  
  // Need at least 4 data points for meaningful quartiles
  if (validScores.length < 4) {
    return null;
  }
  
  const n = validScores.length;
  return {
    q1: validScores[Math.floor(n * 0.25)],  // 25th percentile
    q2: validScores[Math.floor(n * 0.50)],  // 50th percentile (median)
    q3: validScores[Math.floor(n * 0.75)],  // 75th percentile
  };
}

/**
 * Compute quartile thresholds from airports with embedded GA data.
 * 
 * @param airports Array of airports
 * @param personaId Persona ID to get scores for
 * @returns Quartile thresholds or null if insufficient data
 */
export function computeQuartilesFromAirports(
  airports: Airport[],
  personaId: string
): QuartileThresholds | null {
  // Extract valid scores from airport.ga.persona_scores
  const validScores = airports
    .filter(a => a.ga?.persona_scores?.[personaId] !== null && a.ga?.persona_scores?.[personaId] !== undefined)
    .map(a => a.ga!.persona_scores[personaId] as number)
    .sort((a, b) => a - b);
  
  // Need at least 4 data points for meaningful quartiles
  if (validScores.length < 4) {
    return null;
  }
  
  const n = validScores.length;
  return {
    q1: validScores[Math.floor(n * 0.25)],  // 25th percentile
    q2: validScores[Math.floor(n * 0.50)],  // 50th percentile (median)
    q3: validScores[Math.floor(n * 0.75)],  // 75th percentile
  };
}

/**
 * Get relevance bucket for a score based on computed quartiles.
 * 
 * @param score The computed score (or null)
 * @param quartiles Quartile thresholds (or null)
 * @returns Bucket ID
 */
export function getRelevanceBucket(
  score: number | null,
  quartiles: QuartileThresholds | null
): RelevanceBucket {
  if (score === null) {
    return 'unknown';
  }
  
  if (!quartiles) {
    // Fallback: no quartile data, treat all as unknown
    return 'unknown';
  }
  
  if (score >= quartiles.q3) return 'top-quartile';
  if (score >= quartiles.q2) return 'second-quartile';
  if (score >= quartiles.q1) return 'third-quartile';
  return 'bottom-quartile';
}

/**
 * Get color for a relevance bucket.
 * 
 * @param bucket Bucket ID
 * @param bucketConfigs Bucket configuration from API
 * @returns CSS color string
 */
export function getRelevanceBucketColor(
  bucket: RelevanceBucket,
  bucketConfigs: RelevanceBucketConfig[]
): string {
  const config = bucketConfigs.find(c => c.id === bucket);
  return config?.color ?? '#95a5a6'; // Default gray
}

/**
 * Get bucket configuration for a bucket ID.
 * 
 * @param bucket Bucket ID
 * @param bucketConfigs Bucket configuration from API
 * @returns Bucket configuration or undefined
 */
export function getBucketConfig(
  bucket: RelevanceBucket,
  bucketConfigs: RelevanceBucketConfig[]
): RelevanceBucketConfig | undefined {
  return bucketConfigs.find(c => c.id === bucket);
}

/**
 * Get color for an airport based on its score and current quartiles.
 * 
 * @param gaScore Airport GA score (or undefined)
 * @param quartiles Computed quartile thresholds
 * @param bucketConfigs Bucket configuration from API
 * @returns CSS color string
 */
export function getAirportRelevanceColor(
  gaScore: AirportGAScore | undefined,
  quartiles: QuartileThresholds | null,
  bucketConfigs: RelevanceBucketConfig[]
): string {
  const score = gaScore?.score ?? null;
  const bucket = getRelevanceBucket(score, quartiles);
  return getRelevanceBucketColor(bucket, bucketConfigs);
}

/**
 * Default bucket colors (fallback if config not loaded).
 */
export const DEFAULT_BUCKET_CONFIGS: RelevanceBucketConfig[] = [
  { id: 'top-quartile', label: 'Most Relevant', color: '#27ae60' },
  { id: 'second-quartile', label: 'Relevant', color: '#3498db' },
  { id: 'third-quartile', label: 'Less Relevant', color: '#e67e22' },
  { id: 'bottom-quartile', label: 'Least Relevant', color: '#e74c3c' },
  { id: 'unknown', label: 'Unknown', color: '#95a5a6' },
];

