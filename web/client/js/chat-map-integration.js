/**
 * Chat-Map Integration
 * Handles visualization of chatbot results on the Leaflet map
 */

class ChatMapIntegration {
    constructor(map) {
        this.map = map;
        this.chatMarkers = [];
        this.chatMarkersData = []; // Store marker + airport data for updates
        this.chatLayers = L.layerGroup();
        this.chatLayers.addTo(this.map);

        // Keep track of visualization state
        this.currentVisualization = null;
        this.isFilteredMode = false; // Track if we're showing only chat results
        this.chatAirports = []; // Store full airport data for filtering
    }

    /**
     * Visualize data on the map based on chatbot response
     *
     * Brice's approach: Map chatbot visualizations to FilterManager operations
     * - route_with_markers → filterManager.handleRouteSearch()
     * - marker_with_details → filterManager.handleSearch()
     * This allows all UI filters to work consistently on chatbot results
     */
    visualizeData(visualization) {
        if (!visualization) return;

        console.log('ChatMapIntegration.visualizeData called with:', visualization);

        // Helper to use route flow through FilterManager
        const handleRouteViaFilters = (routeObj) => {
            const fromIcao = routeObj?.from?.icao;
            const toIcao = routeObj?.to?.icao;
            if (fromIcao && toIcao && typeof filterManager !== 'undefined' && filterManager?.handleRouteSearch) {
                // Let the unified route pipeline render markers/route and apply filters
                try {
                    console.log(`✅ Delegating route ${fromIcao} → ${toIcao} to FilterManager`);
                    // Call the route handler directly
                    filterManager.handleRouteSearch([fromIcao, toIcao]);
                    return true;
                } catch (e) {
                    console.warn('❌ Route handoff to FilterManager failed:', e);
                }
            }
            return false;
        };

        // Helper to use search flow through FilterManager
        const handleIdentViaSearch = (ident) => {
            if (ident && typeof filterManager !== 'undefined' && filterManager?.handleSearch) {
                try {
                    console.log(`✅ Delegating search for ${ident} to FilterManager`);
                    // Update search box for UX coherence
                    const searchInput = document.getElementById('search-input');
                    if (searchInput) searchInput.value = ident;
                    filterManager.handleSearch(ident);
                    return true;
                } catch (e) {
                    console.warn('❌ Ident handoff to FilterManager failed:', e);
                }
            }
            return false;
        };

        // Array visualizations: prefer the first route or marker-with-details item
        if (Array.isArray(visualization)) {
            console.log('Array visualization detected, processing...');
            // Try to find a route visualization first
            const firstRoute = visualization.find(v => v && v.type === 'route_with_markers');
            if (firstRoute && handleRouteViaFilters(firstRoute.route)) {
                return;
            }
            // Then try single-marker detail visualization
            const firstDetail = visualization.find(v => v && v.type === 'marker_with_details');
            if (firstDetail && handleIdentViaSearch(firstDetail.marker?.ident)) {
                return;
            }
            // Otherwise, fall back to overlay rendering for all
            this.clearChatVisualizations();
            this.currentVisualization = null;
            visualization.forEach(viz => this.visualizeSingle(viz));
            return;
        }

        // Single visualization routing
        if (visualization && visualization.type === 'route_with_markers') {
            console.log('route_with_markers detected with', visualization.markers?.length, 'markers');

            // Use chatbot's pre-selected airports instead of re-fetching all route airports
            if (this.handleRouteWithChatbotAirports(visualization)) {
                console.log('✅ Successfully handled route with chatbot-selected airports');
                return;
            }

            // Fallback if delegation fails
            console.warn('FilterManager integration failed, using fallback rendering');
            this.clearChatVisualizations();
            this.visualizeSingle(visualization);
            return;
        } else if (visualization && visualization.type === 'marker_with_details') {
            if (handleIdentViaSearch(visualization.marker?.ident)) {
                console.log('✅ Successfully delegated marker_with_details to FilterManager');
                return;
            }
        }

        // Fallback: render as overlay
        console.log('Fallback rendering for visualization type:', visualization?.type);
        this.clearChatVisualizations();
        this.visualizeSingle(visualization);
    }

    /**
     * Handle route visualization with chatbot's pre-selected airports
     * This integrates with FilterManager while preserving the chatbot's airport selection
     */
    handleRouteWithChatbotAirports(visualization) {
        try {
            if (!visualization || !visualization.route || !visualization.markers) {
                return false;
            }

            const route = visualization.route;
            const markers = visualization.markers;
            const fromIcao = route.from?.icao;
            const toIcao = route.to?.icao;

            if (!fromIcao || !toIcao || !filterManager) {
                return false;
            }

            console.log(`Integrating chatbot route ${fromIcao} → ${toIcao} with ${markers.length} airports into FilterManager`);

            // Normalize route airport objects for displayRoute (needs icao, lat, lng)
            const normalizedRouteAirports = [
                {
                    icao: fromIcao,
                    lat: route.from.latitude || route.from.latitude_deg || route.from.lat,
                    lng: route.from.longitude || route.from.longitude_deg || route.from.lon
                },
                {
                    icao: toIcao,
                    lat: route.to.latitude || route.to.latitude_deg || route.to.lat,
                    lng: route.to.longitude || route.to.longitude_deg || route.to.lon
                }
            ];

            console.log('Normalized route airports:', normalizedRouteAirports);

            // Set FilterManager's route state (so filters can be reapplied)
            filterManager.currentRoute = {
                airports: [fromIcao, toIcao],
                originalRouteAirports: normalizedRouteAirports,
                isChatbotSelection: true,  // FLAG: This is from chatbot, don't re-query
                chatbotAirports: markers   // Store chatbot's original selection
            };

            // Update FilterManager's stored airports with chatbot's selection
            filterManager.airports = markers;

            // Update the map with chatbot's airports (using FilterManager's method for consistency)
            filterManager.updateMapWithAirports(markers, false);

            // Draw the route line using airportMap's displayRoute method
            if (window.airportMap) {
                // Extract route airport ICAOs
                const routeAirports = [fromIcao, toIcao];
                // Use a default distance for display (won't affect the markers already shown)
                const distanceNm = 50;
                window.airportMap.displayRoute(routeAirports, distanceNm, true, normalizedRouteAirports);
            }

            console.log(`✅ FilterManager now has ${markers.length} chatbot-selected airports. Filters will work on these.`);
            return true;

        } catch (e) {
            console.error('Error in handleRouteWithChatbotAirports:', e);
            return false;
        }
    }

    /**
     * Visualize a single visualization object on the map
     */
    visualizeSingle(viz) {
        console.log('visualizeSingle called with viz:', viz);
        if (!viz || !viz.type) {
            console.warn('Invalid viz object:', viz);
            return;
        }

        console.log('Processing viz type:', viz.type);
        switch (viz.type) {
            case 'route_with_markers':
                console.log('Calling visualizeRouteWithMarkers...');
                this.visualizeRouteWithMarkers(viz);
                break;
            case 'markers':
                console.log('Calling visualizeMarkers with data...');
                this.visualizeMarkers(viz.data || []);
                break;
            case 'marker_with_details':
                if (viz.marker) {
                    console.log('Calling visualizeMarkers with single marker...');
                    this.visualizeMarkers([viz.marker]);
                }
                break;
            default:
                console.warn('Unknown visualization type:', viz.type);
        }
    }

    /**
     * Visualize route with markers (ONLY the markers provided, not all route airports)
     */
    visualizeRouteWithMarkers(viz) {
        console.log('visualizeRouteWithMarkers called, viz:', viz);
        const route = viz.route;
        const markers = viz.markers || [];

        console.log('Route:', route, 'Markers:', markers.length);

        // Draw route line
        if (route && route.from && route.to) {
            const from = route.from;
            const to = route.to;

            console.log('Drawing route from', from, 'to', to);

            if (from.latitude && from.longitude && to.latitude && to.longitude) {
                const routeLine = L.polyline(
                    [[from.latitude, from.longitude], [to.latitude, to.longitude]],
                    { color: '#3388ff', weight: 2, opacity: 0.6 }
                );
                this.chatLayers.addLayer(routeLine);
                console.log('Route line added to map');
            } else if (from.lat && from.lon && to.lat && to.lon) {
                // Try alternative property names
                const routeLine = L.polyline(
                    [[from.lat, from.lon], [to.lat, to.lon]],
                    { color: '#3388ff', weight: 2, opacity: 0.6 }
                );
                this.chatLayers.addLayer(routeLine);
                console.log('Route line added to map (using lat/lon properties)');
            } else {
                console.warn('Route coordinates missing:', from, to);
            }
        }

        // Display ONLY the markers provided by chatbot (not all route airports)
        console.log('About to call visualizeMarkers with', markers.length, 'markers');
        this.visualizeMarkers(markers);
    }

    /**
     * Get marker color based on current legend mode (mimic map.js logic)
     */
    getMarkerColor(airport) {
        const legendMode = window.airportMap?.legendMode || 'airport-type';
        let color = '#ffc107'; // Default: yellow
        let radius = 8;

        if (legendMode === 'runway-length') {
            if (airport.longest_runway_length_ft) {
                if (airport.longest_runway_length_ft > 8000) {
                    color = '#28a745'; // Green for long runways
                    radius = 10;
                } else if (airport.longest_runway_length_ft >= 4000) {
                    color = '#ffc107'; // Yellow for medium runways
                    radius = 8;
                } else {
                    color = '#dc3545'; // Red for short runways
                    radius = 6;
                }
            } else {
                color = '#6c757d'; // Gray for unknown
                radius = 4;
            }
        } else if (legendMode === 'country') {
            const icao = airport.ident || '';
            if (icao.startsWith('LF')) {
                color = '#007bff'; // Blue for France
            } else if (icao.startsWith('EG')) {
                color = '#dc3545'; // Red for UK
            } else if (icao.startsWith('ED')) {
                color = '#28a745'; // Green for Germany
            } else {
                color = '#ffc107'; // Yellow for other
            }
            radius = 6;
        } else {
            // Default airport type legend mode
            if (airport.point_of_entry) {
                color = '#28a745'; // Green for border crossing
                radius = 8;
            } else if (airport.has_procedures || (airport.procedures && airport.procedures.length > 0)) {
                color = '#ffc107'; // Yellow for airports with procedures
                radius = 6;
            } else {
                color = '#dc3545'; // Red for airports without procedures
                radius = 6;
            }
        }

        return { color, radius };
    }

    /**
     * Visualize airport markers
     */
    visualizeMarkers(airports) {
        console.log('visualizeMarkers called with', airports?.length, 'airports');
        if (!Array.isArray(airports)) {
            console.warn('airports is not an array:', airports);
            return;
        }

        // Store airports for filtering
        this.chatAirports = airports;
        console.log(`Stored ${this.chatAirports.length} airports for filtering`);

        airports.forEach((airport, index) => {
            // Support both property naming conventions
            const lat = airport.latitude || airport.latitude_deg || airport.lat;
            const lon = airport.longitude || airport.longitude_deg || airport.lon;
            const ident = airport.ident || airport.icao;

            console.log(`Processing airport ${index}:`, ident, 'lat:', lat, 'lon:', lon);

            if (!lat || !lon) {
                console.warn(`Airport ${ident} missing coordinates:`, airport);
                return;
            }

            // Get color based on current legend mode
            const { color, radius } = this.getMarkerColor(airport);

            // Create circle marker (native Leaflet style - more reliable than divIcon)
            const marker = L.circleMarker([lat, lon], {
                radius: radius + 2,  // Slightly larger for visibility
                fillColor: color,
                color: '#ffffff',  // White border
                weight: 3,  // Thicker border
                opacity: 1,
                fillOpacity: 0.9,  // More opaque
                interactive: true,
                pane: 'markerPane',
                zIndexOffset: 1000  // Force to top
            });

            console.log(`Created circleMarker for ${ident} at [${lat}, ${lon}] with color ${color}`);

            // Create popup content
            let popupContent = `<b>${ident || 'Airport'}</b>`;
            if (airport.name) popupContent += `<br>${airport.name}`;
            if (airport.iso_country || airport.country) popupContent += `<br>Country: ${airport.iso_country || airport.country}`;
            if (airport.segment_distance_nm !== undefined) {
                popupContent += `<br><strong>Distance from route:</strong> ${airport.segment_distance_nm.toFixed(1)}nm`;
            }

            marker.bindPopup(popupContent);

            // Add click handler to show airport details panel
            marker.on('click', () => {
                if (window.airportMap && typeof window.airportMap.onAirportClick === 'function') {
                    console.log(`Chat marker clicked for ${ident}, calling airportMap.onAirportClick`);
                    window.airportMap.onAirportClick(airport);
                } else {
                    console.warn('airportMap.onAirportClick not available');
                }
            });

            this.chatLayers.addLayer(marker);
            this.chatMarkers.push(marker);
            this.chatMarkersData.push({ marker, airport }); // Store for updates
            console.log(`Added marker for ${ident} to chatLayers. Layer has ${this.chatLayers.getLayers().length} layers total`);
        });

        console.log(`Total markers added: ${this.chatMarkers.length}`);
        console.log(`chatLayers total layers: ${this.chatLayers.getLayers().length}`);
        console.log('chatLayers is on map?', this.map.hasLayer(this.chatLayers));
        console.log('chatLayers object:', this.chatLayers);

        // Debug: Check if first marker is on the map
        if (this.chatMarkers.length > 0) {
            const firstMarker = this.chatMarkers[0];
            console.log('First marker:', firstMarker);
            console.log('First marker _latlng:', firstMarker._latlng);
            console.log('First marker options:', firstMarker.options);
        }

        // Fit map to show all markers
        if (this.chatMarkers.length > 0) {
            const group = L.featureGroup(this.chatMarkers);
            const bounds = group.getBounds();
            console.log('Bounds of markers:', bounds);
            this.map.fitBounds(bounds.pad(0.1));
            console.log('Map bounds fitted to markers');
            console.log('Current map zoom:', this.map.getZoom());
            console.log('Current map center:', this.map.getCenter());
        }
    }

    /**
     * Update marker colors based on current legend mode
     * Called when legend mode is switched
     */
    updateMarkerColors() {
        console.log('Updating chat marker colors for new legend mode...');

        if (!this.chatMarkersData || this.chatMarkersData.length === 0) {
            console.log('No chat markers to update');
            return;
        }

        this.chatMarkersData.forEach(({ marker, airport }) => {
            const { color, radius } = this.getMarkerColor(airport);

            // Update marker style
            marker.setStyle({
                radius: radius + 2,
                fillColor: color,
                color: '#ffffff',
                weight: 3,
                opacity: 1,
                fillOpacity: 0.9
            });

            console.log(`Updated marker for ${airport.ident} to color ${color}`);
        });

        console.log(`Updated ${this.chatMarkersData.length} chat markers`);
    }

    /**
     * Update visualization to show only filtered airports
     * Called when filters are applied to chatbot results
     */
    updateVisualizationWithFilteredAirports(filteredAirports) {
        console.log('Updating chatbot visualization with filtered airports:', filteredAirports.length);

        // Clear current markers (but keep the route line if present)
        const routeLine = this.chatLayers.getLayers().find(layer => layer instanceof L.Polyline);

        // Clear all layers
        this.chatLayers.clearLayers();
        this.chatMarkers = [];
        this.chatMarkersData = [];

        // Re-add route line if it existed
        if (routeLine) {
            this.chatLayers.addLayer(routeLine);
            console.log('Preserved route line');
        }

        // Re-visualize only the filtered airports
        this.visualizeMarkers(filteredAirports);

        console.log(`Chatbot visualization updated with ${filteredAirports.length} filtered airports`);
    }

    /**
     * Clear all chat visualizations
     */
    clearChatVisualizations() {
        console.log('Clearing chat visualizations...');
        console.log('chatLayers before clear - layers:', this.chatLayers.getLayers().length, 'on map?', this.map.hasLayer(this.chatLayers));
        this.chatLayers.clearLayers();
        this.chatMarkers = [];
        this.chatMarkersData = []; // Clear marker data too
        this.currentVisualization = null;
        this.isFilteredMode = false;
        this.chatAirports = [];
        console.log('chatLayers after clear - layers:', this.chatLayers.getLayers().length, 'on map?', this.map.hasLayer(this.chatLayers));
    }

    /**
     * Hide all other airports on the map (show only chat results)
     */
    hideOtherAirports() {
        if (window.airportMap && window.airportMap.airportLayer && window.airportMap.map) {
            // Remove the airport layer from the map
            window.airportMap.airportLayer.remove();
            this.isFilteredMode = true;
            console.log('Hidden other airports - showing only chat results');
        }
    }

    /**
     * Show all airports again (restore normal view)
     */
    showAllAirports() {
        console.log('Restoring all airports view...');

        if (window.airportMap && window.airportMap.airportLayer && window.airportMap.map) {
            // Add the airport layer back to the map
            window.airportMap.airportLayer.addTo(window.airportMap.map);
            this.isFilteredMode = false;
            console.log('Restored all airports view');
        } else {
            console.warn('Airport map or layer not available');
        }
    }

}

// Global instance (will be initialized in app.js)
let chatMapIntegration = null;

function initChatMapIntegration(map) {
    chatMapIntegration = new ChatMapIntegration(map);
    console.log('Chat-Map integration initialized');
    return chatMapIntegration;
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { ChatMapIntegration, initChatMapIntegration };
}
