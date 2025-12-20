package me.zhaoqian.flyfun.ui.map

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import me.zhaoqian.flyfun.data.models.Airport
import me.zhaoqian.flyfun.data.models.RouteVisualization
import me.zhaoqian.flyfun.ui.airport.AirportDetailSheet
import me.zhaoqian.flyfun.ui.theme.*
import me.zhaoqian.flyfun.viewmodel.MapViewModel
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.TileSourceFactory
import org.osmdroid.util.GeoPoint
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Marker
import org.osmdroid.views.overlay.Polyline

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen(
    onNavigateToChat: () -> Unit,
    viewModel: MapViewModel = hiltViewModel()
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsState()
    val selectedAirport by viewModel.selectedAirport.collectAsState()
    val airportDetail by viewModel.airportDetail.collectAsState()
    val aipEntries by viewModel.aipEntries.collectAsState()
    val countryRules by viewModel.countryRules.collectAsState()
    val gaSummary by viewModel.gaSummary.collectAsState()
    val filters by viewModel.filters.collectAsState()
    val selectedPersona by viewModel.selectedPersona.collectAsState()
    val gaConfig by viewModel.gaConfig.collectAsState()
    val routeVisualization by viewModel.routeVisualization.collectAsState()
    
    // Sheet state for airport details
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    
    var showFiltersDialog by remember { mutableStateOf(false) }
    var searchQuery by remember { mutableStateOf("") }
    var showSearchBar by remember { mutableStateOf(false) }
    var selectedLegendMode by remember { mutableStateOf(LegendMode.AIRPORT_TYPE) }
    
    // Initialize osmdroid configuration
    LaunchedEffect(Unit) {
        Configuration.getInstance().load(context, context.getSharedPreferences("osmdroid", Context.MODE_PRIVATE))
        Configuration.getInstance().userAgentValue = "FlyFun/1.0"
    }
    
    // Determine which airports to show - search results if searching, otherwise all airports
    val isSearchActive = searchQuery.isNotBlank() && uiState.searchResults.isNotEmpty()
    val displayedAirports = if (isSearchActive) {
        uiState.searchResults
    } else {
        uiState.airports
    }
    
    Box(modifier = Modifier.fillMaxSize()) {
        // OpenStreetMap using osmdroid
        OsmMapView(
            airports = displayedAirports,
            isSearchActive = isSearchActive,
            selectedPersona = selectedPersona,
            legendMode = selectedLegendMode,
            routeVisualization = routeVisualization,
            onAirportClick = { airport -> viewModel.selectAirport(airport) },
            modifier = Modifier.fillMaxSize()
        )
        
        // Top bar with search and filters
        SearchableTopBar(
            modifier = Modifier.align(Alignment.TopCenter),
            searchQuery = searchQuery,
            onSearchQueryChange = { query -> 
                searchQuery = query
                // Trigger search as user types (debounce would be nice but simple for now)
                if (query.length >= 2) {
                    viewModel.searchAirports(query)
                }
            },
            onSearch = { 
                viewModel.searchAirports(searchQuery)
            },
            onClearSearch = {
                searchQuery = ""
                // Clear search results - airports will revert to showing all
                viewModel.searchAirports("")
            },
            showSearchBar = showSearchBar,
            onToggleSearch = { 
                showSearchBar = !showSearchBar
                if (!showSearchBar) {
                    // Clear search when closing
                    searchQuery = ""
                    viewModel.searchAirports("")
                }
            },
            onFilterClick = { showFiltersDialog = true },
            totalAirports = if (searchQuery.isNotBlank()) displayedAirports.size else uiState.totalCount,
            isLoading = uiState.isLoading
        )
        
        // Legend overlay (bottom-left corner)
        LegendOverlay(
            selectedMode = selectedLegendMode,
            onModeChange = { selectedLegendMode = it },
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(16.dp)
                .padding(bottom = 64.dp) // Space for navigation bar
        )
        
        // Loading indicator
        if (uiState.isLoading) {
            CircularProgressIndicator(
                modifier = Modifier
                    .align(Alignment.Center)
                    .padding(16.dp)
            )
        }
        
        // Error message
        uiState.error?.let { error ->
            Snackbar(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(16.dp)
            ) {
                Text(error)
            }
        }
    }
    
    // Airport detail bottom sheet
    if (selectedAirport != null) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.clearSelectedAirport() },
            sheetState = sheetState
        ) {
            AirportDetailSheet(
                airport = selectedAirport!!,
                airportDetail = airportDetail,
                aipEntries = aipEntries,
                countryRules = countryRules,
                gaSummary = gaSummary,
                selectedPersona = selectedPersona,
                onPersonaChange = { viewModel.setSelectedPersona(it) },
                onDismiss = { viewModel.clearSelectedAirport() }
            )
        }
    }
    
    // Filters dialog
    if (showFiltersDialog) {
        FiltersDialog(
            currentFilters = filters,
            onApply = { newFilters ->
                viewModel.updateFilters(newFilters)
                showFiltersDialog = false
            },
            onClear = {
                viewModel.clearFilters()
                showFiltersDialog = false
            },
            onDismiss = { showFiltersDialog = false }
        )
    }
}

@Composable
private fun OsmMapView(
    airports: List<Airport>,
    isSearchActive: Boolean,
    selectedPersona: String,
    legendMode: LegendMode,
    routeVisualization: RouteVisualization?,
    onAirportClick: (Airport) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    
    // Remember map view to avoid recreation
    val mapView = remember {
        MapView(context).apply {
            setTileSource(TileSourceFactory.MAPNIK)
            setMultiTouchControls(true)
            controller.setZoom(5.0)
            controller.setCenter(GeoPoint(48.8, 9.0)) // Center on Europe
        }
    }
    
    // Track last zoomed route to avoid re-zooming on tab switch
    var lastZoomedRoute by remember { mutableStateOf<String?>(null) }
    val currentRouteKey = routeVisualization?.let { "${it.fromIcao}-${it.toIcao}" }
    
    // Track if we've done initial zoom
    var hasInitialized by remember { mutableStateOf(false) }
    
    // Update markers when airports or legend mode changes
    LaunchedEffect(airports, selectedPersona, routeVisualization, legendMode) {
        mapView.overlays.clear()
        
        // Draw route polyline if visualization exists
        if (routeVisualization != null) {
            val routeLine = Polyline().apply {
                addPoint(GeoPoint(routeVisualization.fromLat, routeVisualization.fromLon))
                addPoint(GeoPoint(routeVisualization.toLat, routeVisualization.toLon))
                outlinePaint.color = android.graphics.Color.parseColor("#007bff") // Blue
                outlinePaint.strokeWidth = 8f
                outlinePaint.isAntiAlias = true
            }
            mapView.overlays.add(routeLine)
        }
        
        // Filter to only airports with valid coordinates
        val validAirports = airports.filter { it.latitude != null && it.longitude != null }
        
        validAirports.forEach { airport ->
            val marker = Marker(mapView).apply {
                position = GeoPoint(airport.latitude!!, airport.longitude!!)
                title = airport.name ?: airport.icao
                snippet = airport.icao
                setAnchor(Marker.ANCHOR_CENTER, Marker.ANCHOR_CENTER)
                
                // Use colors and sizes matching the legend
                val color = getMarkerColor(airport, legendMode)
                val size = getMarkerSize(airport, legendMode)
                icon = createCircleMarker(context, color, size)
                
                setOnMarkerClickListener { _, _ ->
                    onAirportClick(airport)
                    true
                }
            }
            mapView.overlays.add(marker)
        }
        
        // Auto-zoom based on context - only zoom on changes, not every recomposition
        if (validAirports.isNotEmpty()) {
            if (isSearchActive) {
                // Zoom to fit search results (regardless of count)
                val latitudes = validAirports.mapNotNull { it.latitude }
                val longitudes = validAirports.mapNotNull { it.longitude }
                
                val minLat = latitudes.minOrNull() ?: 48.0
                val maxLat = latitudes.maxOrNull() ?: 52.0
                val minLon = longitudes.minOrNull() ?: 2.0
                val maxLon = longitudes.maxOrNull() ?: 12.0
                
                // Add padding
                val latPadding = ((maxLat - minLat) * 0.15).coerceAtLeast(0.5)
                val lonPadding = ((maxLon - minLon) * 0.15).coerceAtLeast(0.5)
                
                val boundingBox = org.osmdroid.util.BoundingBox(
                    maxLat + latPadding,
                    maxLon + lonPadding,
                    minLat - latPadding,
                    minLon - lonPadding
                )
                
                // Zoom to fit with animation
                mapView.post {
                    mapView.zoomToBoundingBox(boundingBox, true)
                }
            } else if (routeVisualization != null && currentRouteKey != lastZoomedRoute) {
                // Only zoom to fit route if it's a NEW route (not on tab switch)
                lastZoomedRoute = currentRouteKey
                
                val minLat = minOf(routeVisualization.fromLat, routeVisualization.toLat)
                val maxLat = maxOf(routeVisualization.fromLat, routeVisualization.toLat)
                val minLon = minOf(routeVisualization.fromLon, routeVisualization.toLon)
                val maxLon = maxOf(routeVisualization.fromLon, routeVisualization.toLon)
                
                val latPadding = ((maxLat - minLat) * 0.2).coerceAtLeast(1.0)
                val lonPadding = ((maxLon - minLon) * 0.2).coerceAtLeast(1.0)
                
                val routeBox = org.osmdroid.util.BoundingBox(
                    maxLat + latPadding,
                    maxLon + lonPadding,
                    minLat - latPadding,
                    minLon - lonPadding
                )
                mapView.post {
                    mapView.zoomToBoundingBox(routeBox, true)
                }
            } else if (!hasInitialized && routeVisualization == null) {
                // Initial zoom to Europe view - only on first load
                hasInitialized = true
                val europeBox = org.osmdroid.util.BoundingBox(
                    71.0, // North (Scandinavia)
                    45.0, // East (Turkey)
                    34.0, // South (Mediterranean)
                    -12.0 // West (Portugal/Atlantic)
                )
                mapView.post {
                    mapView.zoomToBoundingBox(europeBox, true)
                }
            }
        }
        
        mapView.invalidate()
    }
    
    // Cleanup
    DisposableEffect(Unit) {
        onDispose {
            mapView.onDetach()
        }
    }
    
    AndroidView(
        factory = { mapView },
        modifier = modifier
    )
}

/**
 * Create a simple colored circle drawable for map markers
 */
private fun createCircleMarker(context: Context, color: Int, sizeDp: Int): android.graphics.drawable.Drawable {
    val sizePx = (sizeDp * context.resources.displayMetrics.density).toInt()
    val bitmap = android.graphics.Bitmap.createBitmap(sizePx, sizePx, android.graphics.Bitmap.Config.ARGB_8888)
    val canvas = android.graphics.Canvas(bitmap)
    
    // Draw circle with border
    val paint = android.graphics.Paint().apply {
        isAntiAlias = true
        style = android.graphics.Paint.Style.FILL
        this.color = color
    }
    canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f - 1, paint)
    
    // White border
    paint.style = android.graphics.Paint.Style.STROKE
    paint.color = android.graphics.Color.WHITE
    paint.strokeWidth = 2f
    canvas.drawCircle(sizePx / 2f, sizePx / 2f, sizePx / 2f - 2, paint)
    
    return android.graphics.drawable.BitmapDrawable(context.resources, bitmap)
}

// Map marker color constants matching web/iOS
private object MarkerColors {
    val BORDER_CROSSING = android.graphics.Color.parseColor("#28A745")  // Green
    val WITH_PROCEDURES = android.graphics.Color.parseColor("#FFC107")  // Yellow  
    val WITHOUT_PROCEDURES = android.graphics.Color.parseColor("#DC3545") // Red
}

/**
 * Get airport marker color based on selected legend mode
 */
private fun getMarkerColor(airport: Airport, legendMode: LegendMode): Int {
    return when (legendMode) {
        LegendMode.AIRPORT_TYPE -> when {
            airport.pointOfEntry == true -> MarkerColors.BORDER_CROSSING
            airport.hasProcedures -> MarkerColors.WITH_PROCEDURES
            else -> MarkerColors.WITHOUT_PROCEDURES
        }
        LegendMode.PROCEDURE_PRECISION -> when {
            // Check for precision approaches (ILS/LPV)
            airport.hasProcedures && airport.procedureCount > 3 -> 0xFF28A745.toInt() // Green - ILS/LPV
            airport.hasProcedures && airport.procedureCount > 1 -> 0xFF17A2B8.toInt() // Teal - RNAV/RNP
            airport.hasProcedures -> 0xFFFFC107.toInt() // Yellow - VOR/NDB
            else -> 0xFFDC3545.toInt() // Red - None
        }
        LegendMode.RUNWAY_LENGTH -> {
            val lengthFt = airport.longestRunwayLengthFt ?: 0
            val lengthM = lengthFt * 0.3048
            when {
                lengthM > 1500 -> 0xFF28A745.toInt() // Green - > 1500m
                lengthM > 1000 -> 0xFF17A2B8.toInt() // Teal - 1000-1500m
                lengthM > 600 -> 0xFFFFC107.toInt() // Yellow - 600-1000m
                else -> 0xFFDC3545.toInt() // Red - < 600m
            }
        }
        LegendMode.COUNTRY -> {
            // Generate a deterministic color based on country code
            val countryCode = airport.country ?: "XX"
            val hash = countryCode.hashCode()
            val hue = (hash and 0x7FFFFFFF) % 360
            android.graphics.Color.HSVToColor(floatArrayOf(hue.toFloat(), 0.7f, 0.8f))
        }
        LegendMode.GA_RELEVANCE -> {
            // Based on GA friendliness (use procedures and border crossing as proxy for now)
            when {
                airport.pointOfEntry == true && airport.hasProcedures -> 0xFF28A745.toInt() // Green - Very Relevant
                airport.hasProcedures -> 0xFF17A2B8.toInt() // Teal - Relevant
                airport.pointOfEntry == true -> 0xFFFFC107.toInt() // Yellow - Somewhat
                else -> 0xFFDC3545.toInt() // Red - Not Relevant
            }
        }
    }
}

/**
 * Get marker size based on airport and legend mode
 */
private fun getMarkerSize(airport: Airport, legendMode: LegendMode): Int {
    return when (legendMode) {
        LegendMode.AIRPORT_TYPE -> when {
            airport.pointOfEntry == true -> 16
            airport.hasProcedures -> 14
            else -> 12
        }
        LegendMode.PROCEDURE_PRECISION -> when {
            airport.hasProcedures && airport.procedureCount > 3 -> 16
            airport.hasProcedures && airport.procedureCount > 1 -> 14
            airport.hasProcedures -> 12
            else -> 10
        }
        LegendMode.RUNWAY_LENGTH -> {
            val lengthFt = airport.longestRunwayLengthFt ?: 0
            val lengthM = lengthFt * 0.3048
            when {
                lengthM > 1500 -> 16
                lengthM > 1000 -> 14
                lengthM > 600 -> 12
                else -> 10
            }
        }
        LegendMode.COUNTRY -> 12 // Same size for all
        LegendMode.GA_RELEVANCE -> when {
            airport.pointOfEntry == true && airport.hasProcedures -> 16
            airport.hasProcedures -> 14
            airport.pointOfEntry == true -> 12
            else -> 10
        }
    }
}

/**
 * Legend mode for map marker coloring
 */
enum class LegendMode(val label: String) {
    AIRPORT_TYPE("Airport Type"),
    PROCEDURE_PRECISION("Procedure Precision"),
    RUNWAY_LENGTH("Runway Length"),
    COUNTRY("Country"),
    GA_RELEVANCE("GA Relevance")
}

@Composable
private fun LegendOverlay(
    selectedMode: LegendMode,
    onModeChange: (LegendMode) -> Unit,
    modifier: Modifier = Modifier
) {
    var showModeMenu by remember { mutableStateOf(false) }
    
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.9f),
        tonalElevation = 4.dp
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            // Header with dropdown
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Info,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "Legend",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold
                )
            }
            
            // Mode selector dropdown
            Box {
                Surface(
                    onClick = { showModeMenu = true },
                    shape = RoundedCornerShape(4.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = selectedMode.label,
                            style = MaterialTheme.typography.labelSmall
                        )
                        Icon(
                            imageVector = Icons.Default.ArrowDropDown,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
                DropdownMenu(
                    expanded = showModeMenu,
                    onDismissRequest = { showModeMenu = false }
                ) {
                    LegendMode.entries.forEach { mode ->
                        DropdownMenuItem(
                            text = { Text(mode.label) },
                            onClick = {
                                onModeChange(mode)
                                showModeMenu = false
                            },
                            leadingIcon = {
                                if (mode == selectedMode) {
                                    Icon(
                                        imageVector = Icons.Default.Check,
                                        contentDescription = "Selected",
                                        tint = MaterialTheme.colorScheme.primary
                                    )
                                }
                            }
                        )
                    }
                }
            }
            
            // Legend items based on selected mode
            when (selectedMode) {
                LegendMode.AIRPORT_TYPE -> {
                    LegendItem(
                        color = androidx.compose.ui.graphics.Color(0xFF28A745),
                        size = 16.dp,
                        label = "Border Crossing"
                    )
                    LegendItem(
                        color = androidx.compose.ui.graphics.Color(0xFFFFC107),
                        size = 14.dp,
                        label = "Airport with Procedures"
                    )
                    LegendItem(
                        color = androidx.compose.ui.graphics.Color(0xFFDC3545),
                        size = 12.dp,
                        label = "Airport without Procedures"
                    )
                }
                LegendMode.PROCEDURE_PRECISION -> {
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFF28A745), size = 14.dp, label = "ILS/LPV")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFF17A2B8), size = 14.dp, label = "RNAV/RNP")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFFFFC107), size = 14.dp, label = "VOR/NDB")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFFDC3545), size = 14.dp, label = "None")
                }
                LegendMode.RUNWAY_LENGTH -> {
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFF28A745), size = 16.dp, label = "> 1500m")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFF17A2B8), size = 14.dp, label = "1000-1500m")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFFFFC107), size = 12.dp, label = "600-1000m")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFFDC3545), size = 10.dp, label = "< 600m")
                }
                LegendMode.COUNTRY -> {
                    Text(
                        text = "Each country has unique color",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                LegendMode.GA_RELEVANCE -> {
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFF28A745), size = 16.dp, label = "Very Relevant")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFF17A2B8), size = 14.dp, label = "Relevant")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFFFFC107), size = 12.dp, label = "Somewhat")
                    LegendItem(color = androidx.compose.ui.graphics.Color(0xFFDC3545), size = 10.dp, label = "Not Relevant")
                }
            }
        }
    }
}

@Composable
private fun LegendItem(
    color: androidx.compose.ui.graphics.Color,
    size: androidx.compose.ui.unit.Dp,
    label: String
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(size)
                .clip(CircleShape)
                .background(color)
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun SearchableTopBar(
    modifier: Modifier = Modifier,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    onSearch: () -> Unit,
    onClearSearch: () -> Unit,
    showSearchBar: Boolean,
    onToggleSearch: () -> Unit,
    onFilterClick: () -> Unit,
    totalAirports: Int,
    isLoading: Boolean
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(16.dp),
        shape = RoundedCornerShape(12.dp),
        tonalElevation = 4.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // App title
                Text(
                    text = "✈️ FlyFun",
                    style = MaterialTheme.typography.titleLarge
                )
                
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Airport count
                    Text(
                        text = if (isLoading) "Loading..." else "$totalAirports airports",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    
                    // Search button
                    IconButton(onClick = onToggleSearch) {
                        Icon(
                            if (showSearchBar) Icons.Default.Close else Icons.Default.Search,
                            contentDescription = "Search"
                        )
                    }
                    
                    // Filter button
                    IconButton(onClick = onFilterClick) {
                        Icon(Icons.Default.FilterList, contentDescription = "Filters")
                    }
                }
            }
            
            // Expandable search bar
            androidx.compose.animation.AnimatedVisibility(visible = showSearchBar) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    OutlinedTextField(
                        value = searchQuery,
                        onValueChange = onSearchQueryChange,
                        modifier = Modifier.weight(1f),
                        placeholder = { Text("Search airports by name or ICAO...") },
                        singleLine = true,
                        shape = RoundedCornerShape(8.dp),
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                        trailingIcon = {
                            if (searchQuery.isNotEmpty()) {
                                IconButton(onClick = onClearSearch) {
                                    Icon(Icons.Default.Clear, contentDescription = "Clear")
                                }
                            }
                        },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            imeAction = androidx.compose.ui.text.input.ImeAction.Search
                        ),
                        keyboardActions = androidx.compose.foundation.text.KeyboardActions(
                            onSearch = { onSearch() }
                        )
                    )
                    
                    Spacer(modifier = Modifier.width(8.dp))
                    
                    FilledTonalButton(
                        onClick = onSearch,
                        enabled = searchQuery.isNotEmpty()
                    ) {
                        Text("Search")
                    }
                }
            }
        }
    }
}
