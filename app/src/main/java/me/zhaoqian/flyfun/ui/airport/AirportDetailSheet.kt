package me.zhaoqian.flyfun.ui.airport

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import me.zhaoqian.flyfun.data.models.*
import me.zhaoqian.flyfun.ui.theme.*

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun AirportDetailSheet(
    airport: Airport,
    airportDetail: AirportDetail?,
    aipEntries: List<AipEntry>,
    countryRules: CountryRulesResponse?,
    gaSummary: GADetailedSummary?,
    selectedPersona: String,
    onPersonaChange: (String) -> Unit,
    onDismiss: () -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val tabs = listOf("Details", "AIP Data", "Rules", "Relevance")
    
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 32.dp)
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = airport.name ?: airport.icao,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "${airport.icao} • ${airport.country ?: "Unknown"}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            
            // GA badge removed - field no longer exists in API
        }
        
        // Tabs
        TabRow(selectedTabIndex = selectedTab) {
            tabs.forEachIndexed { index, title ->
                Tab(
                    selected = selectedTab == index,
                    onClick = { selectedTab = index },
                    text = { Text(title) }
                )
            }
        }
        
        // Tab content
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 300.dp, max = 500.dp)
        ) {
            when (selectedTab) {
                0 -> DetailsTab(airport, airportDetail)
                1 -> AipDataTab(aipEntries)
                2 -> RulesTab(countryRules)
                3 -> RelevanceTab(gaSummary, selectedPersona, onPersonaChange)
            }
        }
    }
}

@Composable
private fun ScoreBadge(score: Double) {
    val (color, label) = when {
        score >= 0.8 -> ScoreExcellent to "Excellent"
        score >= 0.6 -> ScoreGood to "Good"
        score >= 0.4 -> ScoreModerate to "Moderate"
        else -> ScorePoor to "Poor"
    }
    
    Surface(
        shape = MaterialTheme.shapes.small,
        color = color.copy(alpha = 0.2f)
    ) {
        Text(
            text = "${(score * 100).toInt()}% $label",
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelMedium,
            color = color
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DetailsTab(airport: Airport, detail: AirportDetail?) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Links section - always show with EuroGA and Airfield Directory at minimum
        item {
            DetailSection(title = "Links") {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    detail?.homeLink?.let { link ->
                        LinkChip(
                            text = "Home Page",
                            icon = Icons.Default.Home,
                            color = MaterialTheme.colorScheme.primary,
                            url = link
                        )
                    }
                    detail?.wikipediaLink?.let { link ->
                        LinkChip(
                            text = "Wikipedia",
                            icon = Icons.Default.Info,
                            color = Color(0xFFFF9800), // Orange
                            url = link
                        )
                    }
                    // Always show EuroGA link
                    LinkChip(
                        text = "EuroGA",
                        icon = Icons.Default.Flight,
                        color = Color(0xFF4CAF50), // Green
                        url = "https://airports.euroga.org/search.php?icao=${airport.icao}"
                    )
                    // Always show Airfield Directory link
                    LinkChip(
                        text = "Airfield Directory",
                        icon = Icons.Default.Flight,
                        color = Color(0xFF4CAF50), // Green
                        url = "https://airfield.directory/airfield/${airport.icao}"
                    )
                    // Nearby Restaurants if we have coordinates
                    if (airport.latitude != null && airport.longitude != null) {
                        LinkChip(
                            text = "Nearby Restaurants",
                            icon = Icons.Default.Restaurant,
                            color = Color(0xFFF44336), // Red
                            url = "https://www.google.com/maps/search/restaurants/@${airport.latitude},${airport.longitude},14z"
                        )
                    }
                }
            }
        }
        
        // Basic Information section - matching web UI order
        item {
            DetailSection(title = "Basic Information") {
                InfoRow("ICAO:", airport.icao)
                airport.name?.let { InfoRow("Name:", it) }
                detail?.iataCode?.let { InfoRow("IATA:", it) }
                detail?.type?.let { InfoRow("Type:", it.replace("_", " ")) }
                airport.country?.let { InfoRow("Country:", it) }
                detail?.region?.let { InfoRow("Region:", it) }
                detail?.municipality?.let { InfoRow("Municipality:", it) }
                ?: airport.municipality?.let { InfoRow("Municipality:", it) }
                val lat = airport.latitude ?: detail?.latitude
                val lon = airport.longitude ?: detail?.longitude
                if (lat != null && lon != null) {
                    InfoRow("Coordinates:", "${String.format("%.4f", lat)}, ${String.format("%.4f", lon)}")
                }
                detail?.elevationFt?.let { InfoRow("Elevation:", "${it.toInt()} ft") }
            }
        }
        
        // Runways section
        detail?.runways?.let { runways ->
            if (runways.isNotEmpty()) {
                item {
                    DetailSection(title = "Runways (${runways.size})") {
                        runways.forEach { runway ->
                            RunwayCard(runway)
                            Spacer(modifier = Modifier.height(8.dp))
                        }
                    }
                }
            }
        }
        
        // Procedures section with colorful chips
        detail?.procedures?.let { procedures ->
            if (procedures.isNotEmpty()) {
                item {
                    DetailSection(title = "Procedures (${procedures.size})") {
                        procedures.groupBy { it.type ?: it.procedureType ?: "Other" }.forEach { (type, procs) ->
                            Text(
                                text = "$type (${procs.size})",
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.Medium,
                                modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                            )
                            FlowRow(
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                procs.forEach { proc ->
                                    val procName = proc.name ?: "Unknown"
                                    // Colorful chips based on procedure type
                                    val chipColor = when {
                                        procName.contains("ILS") -> Color(0xFF4CAF50) // Green
                                        procName.contains("RNP") -> MaterialTheme.colorScheme.primary
                                        procName.contains("VOR") -> Color(0xFF9C27B0) // Purple
                                        else -> MaterialTheme.colorScheme.surfaceVariant
                                    }
                                    val textColor = if (chipColor == MaterialTheme.colorScheme.surfaceVariant) 
                                        MaterialTheme.colorScheme.onSurfaceVariant else Color.White
                                    
                                    Surface(
                                        shape = MaterialTheme.shapes.small,
                                        color = chipColor
                                    ) {
                                        Text(
                                            text = procName,
                                            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                            style = MaterialTheme.typography.labelMedium,
                                            color = textColor
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Data Sources section
        detail?.sources?.let { sources ->
            if (sources.isNotEmpty()) {
                item {
                    DetailSection(title = "Data Sources") {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            sources.forEach { source ->
                                Surface(
                                    shape = MaterialTheme.shapes.small,
                                    color = MaterialTheme.colorScheme.surfaceVariant
                                ) {
                                    Text(
                                        text = source,
                                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                                        style = MaterialTheme.typography.labelMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LinkChip(text: String, icon: ImageVector, color: Color, url: String? = null) {
    val uriHandler = LocalUriHandler.current
    
    Surface(
        modifier = Modifier.clickable(enabled = url != null) {
            url?.let { uriHandler.openUri(it) }
        },
        shape = MaterialTheme.shapes.small,
        border = BorderStroke(1.dp, color),
        color = Color.Transparent
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(16.dp))
            Text(text, color = color, style = MaterialTheme.typography.labelMedium)
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.width(120.dp)
        )
        Text(
            text = value,
            modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun DetailSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(bottom = 8.dp)
        )
        content()
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun RunwayCard(runway: Runway) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column {
                Text(runway.identifier ?: "RWY", fontWeight = FontWeight.Bold)
                runway.surface?.let { 
                    Text(it, style = MaterialTheme.typography.bodySmall) 
                }
            }
            Column(horizontalAlignment = Alignment.End) {
                runway.lengthFt?.let { Text("${it.toInt()} ft") }
                if (runway.isLighted) {
                    Text("Lighted", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun AipDataTab(aipEntries: List<AipEntry>) {
    var filterQuery by remember { mutableStateOf("") }
    
    if (aipEntries.isEmpty()) {
        EmptyTabContent("No AIP data available")
    } else {
        Column(modifier = Modifier.fillMaxSize()) {
            // Filter field
            OutlinedTextField(
                value = filterQuery,
                onValueChange = { filterQuery = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text("Filter AIP entries...") },
                singleLine = true,
                trailingIcon = {
                    if (filterQuery.isNotEmpty()) {
                        IconButton(onClick = { filterQuery = "" }) {
                            Icon(Icons.Default.Close, contentDescription = "Clear")
                        }
                    }
                }
            )
            
            // Filter entries based on query
            val filteredEntries = if (filterQuery.isBlank()) {
                aipEntries
            } else {
                aipEntries.filter { entry ->
                    entry.value.contains(filterQuery, ignoreCase = true) ||
                    entry.section.contains(filterQuery, ignoreCase = true) ||
                    entry.field.contains(filterQuery, ignoreCase = true)
                }
            }
            
            // Group by section
            val grouped = filteredEntries.groupBy { it.section }
            
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                grouped.forEach { (section, entries) ->
                    item(key = section) {
                        ExpandableAipSection(
                            sectionName = section,
                            entries = entries
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ExpandableAipSection(
    sectionName: String,
    entries: List<AipEntry>
) {
    var expanded by remember { mutableStateOf(false) }
    
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        )
    ) {
        Column {
            // Header (clickable to expand/collapse)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { expanded = !expanded }
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = if (expanded) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowRight,
                        contentDescription = if (expanded) "Collapse" else "Expand",
                        tint = MaterialTheme.colorScheme.primary
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "$sectionName (${entries.size})",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
            
            // Expanded content - filter out entries with empty value
            if (expanded) {
                Column(
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    entries.filter { it.value.isNotBlank() }.forEach { entry ->
                        AipEntryCard(entry)
                    }
                }
            }
        }
    }
}

@Composable
private fun AipEntryCard(entry: AipEntry) {
    val primaryColor = MaterialTheme.colorScheme.primary
    
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .drawBehind {
                // Draw left blue border
                drawRect(
                    color = primaryColor,
                    topLeft = Offset.Zero,
                    size = Size(4.dp.toPx(), size.height)
                )
            },
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 1.dp
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 12.dp, end = 12.dp, top = 10.dp, bottom = 10.dp)
        ) {
            // Format: "Title: Content" using field and value
            if (entry.field.isNotBlank()) {
                Text(
                    text = buildAnnotatedString {
                        withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                            append(entry.field)
                            append(": ")
                        }
                        append(entry.value)
                    },
                    style = MaterialTheme.typography.bodyMedium
                )
            } else {
                Text(
                    text = entry.value,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RulesTab(countryRules: CountryRulesResponse?) {
    if (countryRules == null || countryRules.categories.isEmpty()) {
        EmptyTabContent("No rules data available")
    } else {
        // Filter state
        var filterQuery by remember { mutableStateOf("") }
        val expandedCategories = remember { mutableStateMapOf<String, Boolean>() }
        
        // Filter categories and rules based on query
        val filteredCategories = if (filterQuery.isBlank()) {
            countryRules.categories
        } else {
            countryRules.categories.mapNotNull { category ->
                val filteredRules = category.rules.filter { rule ->
                    rule.questionText?.contains(filterQuery, ignoreCase = true) == true ||
                    rule.answerHtml?.contains(filterQuery, ignoreCase = true) == true ||
                    rule.tags.any { it.contains(filterQuery, ignoreCase = true) } ||
                    category.name.contains(filterQuery, ignoreCase = true)
                }
                if (filteredRules.isNotEmpty() || category.name.contains(filterQuery, ignoreCase = true)) {
                    category.copy(rules = filteredRules, count = filteredRules.size)
                } else null
            }
        }
        
        Column(modifier = Modifier.fillMaxSize()) {
            // Header with stats
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    text = "Rules for ${countryRules.country}: ${countryRules.totalRules} answers across ${countryRules.categories.size} categories.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                
                Spacer(modifier = Modifier.height(12.dp))
                
                // Filter input
                OutlinedTextField(
                    value = filterQuery,
                    onValueChange = { filterQuery = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text("Filter rules by question, answer, tag, or category...") },
                    singleLine = true,
                    trailingIcon = {
                        if (filterQuery.isNotEmpty()) {
                            IconButton(onClick = { filterQuery = "" }) {
                                Icon(Icons.Default.Close, contentDescription = "Clear")
                            }
                        }
                    }
                )
            }
            
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
            
            filteredCategories.forEach { category ->
                val isExpanded = expandedCategories[category.name] ?: false
                
                // Category header (expandable)
                item {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { expandedCategories[category.name] = !isExpanded },
                        color = MaterialTheme.colorScheme.surfaceVariant,
                        shape = MaterialTheme.shapes.small
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.SpaceBetween,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowRight,
                                    contentDescription = if (isExpanded) "Collapse" else "Expand",
                                    modifier = Modifier.size(20.dp)
                                )
                                Text(
                                    text = "${category.name} (${category.count})",
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    }
                }
                
                // Rules in this category (only if expanded)
                if (isExpanded) {
                    items(category.rules) { rule ->
                        RuleEntryCard(rule)
                    }
                }
            }
        }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RuleEntryCard(rule: RuleEntry) {
    val uriHandler = LocalUriHandler.current
    
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        ),
        elevation = CardDefaults.cardElevation(defaultElevation = 1.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            // Question with gavel icon
            rule.questionText?.let {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Gavel,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(16.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
            }
            
            // Answer (HTML stripped)
            rule.answerHtml?.let {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = it.replace(Regex("<[^>]*>"), ""), // Strip HTML tags
                    style = MaterialTheme.typography.bodyMedium
                )
            }
            
            // Tags
            if (rule.tags.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    rule.tags.forEach { tag ->
                        Surface(
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.secondaryContainer
                        ) {
                            Text(
                                text = tag,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSecondaryContainer
                            )
                        }
                    }
                }
            }
            
            // Links
            if (rule.links.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Default.Link,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(14.dp)
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    rule.links.forEach { link ->
                        Text(
                            text = try { 
                                java.net.URI(link).host?.removePrefix("www.") ?: link 
                            } catch (e: Exception) { link },
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .clickable { uriHandler.openUri(link) }
                                .padding(end = 8.dp)
                        )
                    }
                }
            }
            
            // Metadata (last reviewed, confidence)
            val metaParts = mutableListOf<String>()
            rule.lastReviewed?.let { metaParts.add("Last reviewed: $it") }
            rule.confidence?.let { metaParts.add("Confidence: $it") }
            
            if (metaParts.isNotEmpty()) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = metaParts.joinToString(" • "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RelevanceTab(
    gaSummary: GADetailedSummary?,
    selectedPersona: String,
    onPersonaChange: (String) -> Unit
) {
    if (gaSummary == null || !gaSummary.hasData) {
        EmptyTabContent("No GA friendliness data available")
        return
    }
    
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // Overall Score Section
        item {
            RelevanceSection(title = "Overall Score", icon = Icons.Default.Star) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // Large score badge with gradient
                    gaSummary.score?.let { score ->
                        val scoreColor = getScoreColor(score)
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = scoreColor
                        ) {
                            Text(
                                text = "${(score * 100).toInt()}%",
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.headlineMedium,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                    
                    // Review count info
                    Column {
                        Text(
                            text = "Based on ${gaSummary.reviewCount} review${if (gaSummary.reviewCount != 1) "s" else ""}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
        
        // Feature Breakdown Section
        gaSummary.features?.let { features ->
            if (features.isNotEmpty()) {
                item {
                    RelevanceSection(title = "Feature Breakdown", icon = Icons.Default.BarChart) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            features.forEach { (featureName, value) ->
                                val displayName = featureName.replace("_", " ")
                                    .replace("ga ", "")
                                    .replaceFirstChar { it.uppercase() }
                                val percentage = value?.let { (it * 100).toInt() } ?: 0
                                val barColor = value?.let { getScoreColor(it) } ?: MaterialTheme.colorScheme.surfaceVariant
                                
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text(
                                        text = displayName,
                                        modifier = Modifier.weight(0.4f),
                                        style = MaterialTheme.typography.bodySmall,
                                        fontWeight = FontWeight.Medium
                                    )
                                    Box(
                                        modifier = Modifier
                                            .weight(0.45f)
                                            .height(8.dp)
                                            .background(
                                                MaterialTheme.colorScheme.surfaceVariant,
                                                RoundedCornerShape(4.dp)
                                            )
                                    ) {
                                        Box(
                                            modifier = Modifier
                                                .fillMaxHeight()
                                                .fillMaxWidth(fraction = (value ?: 0.0).toFloat().coerceIn(0f, 1f))
                                                .background(barColor, RoundedCornerShape(4.dp))
                                        )
                                    }
                                    Text(
                                        text = if (value != null) "$percentage%" else "N/A",
                                        modifier = Modifier.weight(0.15f),
                                        style = MaterialTheme.typography.labelSmall,
                                        textAlign = TextAlign.End
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Tags Section
        gaSummary.tags?.let { tags ->
            if (tags.isNotEmpty()) {
                item {
                    RelevanceSection(title = "Review Tags", icon = Icons.Default.Label) {
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            tags.forEach { tag ->
                                Surface(
                                    shape = MaterialTheme.shapes.small,
                                    color = MaterialTheme.colorScheme.secondaryContainer
                                ) {
                                    Text(
                                        text = tag,
                                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Summary Section
        gaSummary.summaryText?.let { summary ->
            item {
                RelevanceSection(title = "Summary", icon = Icons.Default.FormatQuote) {
                    Text(
                        text = summary,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        
        // Requirements Section (hassle level, notification)
        if (gaSummary.hassleLevel != null || gaSummary.notificationSummary != null) {
            item {
                RelevanceSection(title = "Requirements", icon = Icons.Default.Assignment) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        gaSummary.hassleLevel?.let { 
                            Text("Hassle Level: $it", fontWeight = FontWeight.Medium)
                        }
                        gaSummary.notificationSummary?.let {
                            Text(
                                text = it,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }
        
        // Amenities Section (hotel, restaurant)
        if (gaSummary.hotelInfo != null || gaSummary.restaurantInfo != null) {
            item {
                RelevanceSection(title = "Amenities", icon = Icons.Default.Hotel) {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        gaSummary.hotelInfo?.let { 
                            Text("🏨 $it", style = MaterialTheme.typography.bodySmall)
                        }
                        gaSummary.restaurantInfo?.let {
                            Text("🍽️ $it", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun RelevanceSection(
    title: String,
    icon: ImageVector,
    content: @Composable ColumnScope.() -> Unit
) {
    Column {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(bottom = 8.dp)
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp)
            )
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.Bold
            )
        }
        content()
    }
}

private fun getScoreColor(score: Double): Color {
    return when {
        score >= 0.75 -> Color(0xFF27AE60) // Green
        score >= 0.50 -> Color(0xFF3498DB) // Blue
        score >= 0.25 -> Color(0xFFF39C12) // Orange
        else -> Color(0xFFE74C3C) // Red
    }
}

@Composable
private fun EmptyTabContent(message: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
