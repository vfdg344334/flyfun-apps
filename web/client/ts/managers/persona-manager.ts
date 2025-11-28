/**
 * PersonaManager - Handles persona selection and GA score loading.
 * 
 * Responsibilities:
 * - Load GA config on startup
 * - Manage persona selection with localStorage persistence
 * - Trigger score loading when needed
 * - Integrate with store for state management
 */

import { APIAdapter } from '../adapters/api-adapter';
import { useStore } from '../store/store';
import type { GAConfig, Persona, AirportGAScore, Airport, QuartileThresholds } from '../store/types';

const PERSONA_STORAGE_KEY = 'flyfun-selected-persona';
const DEFAULT_PERSONA = 'ifr_touring_sr22';

export class PersonaManager {
  private api: APIAdapter;
  private initialized: boolean = false;
  
  constructor(api: APIAdapter) {
    this.api = api;
  }
  
  /**
   * Initialize the PersonaManager.
   * Loads GA config and restores persona selection from localStorage.
   */
  async init(): Promise<void> {
    if (this.initialized) {
      console.log('[PersonaManager] Already initialized');
      return;
    }
    
    console.log('[PersonaManager] Initializing...');
    
    try {
      // Load GA config from API
      const config = await this.api.getGAConfig();
      useStore.getState().setGAConfig(config);
      console.log('[PersonaManager] GA config loaded:', {
        features: config.feature_names.length,
        personas: config.personas.length
      });
      
      // Restore persona from localStorage or use default
      const savedPersona = this.getSavedPersona();
      const validPersona = this.validatePersona(savedPersona, config);
      
      if (validPersona !== savedPersona) {
        console.log(`[PersonaManager] Saved persona "${savedPersona}" invalid, using "${validPersona}"`);
      }
      
      useStore.getState().setGASelectedPersona(validPersona);
      this.savePersona(validPersona);
      
      // Populate persona selector in UI
      this.populatePersonaSelector();
      
      this.initialized = true;
      console.log('[PersonaManager] Initialized with persona:', validPersona);
      
    } catch (error) {
      console.error('[PersonaManager] Failed to initialize:', error);
      useStore.getState().setGAConfigError(
        error instanceof Error ? error.message : 'Failed to load GA config'
      );
      
      // Still set default persona even if config fails
      useStore.getState().setGASelectedPersona(DEFAULT_PERSONA);
      this.initialized = true;
    }
  }
  
  /**
   * Get saved persona from localStorage.
   */
  private getSavedPersona(): string {
    try {
      const saved = localStorage.getItem(PERSONA_STORAGE_KEY);
      return saved || DEFAULT_PERSONA;
    } catch {
      return DEFAULT_PERSONA;
    }
  }
  
  /**
   * Save persona to localStorage.
   */
  private savePersona(personaId: string): void {
    try {
      localStorage.setItem(PERSONA_STORAGE_KEY, personaId);
    } catch (error) {
      console.warn('[PersonaManager] Failed to save persona to localStorage:', error);
    }
  }
  
  /**
   * Validate persona exists in config, return default if not.
   */
  private validatePersona(personaId: string, config: GAConfig): string {
    const exists = config.personas.some(p => p.id === personaId);
    return exists ? personaId : config.default_persona || DEFAULT_PERSONA;
  }
  
  /**
   * Select a different persona.
   * Updates store and localStorage, recomputes quartiles for the new persona.
   */
  selectPersona(personaId: string): void {
    const state = useStore.getState();
    const config = state.ga.config;
    
    if (!config) {
      console.warn('[PersonaManager] Cannot select persona: config not loaded');
      return;
    }
    
    const validPersona = this.validatePersona(personaId, config);
    
    if (validPersona !== personaId) {
      console.warn(`[PersonaManager] Persona "${personaId}" not found, using "${validPersona}"`);
    }
    
    // Update store
    state.setGASelectedPersona(validPersona);
    this.savePersona(validPersona);
    
    // Recompute quartiles for the new persona
    // (Uses airport.ga.persona_scores which has all personas pre-computed)
    this.computeQuartiles();
    
    console.log('[PersonaManager] Selected persona:', validPersona);
  }
  
  /**
   * Get current persona ID.
   */
  getCurrentPersona(): string {
    return useStore.getState().ga.selectedPersona;
  }
  
  /**
   * Get list of available personas.
   */
  getPersonas(): Persona[] {
    return useStore.getState().ga.config?.personas || [];
  }
  
  /**
   * Get current persona config.
   */
  getCurrentPersonaConfig(): Persona | undefined {
    const personaId = this.getCurrentPersona();
    return this.getPersonas().find(p => p.id === personaId);
  }
  
  /**
   * Compute quartile thresholds from the current airports.
   * Called when airports change or persona changes to recompute visualization buckets.
   * 
   * Note: GA scores are now embedded in airport.ga from the API response.
   * This method computes dynamic quartile thresholds for the relevance legend.
   */
  computeQuartiles(): void {
    const state = useStore.getState();
    const airports = state.filteredAirports;
    const persona = state.ga.selectedPersona;
    
    // Extract scores for the selected persona from airports with GA data
    const scores: number[] = [];
    for (const airport of airports) {
      if (airport.ga?.persona_scores) {
        const score = airport.ga.persona_scores[persona];
        if (score !== null && score !== undefined) {
          scores.push(score);
        }
      }
    }
    
    if (scores.length < 4) {
      console.log(`[PersonaManager] Not enough scores (${scores.length}) to compute quartiles`);
      state.setGAComputedQuartiles(null);
      return;
    }
    
    // Sort scores ascending
    scores.sort((a, b) => a - b);
    
    // Compute quartile thresholds
    const q1Index = Math.floor(scores.length * 0.25);
    const q2Index = Math.floor(scores.length * 0.5);
    const q3Index = Math.floor(scores.length * 0.75);
    
    const quartiles: QuartileThresholds = {
      q1: scores[q1Index],
      q2: scores[q2Index],
      q3: scores[q3Index]
    };
    
    console.log(`[PersonaManager] Computed quartiles from ${scores.length} scores:`, quartiles);
    state.setGAComputedQuartiles(quartiles);
  }
  
  /**
   * Legacy method - no longer needed as scores come with airport data.
   * Kept for backwards compatibility but does nothing.
   * @deprecated Use airport.ga.persona_scores instead
   */
  async loadScores(_icaos: string[]): Promise<void> {
    // GA scores are now embedded in airport response via include_ga=true
    // Just compute quartiles from the current airports
    this.computeQuartiles();
  }
  
  /**
   * Load full GA summary for a single airport.
   */
  async loadSummary(icao: string): Promise<void> {
    const state = useStore.getState();
    const persona = state.ga.selectedPersona;
    
    // Check if already cached
    if (state.ga.summaries.has(icao.toUpperCase())) {
      console.log(`[PersonaManager] Summary for ${icao} already cached`);
      return;
    }
    
    console.log(`[PersonaManager] Loading summary for ${icao}`);
    
    try {
      const summary = await this.api.getGASummary(icao, persona);
      state.setGASummary(icao.toUpperCase(), summary);
      console.log(`[PersonaManager] Loaded summary for ${icao}`);
    } catch (error) {
      console.error(`[PersonaManager] Failed to load summary for ${icao}:`, error);
    }
  }
  
  /**
   * Get score for an airport (from cache).
   */
  getScore(icao: string): AirportGAScore | undefined {
    return useStore.getState().ga.scores.get(icao.toUpperCase());
  }
  
  /**
   * Check if GA feature is enabled (config loaded successfully).
   */
  isEnabled(): boolean {
    const state = useStore.getState();
    return state.ga.configLoaded && !state.ga.configError && state.ga.config !== null;
  }
  
  /**
   * Populate the persona selector dropdown in the UI.
   */
  private populatePersonaSelector(): void {
    const selector = document.getElementById('persona-selector') as HTMLSelectElement;
    if (!selector) {
      console.log('[PersonaManager] Persona selector not found in DOM');
      return;
    }
    
    const config = useStore.getState().ga.config;
    if (!config || !config.personas) {
      return;
    }
    
    selector.innerHTML = '';
    config.personas.forEach(persona => {
      const option = document.createElement('option');
      option.value = persona.id;
      option.textContent = persona.label;
      selector.appendChild(option);
    });
    
    // Select current persona
    const currentPersona = useStore.getState().ga.selectedPersona;
    selector.value = currentPersona;
    
    console.log('[PersonaManager] Populated persona selector with', config.personas.length, 'personas');
  }
}

