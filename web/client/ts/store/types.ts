/**
 * TypeScript type definitions for the application state
 */

/**
 * Airport data structure (matches API response)
 */
export interface Airport {
  ident: string;
  name?: string;
  municipality?: string;
  iso_country?: string;
  latitude_deg?: number;
  longitude_deg?: number;
  longest_runway_length_ft?: number;
  point_of_entry?: boolean;
  has_procedures?: boolean;
  has_aip_data?: boolean;
  has_hard_runway?: boolean;
  procedure_count?: number;
  runway_count?: number;
  // Route-specific metadata
  _routeSegmentDistance?: number;
  _routeEnrouteDistance?: number;
  _closestSegment?: [string, string];
}

/**
 * Filter configuration
 */
export interface FilterConfig {
  country: string | null;
  has_procedures: boolean | null;
  has_aip_data: boolean | null;
  has_hard_runway: boolean | null;
  point_of_entry: boolean | null;
  aip_field: string | null;
  aip_value: string | null;
  aip_operator: 'contains' | 'equals' | 'not_empty' | 'starts_with' | 'ends_with';
  has_avgas: boolean | null;
  has_jet_a: boolean | null;
  max_runway_length_ft: number | null;
  min_runway_length_ft: number | null;
  max_landing_fee: number | null;
  limit: number;
  offset: number;
  // Route-specific filters (not part of standard FilterConfig but used in API)
  enroute_distance_max_nm?: number;
}

/**
 * Legend mode types
 */
export type LegendMode = 'airport-type' | 'procedure-precision' | 'runway-length' | 'country' | 'relevance';

/**
 * Relevance bucket types (quartile-based)
 */
export type RelevanceBucket = 
  | 'top-quartile'      // Top 25% of scores
  | 'second-quartile'   // 50-75% percentile
  | 'third-quartile'    // 25-50% percentile
  | 'bottom-quartile'   // Bottom 25% of scores
  | 'unknown';          // No GA data

/**
 * Relevance bucket configuration (colors only - thresholds computed from quartiles)
 */
export interface RelevanceBucketConfig {
  id: RelevanceBucket;
  label: string;
  color: string;
}

/**
 * Persona definition with weights
 */
export interface Persona {
  id: string;
  label: string;
  description: string;
  weights: Record<string, number>;
}

/**
 * GA configuration from API (source of truth)
 */
export interface GAConfig {
  feature_names: string[];
  feature_display_names: Record<string, string>;
  feature_descriptions: Record<string, string>;
  relevance_buckets: RelevanceBucketConfig[];
  personas: Persona[];
  default_persona: string;
  version: string;
}

/**
 * GA feature scores for an airport
 */
export interface GAFeatureScores {
  ga_cost_score: number | null;
  ga_review_score: number | null;
  ga_hassle_score: number | null;
  ga_ops_ifr_score: number | null;
  ga_ops_vfr_score: number | null;
  ga_access_score: number | null;
  ga_fun_score: number | null;
  ga_hospitality_score: number | null;
}

/**
 * GA score for a single airport
 */
export interface AirportGAScore {
  icao: string;
  has_data: boolean;
  score: number | null;
  features: GAFeatureScores | null;
  review_count: number;
}

/**
 * Full GA summary for an airport
 */
export interface AirportGASummary extends AirportGAScore {
  last_review_utc: string | null;
  tags: string[];
  summary_text: string | null;
  notification_summary: string | null;
  hassle_level: string | null;
  hotel_info: string | null;
  restaurant_info: string | null;
}

/**
 * Computed quartile thresholds
 */
export interface QuartileThresholds {
  q1: number;  // 25th percentile
  q2: number;  // 50th percentile (median)
  q3: number;  // 75th percentile
}

/**
 * GA Friendliness state
 */
export interface GAState {
  // Configuration from API
  config: GAConfig | null;
  configLoaded: boolean;
  configError: string | null;
  
  // Runtime state
  selectedPersona: string;
  scores: Map<string, AirportGAScore>;
  summaries: Map<string, AirportGASummary>;
  isLoading: boolean;
  
  // Computed from current scores (recalculated when scores change)
  computedQuartiles: QuartileThresholds | null;
}

/**
 * Highlight data
 */
export interface Highlight {
  id: string;
  type: 'point' | 'airport';
  lat: number;
  lng: number;
  color?: string;
  radius?: number;
  popup?: string;
}

/**
 * Overlay data
 */
export interface Overlay {
  id: string;
  type: 'circle' | 'polygon' | 'polyline';
  data: any; // Leaflet layer data
}

/**
 * Visualization configuration
 */
export interface VisualizationConfig {
  legendMode: LegendMode;
  highlights: Map<string, Highlight>;
  overlays: Map<string, Overlay>;
  showProcedureLines: boolean;
  showRoute: boolean;
}

/**
 * Route state
 */
export interface RouteState {
  airports: string[] | null; // ICAO codes
  distance_nm: number;
  originalRouteAirports: Array<{icao: string; lat: number; lng: number}> | null;
  isChatbotSelection: boolean;
  chatbotAirports: Airport[] | null;
}

/**
 * Locate state
 */
export interface LocateState {
  query: string | null;
  center: {lat: number; lng: number; label: string} | null;
  radiusNm: number;
}

/**
 * Map view state
 */
export interface MapView {
  center: [number, number]; // [lat, lng]
  zoom: number;
}

/**
 * UI state
 */
export interface UIState {
  loading: boolean;
  error: string | null;
  searchQuery: string;
  activeTab: 'details' | 'aip' | 'rules' | 'relevance';
}

/**
 * Complete application state
 */
export interface AppState {
  // Airport data
  airports: Airport[];
  filteredAirports: Airport[];
  
  // Filter configuration
  filters: FilterConfig;
  
  // Visualization configuration
  visualization: VisualizationConfig;
  
  // Route state
  route: RouteState | null;
  
  // Locate state
  locate: LocateState | null;
  
  // Selection state
  selectedAirport: Airport | null;
  
  // Map view state
  mapView: MapView;
  
  // UI state
  ui: UIState;
  
  // GA Friendliness state
  ga: GAState;
}

/**
 * Action types for state updates
 */
export type AppAction =
  | { type: 'SET_AIRPORTS'; payload: Airport[] }
  | { type: 'SET_FILTERS'; payload: Partial<FilterConfig> }
  | { type: 'SET_LEGEND_MODE'; payload: LegendMode }
  | { type: 'HIGHLIGHT_POINT'; payload: Highlight }
  | { type: 'REMOVE_HIGHLIGHT'; payload: string }
  | { type: 'CLEAR_HIGHLIGHTS' }
  | { type: 'SET_ROUTE'; payload: RouteState | null }
  | { type: 'SET_LOCATE'; payload: LocateState | null }
  | { type: 'SELECT_AIRPORT'; payload: Airport | null }
  | { type: 'SET_MAP_VIEW'; payload: MapView }
  | { type: 'SET_LOADING'; payload: boolean }
  | { type: 'SET_ERROR'; payload: string | null }
  | { type: 'SET_SEARCH_QUERY'; payload: string }
  | { type: 'SET_ACTIVE_TAB'; payload: UIState['activeTab'] }
  | { type: 'CLEAR_FILTERS' }
  | { type: 'RESET_STATE' };

