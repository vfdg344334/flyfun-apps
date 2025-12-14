package me.zhaoqian.flyfun.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Airport data models matching the API responses.
 */

@Serializable
data class Airport(
    @SerialName("ident") val icao: String,
    val name: String? = null,
    @SerialName("iso_country") val country: String? = null,
    @SerialName("latitude_deg") val latitude: Double? = null,
    @SerialName("longitude_deg") val longitude: Double? = null,
    val municipality: String? = null,
    @SerialName("point_of_entry") val pointOfEntry: Boolean? = null,
    @SerialName("has_procedures") val hasProcedures: Boolean = false,
    @SerialName("has_runways") val hasRunways: Boolean = false,
    @SerialName("has_aip_data") val hasAipData: Boolean = false,
    @SerialName("has_hard_runway") val hasHardRunway: Boolean = false,
    @SerialName("has_lighted_runway") val hasLightedRunway: Boolean = false,
    @SerialName("has_soft_runway") val hasSoftRunway: Boolean = false,
    @SerialName("has_water_runway") val hasWaterRunway: Boolean = false,
    @SerialName("has_snow_runway") val hasSnowRunway: Boolean = false,
    @SerialName("longest_runway_length_ft") val longestRunwayLengthFt: Int? = null,
    @SerialName("procedure_count") val procedureCount: Int = 0,
    @SerialName("runway_count") val runwayCount: Int = 0,
    @SerialName("aip_entry_count") val aipEntryCount: Int = 0,
    val ga: GASummary? = null
)

@Serializable
data class GASummary(
    @SerialName("has_data") val hasData: Boolean = false,
    val score: Double? = null,
    val features: Map<String, Double?>? = null,
    @SerialName("review_count") val reviewCount: Int = 0,
    val tags: List<String>? = null,
    @SerialName("summary_text") val summaryText: String? = null,
    @SerialName("hassle_level") val hassleLevel: String? = null
)

@Serializable
data class AirportDetail(
    @SerialName("ident") val icao: String,
    val name: String? = null,
    val type: String? = null,
    @SerialName("iso_country") val country: String? = null,
    @SerialName("iso_region") val region: String? = null,
    @SerialName("latitude_deg") val latitude: Double? = null,
    @SerialName("longitude_deg") val longitude: Double? = null,
    @SerialName("elevation_ft") val elevationFt: Double? = null,
    val municipality: String? = null,
    @SerialName("iata_code") val iataCode: String? = null,
    @SerialName("home_link") val homeLink: String? = null,
    @SerialName("wikipedia_link") val wikipediaLink: String? = null,
    val sources: List<String> = emptyList(),
    val runways: List<Runway> = emptyList(),
    val procedures: List<Procedure> = emptyList(),
    @SerialName("aip_entries") val aipEntries: List<AipEntry> = emptyList()
)

@Serializable
data class Runway(
    @SerialName("le_ident") val identifier: String? = null,
    @SerialName("length_ft") val lengthFt: Double? = null,
    @SerialName("width_ft") val widthFt: Double? = null,
    val surface: String? = null,
    val lighted: Int = 0
) {
    val isLighted: Boolean get() = lighted == 1
}

@Serializable
data class Procedure(
    val type: String? = null,
    val name: String? = null,
    val runway: String? = null,
    @SerialName("procedure_type") val procedureType: String? = null
)

@Serializable
data class AipEntry(
    val section: String = "",
    val field: String = "",
    val value: String = "",
    @SerialName("std_field") val stdField: String? = null,
    val source: String? = null
)

@Serializable
data class AirportsResponse(
    val airports: List<Airport>,
    val total: Int,
    val offset: Int,
    val limit: Int
)
