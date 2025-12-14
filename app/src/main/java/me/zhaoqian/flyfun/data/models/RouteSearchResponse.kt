package me.zhaoqian.flyfun.data.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Response from /api/airports/route-search endpoint.
 * Contains the full list of airports near a route.
 */
@Serializable
data class RouteSearchResponse(
    val airports: List<RouteAirportItem> = emptyList(),
    val route: RouteInfo? = null
)

@Serializable
data class RouteAirportItem(
    val airport: Airport,
    @SerialName("enroute_distance_nm")
    val enrouteDistanceNm: Double? = null
)

@Serializable
data class RouteInfo(
    val from: String? = null,
    val to: String? = null,
    @SerialName("total_distance_nm")
    val totalDistanceNm: Double? = null
)
