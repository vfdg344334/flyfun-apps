# Shared Filter & Legend Specification

> **Authoritative spec for filter/legend parity between web and iOS apps**
>
> This document defines the shared specifications to keep web and iOS implementations in sync.
> Changes to filter logic or legend colors should be reflected here and in both platforms.

## Shared Data Sources

Both platforms use these bundled SQLite databases as the source of truth:

| Database | Content | iOS Service | Web Service |
|----------|---------|-------------|-------------|
| `airports.db` | Airports, runways, procedures, AIP entries | RZFlight KnownAirports | EuroAipModel |
| `ga_notifications.db` | Customs/immigration requirements | NotificationService | NotificationService |
| `ga_persona.db` | GA friendliness (hotel, restaurant, fees) | GAFriendlinessService | GAFriendlinessService |

---

## Notification Legend (12-Condition Cascade)

Both platforms must implement this exact cascade in order:

| # | Condition | Color | Bucket | Hex |
|---|-----------|-------|--------|-----|
| 1 | `is_h24 === true` | Green | h24 | #28a745 |
| 2 | `type='not_available'` | Red | difficult | #dc3545 |
| 3 | `is_on_request === true` | Yellow | moderate | #ffc107 |
| 4 | `type='business_day'` | Blue | hassle | #007bff |
| 5 | `type='as_ad_hours'` | Green | easy | #28a745 |
| 6 | `type='hours'` AND `hours_notice=null` | Green | easy | #28a745 |
| 7 | `hours_notice` is null/undefined | Gray | unknown | #95a5a6 |
| 8 | `hours_notice <= 12` | Green | easy | #28a745 |
| 9 | `hours_notice 13-24` | Yellow | moderate | #ffc107 |
| 10 | `hours_notice 25-48` | Blue | hassle | #007bff |
| 11 | `hours_notice > 48` | Red | difficult | #dc3545 |

### Implementation Reference

**Web (TypeScript):**
```typescript
// web-app/components/map/Legend.tsx - getNotificationColor()
```

**iOS (Swift):**
```swift
// app/FlyFunEuroAIP/App/Models/NotificationInfo.swift
extension NotificationInfo {
    var bucket: NotificationBucket { ... }
}
```

---

## Filter Parameters

### Core Airport Filters (RZFlight/airports.db)

| Filter | Type | iOS Property | Web Property | DB Column |
|--------|------|--------------|--------------|-----------|
| Country | String? | `country` | `country` | `iso_country` |
| Has Procedures | Bool? | `hasProcedures` | `hasProcedures` | procedures table |
| Hard Runway | Bool? | `hasHardRunway` | `hasHardRunway` | runways.surface |
| Lighted Runway | Bool? | `hasLightedRunway` | `hasLightedRunway` | runways.lighted |
| Point of Entry | Bool? | `pointOfEntry` | `pointOfEntry` | border_crossing_points |
| Min Runway (ft) | Int? | `minRunwayLengthFt` | `minRunwayLengthFt` | runways.length_ft |
| Max Runway (ft) | Int? | `maxRunwayLengthFt` | `maxRunwayLengthFt` | runways.length_ft |
| Has ILS | Bool? | `hasILS` | `hasILS` | procedures.approach_type |
| Has RNAV | Bool? | `hasRNAV` | `hasRNAV` | procedures.precision_category |
| Precision Approach | Bool? | `hasPrecisionApproach` | `hasPrecisionApproach` | procedures |
| AIP Field | String? | `aipField` | `aipField` | aip_entries.field |

### Fuel Filters (RZFlight/AIP Entries)

| Filter | Type | iOS Property | Detection Logic |
|--------|------|--------------|-----------------|
| Has AVGAS | Bool? | `hasAvgas` | AIP entries contain "AVGAS" or "100LL" |
| Has Jet-A | Bool? | `hasJetA` | AIP entries contain "JET" or "JETA1" |

### GA Friendliness Filters (ga_persona.db)

| Filter | Type | iOS Property | Web Property | DB Column |
|--------|------|--------------|--------------|-----------|
| Hotel | String? | `hotel` | `hotel` | `aip_hotel_info` |
| Restaurant | String? | `restaurant` | `restaurant` | `aip_restaurant_info` |
| Max Landing Fee | Double? | `maxLandingFee` | `maxLandingFee` | `fee_band_*` columns |

**Hospitality Values:**
- `"vicinity"` = nearby or at airport (DB values 1 or 2)
- `"atAirport"` = at airport only (DB value 2)

### Size Filters

| Filter | Type | iOS Property | Logic |
|--------|------|--------------|-------|
| Exclude Large | Bool? | `excludeLargeAirports` | Max runway < 8000ft |

---

## Legend Mode Colors

### Airport Type Legend

| Category | Color | iOS | Web |
|----------|-------|-----|-----|
| Border Crossing | Purple | `.purple` | `#800080` |
| IFR Airport | Blue | `.blue` | `#0000ff` |
| VFR Airport | Green | `.green` | `#00ff00` |

### Runway Length Legend

| Category | Threshold | Color | Hex |
|----------|-----------|-------|-----|
| Long | >8000ft | Red | `#ff0000` |
| Medium | 4000-8000ft | Orange | `#ffa500` |
| Short | <4000ft | Green | `#00ff00` |

### Procedures Legend

| Category | Color | Hex |
|----------|-------|-----|
| ILS/Precision | Yellow | `#ffff00` |
| RNAV/GPS | Blue | `#0080ff` |
| Non-precision | Orange | `#ffa500` |
| VFR only | Gray | `#808080` |

### Country Legend

Countries are assigned colors via hash function for visual distinction.

---

## Thresholds Reference

| Threshold | Value | Usage |
|-----------|-------|-------|
| Long Runway | 8000ft | Runway legend, large airport filter |
| Medium Runway | 4000ft | Runway legend boundary |
| Easy Notice | 12h | Notification cascade |
| Moderate Notice | 24h | Notification cascade |
| Hassle Notice | 48h | Notification cascade |

---

## Verification Checklist

When updating filters or legends, verify:

1. [ ] Same filter applied on web and iOS returns similar airport counts
2. [ ] Same airport shows same legend color on both platforms
3. [ ] Notification cascade produces identical bucket for test cases
4. [ ] New filters added to FilterConfig.swift and web FilterState
5. [ ] This spec document updated with changes

---

## Test Cases for Notification Cascade

| ICAO | Type | Hours | Expected Bucket |
|------|------|-------|-----------------|
| TEST1 | h24 | - | h24 (green) |
| TEST2 | not_available | - | difficult (red) |
| TEST3 | on_request | - | moderate (yellow) |
| TEST4 | business_day | - | hassle (blue) |
| TEST5 | as_ad_hours | - | easy (green) |
| TEST6 | hours | null | easy (green) |
| TEST7 | hours | 6 | easy (green) |
| TEST8 | hours | 18 | moderate (yellow) |
| TEST9 | hours | 36 | hassle (blue) |
| TEST10 | hours | 72 | difficult (red) |
| TEST11 | unknown | null | unknown (gray) |

---

## Related Documents

- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - iOS app structure
- [LEGEND_DESIGN.md](LEGEND_DESIGN.md) - Web legend design
- [UI_FILTER_STATE_DESIGN.md](UI_FILTER_STATE_DESIGN.md) - Web filter state
- [IOS_APP_MAP.md](IOS_APP_MAP.md) - iOS map implementation
