package me.zhaoqian.flyfun.ui.map

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import me.zhaoqian.flyfun.viewmodel.AirportFilters

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FiltersDialog(
    currentFilters: AirportFilters,
    onApply: (AirportFilters) -> Unit,
    onClear: () -> Unit,
    onDismiss: () -> Unit
) {
    var filters by remember { mutableStateOf(currentFilters) }
    var showAdvanced by remember { mutableStateOf(false) }
    
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Filter Airports") },
        text = {
            Column(
                modifier = Modifier
                    .verticalScroll(rememberScrollState())
                    .padding(vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Search field
                OutlinedTextField(
                    value = filters.searchQuery ?: "",
                    onValueChange = { filters = filters.copy(searchQuery = it.ifBlank { null }) },
                    label = { Text("Search") },
                    placeholder = { Text("Airport name or ICAO") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                
                // Country filter
                OutlinedTextField(
                    value = filters.country ?: "",
                    onValueChange = { filters = filters.copy(country = it.uppercase().ifBlank { null }) },
                    label = { Text("Country Code") },
                    placeholder = { Text("e.g., DE, FR, IT") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                
                // Procedure type dropdown
                var procedureExpanded by remember { mutableStateOf(false) }
                val procedureOptions = listOf("", "ILS", "VOR", "NDB", "RNAV", "VISUAL")
                
                ExposedDropdownMenuBox(
                    expanded = procedureExpanded,
                    onExpandedChange = { procedureExpanded = !procedureExpanded }
                ) {
                    OutlinedTextField(
                        value = filters.procedureType ?: "Any",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Procedure Type") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = procedureExpanded) },
                        modifier = Modifier
                            .menuAnchor()
                            .fillMaxWidth()
                    )
                    ExposedDropdownMenu(
                        expanded = procedureExpanded,
                        onDismissRequest = { procedureExpanded = false }
                    ) {
                        procedureOptions.forEach { option ->
                            DropdownMenuItem(
                                text = { Text(option.ifBlank { "Any" }) },
                                onClick = {
                                    filters = filters.copy(procedureType = option.ifBlank { null })
                                    procedureExpanded = false
                                }
                            )
                        }
                    }
                }
                
                // Runway minimum length
                OutlinedTextField(
                    value = filters.runwayMinLength?.toString() ?: "",
                    onValueChange = { 
                        filters = filters.copy(runwayMinLength = it.toIntOrNull()) 
                    },
                    label = { Text("Min Runway Length (ft)") },
                    placeholder = { Text("e.g., 3000") },
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true
                )
                
                // Quick Filters Section
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                Text(
                    text = "Quick Filters",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold
                )
                
                // Quick Filters - Row 1
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    GridFilterCheckbox(
                        checked = filters.hasProcedures == true,
                        onCheckedChange = { filters = filters.copy(hasProcedures = if (it) true else null) },
                        label = "Procedures",
                        modifier = Modifier.weight(1f)
                    )
                    GridFilterCheckbox(
                        checked = filters.hasAipData == true,
                        onCheckedChange = { filters = filters.copy(hasAipData = if (it) true else null) },
                        label = "AIP Data",
                        modifier = Modifier.weight(1f)
                    )
                }
                
                // Quick Filters - Row 2
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    GridFilterCheckbox(
                        checked = filters.hasHardRunway == true,
                        onCheckedChange = { filters = filters.copy(hasHardRunway = if (it) true else null) },
                        label = "Hard Runway",
                        modifier = Modifier.weight(1f)
                    )
                    GridFilterCheckbox(
                        checked = filters.hasIls == true,
                        onCheckedChange = { filters = filters.copy(hasIls = if (it) true else null) },
                        label = "ILS Approach",
                        modifier = Modifier.weight(1f)
                    )
                }
                
                // Quick Filters - Row 3
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    GridFilterCheckbox(
                        checked = filters.pointOfEntry == true,
                        onCheckedChange = { filters = filters.copy(pointOfEntry = if (it) true else null) },
                        label = "Border Crossing",
                        modifier = Modifier.weight(1f)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                }
                
                // Advanced AIP Filters Section
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .toggleable(
                            value = showAdvanced,
                            onValueChange = { showAdvanced = it },
                            role = Role.Button
                        )
                        .padding(vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "⚙️ Advanced AIP Filters",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = if (showAdvanced) "▲" else "▼",
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
                
                if (showAdvanced) {
                    Text(
                        text = "Facility Filters:",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    
                    // Facility Filters - Row 1
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        GridFilterCheckbox(
                            checked = filters.hasHotels == true,
                            onCheckedChange = { filters = filters.copy(hasHotels = if (it) true else null) },
                            label = "Hotels",
                            modifier = Modifier.weight(1f)
                        )
                        GridFilterCheckbox(
                            checked = filters.hasRestaurants == true,
                            onCheckedChange = { filters = filters.copy(hasRestaurants = if (it) true else null) },
                            label = "Restaurants",
                            modifier = Modifier.weight(1f)
                        )
                    }
                    
                    // Facility Filters - Row 2
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        GridFilterCheckbox(
                            checked = filters.hasAvgas == true,
                            onCheckedChange = { filters = filters.copy(hasAvgas = if (it) true else null) },
                            label = "AVGAS",
                            modifier = Modifier.weight(1f)
                        )
                        GridFilterCheckbox(
                            checked = filters.hasJetA == true,
                            onCheckedChange = { filters = filters.copy(hasJetA = if (it) true else null) },
                            label = "Jet A",
                            modifier = Modifier.weight(1f)
                        )
                    }
                    
                    // Facility Filters - Row 3
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        GridFilterCheckbox(
                            checked = filters.hasCustoms == true,
                            onCheckedChange = { filters = filters.copy(hasCustoms = if (it) true else null) },
                            label = "Customs",
                            modifier = Modifier.weight(1f)
                        )
                        GridFilterCheckbox(
                            checked = filters.hasDeicing == true,
                            onCheckedChange = { filters = filters.copy(hasDeicing = if (it) true else null) },
                            label = "De-icing",
                            modifier = Modifier.weight(1f)
                        )
                    }
                    
                    // Facility Filters - Row 4
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        GridFilterCheckbox(
                            checked = filters.hasHangar == true,
                            onCheckedChange = { filters = filters.copy(hasHangar = if (it) true else null) },
                            label = "Hangar",
                            modifier = Modifier.weight(1f)
                        )
                        Spacer(modifier = Modifier.weight(1f))
                    }
                }
            }
        },
        confirmButton = {
            Button(onClick = { onApply(filters) }) {
                Text("Apply")
            }
        },
        dismissButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onClear) {
                    Text("Clear All")
                }
                TextButton(onClick = onDismiss) {
                    Text("Cancel")
                }
            }
        }
    )
}

@Composable
private fun GridFilterCheckbox(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .toggleable(
                value = checked,
                onValueChange = onCheckedChange,
                role = Role.Checkbox
            )
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = null
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}
