package me.zhaoqian.flyfun.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import me.zhaoqian.flyfun.ui.map.MapScreen
import me.zhaoqian.flyfun.ui.chat.ChatScreen

/**
 * Main app composable with navigation.
 */
@Composable
fun FlyFunApp() {
    val navController = rememberNavController()
    var currentScreen by remember { mutableStateOf("map") }
    
    Scaffold(
        floatingActionButton = {
            FloatingActionButton(
                onClick = {
                    if (currentScreen == "map") {
                        currentScreen = "chat"
                        navController.navigate("chat") {
                            launchSingleTop = true
                            restoreState = true
                            popUpTo(navController.graph.startDestinationId) {
                                saveState = true
                            }
                        }
                    } else {
                        currentScreen = "map"
                        navController.navigate("map") {
                            launchSingleTop = true
                            restoreState = true
                            popUpTo(navController.graph.startDestinationId) {
                                saveState = true
                            }
                        }
                    }
                },
                containerColor = androidx.compose.ui.graphics.Color(0xFF4285F4), // Google blue
                contentColor = androidx.compose.ui.graphics.Color.White,
                modifier = Modifier.padding(bottom = 72.dp)
            ) {
                Icon(
                    imageVector = if (currentScreen == "map") Icons.Default.Chat else Icons.Default.Map,
                    contentDescription = if (currentScreen == "map") "Open Assistant" else "Open Map"
                )
            }
        }
    ) { _ ->
        NavHost(
            navController = navController,
            startDestination = "map",
            modifier = Modifier.fillMaxSize()
        ) {
            composable("map") {
                currentScreen = "map"
                MapScreen(
                    onNavigateToChat = {
                        currentScreen = "chat"
                        navController.navigate("chat") {
                            launchSingleTop = true
                            restoreState = true
                            popUpTo(navController.graph.startDestinationId) {
                                saveState = true
                            }
                        }
                    }
                )
            }
            composable("chat") {
                currentScreen = "chat"
                ChatScreen(
                    onNavigateToMap = {
                        currentScreen = "map"
                        navController.navigate("map") {
                            launchSingleTop = true
                            restoreState = true
                            popUpTo(navController.graph.startDestinationId) {
                                saveState = true
                            }
                        }
                    }
                )
            }
        }
    }
}
