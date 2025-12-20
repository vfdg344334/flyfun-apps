package me.zhaoqian.flyfun.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import me.zhaoqian.flyfun.data.models.*
import me.zhaoqian.flyfun.data.repository.FlyFunRepository
import me.zhaoqian.flyfun.data.repository.RouteStateHolder
import javax.inject.Inject

/**
 * ViewModel for the Map screen - manages airport data and filtering.
 */
@HiltViewModel
class MapViewModel @Inject constructor(
    private val repository: FlyFunRepository,
    private val routeStateHolder: RouteStateHolder
) : ViewModel() {
    
    // UI State
    private val _uiState = MutableStateFlow(MapUiState())
    val uiState: StateFlow<MapUiState> = _uiState.asStateFlow()
    
    // Selected airport for detail view
    private val _selectedAirport = MutableStateFlow<Airport?>(null)
    val selectedAirport: StateFlow<Airport?> = _selectedAirport.asStateFlow()
    
    // Airport detail (full info)
    private val _airportDetail = MutableStateFlow<AirportDetail?>(null)
    val airportDetail: StateFlow<AirportDetail?> = _airportDetail.asStateFlow()
    
    // AIP entries for selected airport
    private val _aipEntries = MutableStateFlow<List<AipEntry>>(emptyList())
    val aipEntries: StateFlow<List<AipEntry>> = _aipEntries.asStateFlow()
    
    // Country rules for selected airport
    private val _countryRules = MutableStateFlow<CountryRulesResponse?>(null)
    val countryRules: StateFlow<CountryRulesResponse?> = _countryRules.asStateFlow()
    
    // GA summary for selected airport
    private val _gaSummary = MutableStateFlow<GADetailedSummary?>(null)
    val gaSummary: StateFlow<GADetailedSummary?> = _gaSummary.asStateFlow()
    
    // Filters
    private val _filters = MutableStateFlow(AirportFilters())
    val filters: StateFlow<AirportFilters> = _filters.asStateFlow()
    
    // GA Config
    private val _gaConfig = MutableStateFlow<GAConfig?>(null)
    val gaConfig: StateFlow<GAConfig?> = _gaConfig.asStateFlow()
    
    // Selected persona
    private val _selectedPersona = MutableStateFlow("ifr_touring_sr22")
    val selectedPersona: StateFlow<String> = _selectedPersona.asStateFlow()
    
    // Route visualization from chat (observed from shared state)
    // Route visualization from chat (observed from shared state)
    val routeVisualization: StateFlow<RouteVisualization?> = routeStateHolder.routeVisualization
    
    // Internal cache of all loaded airports
    private val _allAirports = MutableStateFlow<List<Airport>>(emptyList())
    
    init {
        loadAirports()
        loadGAConfig()
        
        // Observe route, filters and apply client-side filtering
        viewModelScope.launch {
            combine(_allAirports, routeVisualization, _filters) { allAirports, routeViz, filters ->
                val baseAirports = if (routeViz != null && routeViz.airports.isNotEmpty()) {
                    // If visualising a route, show ONLY the airports from the route
                    routeViz.airports
                } else {
                    // Otherwise show all loaded airports
                    allAirports
                }
                
                // Apply client-side filters
                baseAirports.filter { airport ->
                    // Has Procedures filter
                    val passesHasProcedures = filters.hasProcedures != true || 
                        airport.hasProcedures
                    
                    // Has AIP Data filter
                    val passesHasAipData = filters.hasAipData != true || 
                        airport.hasAipData
                    
                    // Has Hard Runway filter
                    val passesHasHardRunway = filters.hasHardRunway != true || 
                        airport.hasHardRunway
                    
                    // Combine all filters
                    passesHasProcedures && passesHasAipData && passesHasHardRunway
                }
            }.collect { filteredAirports ->
                _uiState.update { 
                    it.copy(
                        airports = filteredAirports,
                        totalCount = filteredAirports.size
                    )
                }
            }
        }
    }
    
    fun clearRouteVisualization() {
        routeStateHolder.clearRouteVisualization()
    }
    
    fun loadAirports() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            
            val currentFilters = _filters.value
            
            // Map facility filters to AIP field/value/operator
            // Only one AIP filter can be used at a time, so prioritize
            val (aipField, aipValue, aipOperator) = when {
                currentFilters.hasAvgas == true -> Triple("Fuel and oil types", "avgas", "contains")
                currentFilters.hasJetA == true -> Triple("Fuel and oil types", "jet a", "contains")
                currentFilters.hasHotels == true -> Triple("Hotels", null, "not_empty")
                currentFilters.hasRestaurants == true -> Triple("Restaurants", null, "not_empty")
                currentFilters.hasCustoms == true -> Triple("Customs and immigration", null, "not_empty")
                currentFilters.hasDeicing == true -> Triple("De-icing facilities", null, "not_empty")
                currentFilters.hasHangar == true -> Triple("Hangar space for visiting aircraft", null, "not_empty")
                else -> Triple(null, null, null)
            }
            
            repository.getAirports(
                country = currentFilters.country,
                hasProcedure = currentFilters.procedureType,
                hasIls = currentFilters.hasIls,
                pointOfEntry = currentFilters.pointOfEntry,
                runwayMinLength = currentFilters.runwayMinLength,
                search = currentFilters.searchQuery,
                hasProcedures = currentFilters.hasProcedures,
                hasAipData = currentFilters.hasAipData,
                hasHardRunway = currentFilters.hasHardRunway,
                aipField = aipField,
                aipValue = aipValue,
                aipOperator = aipOperator
            ).fold(
                onSuccess = { airports ->
                    _allAirports.value = airports
                    // UI state will be updated by the combine collector
                    _uiState.update { it.copy(isLoading = false) }
                },
                onFailure = { error ->
                    _uiState.update { 
                        it.copy(
                            isLoading = false,
                            error = error.message ?: "Failed to load airports"
                        )
                    }
                }
            )
        }
    }
    
    private fun loadGAConfig() {
        viewModelScope.launch {
            repository.getGAConfig().onSuccess { config ->
                _gaConfig.value = config
                _selectedPersona.value = config.defaultPersona
            }
        }
    }
    
    fun selectAirport(airport: Airport) {
        android.util.Log.w("MapVM", "selectAirport called: ${airport.icao}")
        _selectedAirport.value = airport
        loadAirportDetail(airport.icao, airport.country)
    }
    
    fun clearSelectedAirport() {
        _selectedAirport.value = null
        _airportDetail.value = null
        _aipEntries.value = emptyList()
        _countryRules.value = null
        _gaSummary.value = null
    }
    
    private fun loadAirportDetail(icao: String, countryCode: String?) {
        android.util.Log.w("MapVM", "loadAirportDetail: icao=$icao, country=$countryCode")
        viewModelScope.launch {
            // Fetch airport detail (includes aipEntries)
            repository.getAirportDetail(icao)
                .onSuccess { detail ->
                    android.util.Log.w("MapVM", "AirportDetail success: runways=${detail.runways.size}, procedures=${detail.procedures.size}, aipEntries=${detail.aipEntries.size}")
                    _airportDetail.value = detail
                    // Use AIP entries from the main detail endpoint
                    _aipEntries.value = detail.aipEntries
                }
                .onFailure { e ->
                    android.util.Log.e("MapVM", "AirportDetail failed: ${e.message}", e)
                }
            
            // Fetch country rules if country code is available
            countryCode?.let { country ->
                repository.getCountryRules(country)
                    .onSuccess { rules ->
                        android.util.Log.d("MapVM", "CountryRules success: ${rules.totalRules} rules")
                        _countryRules.value = rules
                    }
                    .onFailure { e ->
                        android.util.Log.e("MapVM", "CountryRules failed: ${e.message}")
                    }
            }
            
            // Fetch GA summary with selected persona
            repository.getGASummary(icao, _selectedPersona.value)
                .onSuccess { summary ->
                    android.util.Log.d("MapVM", "GASummary success: hasData=${summary.hasData}, score=${summary.score}")
                    _gaSummary.value = summary
                }
                .onFailure { e ->
                    android.util.Log.e("MapVM", "GASummary failed: ${e.message}")
                }
        }
    }
    
    fun updateFilters(filters: AirportFilters) {
        _filters.value = filters
        loadAirports()
    }
    
    fun clearFilters() {
        _filters.value = AirportFilters()
        loadAirports()
    }
    
    fun setSelectedPersona(personaId: String) {
        _selectedPersona.value = personaId
    }
    
    fun searchAirports(query: String) {
        viewModelScope.launch {
            if (query.length >= 2) {
                repository.searchAirports(query).onSuccess { results ->
                    _uiState.update { it.copy(searchResults = results) }
                }
            } else {
                _uiState.update { it.copy(searchResults = emptyList()) }
            }
        }
    }
}

data class MapUiState(
    val isLoading: Boolean = false,
    val airports: List<Airport> = emptyList(),
    val totalCount: Int = 0,
    val error: String? = null,
    val searchResults: List<Airport> = emptyList()
)

data class AirportFilters(
    val country: String? = null,
    val procedureType: String? = null,
    val hasIls: Boolean? = null,
    val pointOfEntry: Boolean? = null,
    val runwayMinLength: Int? = null,
    val searchQuery: String? = null,
    // Additional filters matching web UI
    val hasProcedures: Boolean? = null,
    val hasAipData: Boolean? = null,
    val hasHardRunway: Boolean? = null,
    // AIP Quick Filters
    val hasHotels: Boolean? = null,
    val hasRestaurants: Boolean? = null,
    val hasAvgas: Boolean? = null,
    val hasJetA: Boolean? = null,
    val hasCustoms: Boolean? = null,
    val hasDeicing: Boolean? = null,
    val hasHangar: Boolean? = null
)
