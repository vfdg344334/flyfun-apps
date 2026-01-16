# iOS App UI Layout

> Layout philosophy, iPhone vs iPad, view organization, and shared components.

## Layout Philosophy

**Different UX for different form factors, shared components where possible.**

| Device | Layout Strategy | Primary Navigation |
|--------|----------------|-------------------|
| iPhone | Map-centric with overlays | ZStack layers |
| iPad | Sidebar + detail | NavigationSplitView |

### Why Different Layouts?

- **iPhone** has limited screen space → map should always be visible
- **iPad** has room for persistent sidebar → NavigationSplitView is natural fit
- Same data, different interaction patterns

## iPhone Layout (Compact)

```
┌─────────────────────────────┐
│ [Search...........] [Filter]│  ← Top: Search bar + filter toggle
├─────────────────────────────┤
│                             │
│           MAP               │  ← Always visible (ZStack base)
│      (full screen)          │
│                             │
├─────────────────────────────┤
│ ┌─────────────────────────┐ │  [Legend]  ← Floating buttons
│ │   Chat Overlay          │ │  [Chat]      (bottom-right)
│ │   (resizable)           │ │
│ │   ↕ drag handle         │ │
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

**Key Components:**
- `iPhoneLayoutView` - Root ZStack container
- `iPhoneSearchBar` - Top search with embedded filter button
- `iPhoneFilterOverlay` - Filter panel (appears below search)
- `iPhoneFloatingButtons` - Legend picker + chat toggle
- `iPhoneChatOverlay` - Resizable bottom sheet with drag gesture

**Interaction:**
- Map always visible as background layer
- Search bar at top (hides when chat is open for space)
- Filters appear as overlay, tap outside to dismiss
- Chat slides up from bottom, resizable via drag
- Floating buttons move up when chat is open

## iPad Layout (Regular)

```
┌────────────────┬───────────────────────────────┬──────────────┐
│    SIDEBAR     │             MAP               │  INSPECTOR   │
│                │                               │  (optional)  │
│  Search/Filter │                               │              │
│  or Chat       │                               │  Airport     │
│  or Settings   │      [Search] [Chat] [Legend] │  Details     │
│                │           (floating)          │              │
└────────────────┴───────────────────────────────┴──────────────┘
```

**Key Components:**
- `iPadLayoutView` - NavigationSplitView container
- `SearchFilterSidebar` - Search + filters in sidebar
- `ChatView` - Full chat in sidebar (toggles with search)
- `MapDetailView` - Map as detail pane
- `AirportInspectorView` - Inspector panel when airport selected

**Interaction:**
- Sidebar toggles between search/filters and chat
- Floating buttons toggle sidebar content or visibility
- Inspector appears as trailing column when airport selected
- Chat settings and offline maps stay within sidebar navigation

## View Folder Structure

```
UserInterface/Views/
├── Shared/                    # Cross-platform components
│   ├── FilterBindings.swift   # Filter state bindings with debounced apply
│   └── FloatingActionButton.swift
│
├── iPad/                      # iPad-specific layouts
│   └── iPadLayoutView.swift
│
├── iPhone/                    # iPhone-specific layouts
│   ├── iPhoneLayoutView.swift
│   ├── iPhoneSearchBar.swift
│   ├── iPhoneFilterOverlay.swift
│   ├── iPhoneFloatingButtons.swift
│   └── iPhoneChatOverlay.swift
│
├── Sidebar/                   # iPad sidebar views
│   └── SearchFilterSidebar.swift
│
├── Chat/                      # Chat views (shared)
│   ├── ChatView.swift         # Full chat with navigation
│   ├── ChatContent.swift      # Chat content without chrome (embedded use)
│   ├── ChatSettingsView.swift
│   └── ChatBubble.swift
│
├── Map/                       # Map views (shared)
│   ├── AirportMapView.swift
│   └── MapDetailView.swift
│
├── Airport/                   # Airport detail views (shared)
│   └── AirportInspectorView.swift
│
└── Settings/                  # Settings views
    └── OfflineMapsView.swift
```

## Shared Components

### FilterBindings

Eliminates filter binding duplication between iPad sidebar and iPhone overlay.

```swift
// Usage in any view
@Environment(\.appState) private var state
private var filters: FilterBindings { FilterBindings(state: state) }

var body: some View {
    Toggle("Border Crossing", isOn: filters.pointOfEntry)
    Toggle("AVGAS", isOn: filters.hasAvgas)
    Picker("Country", selection: filters.country) { ... }
}
```

**Features:**
- All filter bindings with automatic debounced apply (300ms)
- `hasActiveFilters` computed property
- `clearAll()` function

### FloatingActionButton

Shared button style for floating action buttons.

```swift
// As a button
FloatingActionButton(
    icon: "magnifyingglass",
    isActive: true,
    activeColor: .blue,
    size: 44
) {
    // action
}

// As a menu label
Menu {
    Picker(...) { ... }
} label: {
    FloatingActionButton(icon: "paintpalette", isActive: true, activeColor: .purple) { }
        .allowsHitTesting(false)
}
```

### ChatContent

Chat UI without navigation chrome, for embedding in overlays.

```swift
// Used by ChatView (iPad - full screen)
ChatContent(compactWelcome: false)

// Used by iPhoneChatOverlay (iPhone - embedded)
ChatContent(compactWelcome: true)
```

## Naming Conventions

| Convention | Example | Reason |
|------------|---------|--------|
| Lowercase 'i' prefix | `iPhoneLayoutView`, `iPadLayoutView` | Apple brand naming |
| Descriptive suffixes | `*Overlay`, `*Sidebar`, `*Content` | Clarifies purpose |
| View suffix | `SearchFilterSidebar` (not `SearchFilterSidebarView`) | SwiftUI convention |

## Component Reuse Strategy

### What to Share

| Component | Why Shared |
|-----------|-----------|
| `FilterBindings` | Same data, same logic, different UI |
| `FloatingActionButton` | Same visual style |
| `ChatContent` | Same chat functionality |
| `AirportMapView` | Same map for both devices |
| `AirportInspectorView` | Same airport details |

### What NOT to Share

| Component | Why Device-Specific |
|-----------|-------------------|
| Layout containers | Different navigation paradigms |
| Search bar | Different styling (overlay vs material) |
| Filter presentation | List sections vs VStack with HStack pickers |

**Rule of thumb:** Share data/logic, specialize presentation.

## ContentView Branching

Root view branches based on size class:

```swift
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .compact {
            iPhoneLayoutView()
        } else {
            iPadLayoutView()
        }
    }
}
```

## Related Documents

- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - State management, domains
- [IOS_APP_MAP.md](IOS_APP_MAP.md) - Map implementation details
- [IOS_APP_CHAT.md](IOS_APP_CHAT.md) - Chat system details
