# FlyFunBrief

iOS app for reviewing ForeFlight briefings with NOTAM management.

## Setup

### 1. Create Xcode Project

Create a new Xcode project:
- **Template**: iOS App
- **Product Name**: FlyFunBrief
- **Bundle Identifier**: `com.ro-z.flyfunbrief`
- **Interface**: SwiftUI
- **Language**: Swift
- **Minimum iOS Version**: iOS 26.0

### 2. Add Share Extension Target

1. File > New > Target
2. Select **Share Extension**
3. **Product Name**: FlyFunBriefShare
4. **Bundle Identifier**: `com.ro-z.flyfunbrief.share`

### 3. Configure App Group

1. Select the main app target
2. Go to Signing & Capabilities
3. Add **App Groups** capability
4. Create group: `group.com.ro-z.flyfunbrief`
5. Repeat for the Share Extension target

### 4. Add Package Dependencies

Add the following Swift Package:
- **RZFlight**: `https://github.com/roznet/rzflight` (branch: main)

Add via CocoaPods (Podfile):
```ruby
pod 'FMDB'
```

### 5. Add Source Files

Copy all `.swift` files from this directory structure into the Xcode project.

### 6. Configure Secrets

1. Copy `Resources/secrets.json.sample` to `Resources/secrets.json`
2. Update the `api_base_url` to point to your server

## Architecture

```
FlyFunBrief/
├── App/
│   ├── FlyFunBriefApp.swift       # App entry point
│   ├── State/
│   │   ├── AppState.swift          # Composed state object
│   │   └── Domains/                # Domain-specific state
│   │       ├── BriefingDomain.swift
│   │       ├── NotamDomain.swift
│   │       ├── NavigationDomain.swift
│   │       └── SettingsDomain.swift
│   ├── Services/
│   │   └── BriefingService.swift   # API communication
│   ├── Data/
│   │   └── AnnotationStore.swift   # SQLite persistence
│   ├── Models/
│   │   └── NotamAnnotation.swift   # User annotation model
│   └── Config/
│       └── SecretsManager.swift    # Configuration loading
└── UserInterface/
    ├── Views/
    │   ├── iPhone/
    │   ├── iPad/
    │   ├── NotamList/
    │   ├── NotamDetail/
    │   ├── Filters/
    │   ├── Import/
    │   └── Settings/
    └── Components/
        └── CategoryChip.swift
```

## API Endpoint

The app requires the briefing API endpoint at `/api/briefing/parse`.

Start the server:
```bash
cd /path/to/flyfun-apps/main
source venv/bin/activate
cd web/server
uvicorn main:app --reload
```

Test the endpoint:
```bash
curl -X POST "http://localhost:8000/api/briefing/parse" \
  -F "file=@test_briefing.pdf" \
  -H "Content-Type: multipart/form-data"
```

## Features

- Import ForeFlight briefing PDFs via share sheet
- View and filter NOTAMs by airport, category, status
- Mark NOTAMs as read/important/ignored
- Add text notes to NOTAMs
- View NOTAM location on map (when coordinates available)
- iPhone and iPad optimized layouts
