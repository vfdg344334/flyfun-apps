# FlyFun Android App

An Android app for the FlyFun aviation assistant, providing airport information, flight planning, and an AI chatbot for aviation queries.

## Features

- **Interactive Map**: View European airports on OpenStreetMap (no API key needed!)
- **Airport Details**: Detailed information including runways, procedures, and AIP data
- **GA Friendliness**: Scores and summaries for General Aviation friendliness
- **AI Assistant**: Chat with an aviation-focused AI for flight planning help
- **Filters**: Filter airports by country, procedures, runway length, and more
- **Legend Modes**: Color airports by type, procedure precision, runway length, country, or GA relevance

## Setup

### Prerequisites

- Android Studio Hedgehog (2023.1.1) or later
- JDK 17
- Android SDK with API 34

### Configuration

1. Copy `local.properties.example` to `local.properties`
2. Update `API_BASE_URL` with your API server URL

```properties
API_BASE_URL=http://your-server:8000/
```

### Building

```bash
./gradlew assembleDebug
```

### Running

Open the project in Android Studio and run on an emulator or device.

**No API keys required!** The app uses OpenStreetMap via osmdroid.

## Backend API

This app requires the FlyFun API server. For setting up the backend:

👉 **See [flyfun-apps](https://github.com/roznet/flyfun-apps) for API documentation and setup**

The API provides:
- Airport data and search
- Aviation rules by country
- GA friendliness scores
- AI-powered aviation assistant (streaming)

## Architecture

- **Kotlin** with **Jetpack Compose** for UI
- **MVVM** architecture with ViewModels
- **Hilt** for dependency injection
- **Retrofit** for networking
- **osmdroid** for OpenStreetMap display (like Leaflet on web)
- **Kotlinx Serialization** for JSON parsing

## Project Structure

```
app/src/main/java/.../
├── data/
│   ├── api/           # Retrofit API interfaces
│   ├── models/        # Data classes
│   └── repository/    # Data access layer
├── di/                # Hilt modules
├── ui/
│   ├── map/           # Map screen (osmdroid)
│   ├── airport/       # Airport details
│   ├── chat/          # Chat screen
│   └── theme/         # Material 3 theme
├── viewmodel/         # ViewModels
├── FlyFunApplication.kt
└── MainActivity.kt
```

## License

MIT License
