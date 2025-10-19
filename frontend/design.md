# Design System & Multi-Brand Theming - Design Document

## Overview

**Design System**: Centralized token-driven architecture enabling theme switching via single-source-of-truth JSON (tokens.design.json) managed in Figma Tokens Studio.

**Key Principle**: Separate data layer (tokens) from presentation layer (platform-specific Theme objects). All visual changes propagate via JSON export, not code edits.

**Scope**:
- 2 brands (BrandA: blue, BrandB: coral)
- 2 color modes (light/dark)
- 2 platforms (iOS/Android)
- 8 complete theme combinations
- Single implementation for each platform, switching without restart

## Architecture

### Three-Tier Token Model

```
Layer 1: tokens.design.json (Figma Tokens Studio - single source)
  ↓
Layer 2: Platform Generators (Style Dictionary for iOS, Gradle for Android)
  ↓
Layer 3: Platform-Specific Runtime (Theme.swift / Theme.kt)
  ↓
Layer 4: UI Components (SwiftUI Views / Composable functions)
```

### Token Categories

```json
{
  "core": {
    "color": { "palette": { "gray": [0-900], "blue": [500-700], "coral": [500-700], ... } },
    "type": { "fontFamily": "SF Pro Text", "scale": { "label/sm", "body/md", "title/lg" } },
    "space": { "xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24, "2xl": 32 },
    "radius": { "sm": 8, "md": 12, "lg": 16 },
    "motion": { "duration": { "fast": 120, "base": 200, "slow": 320 }, "easing": "standard" }
  },
  "brandA.light": { color: { bg, fg, brand, border, state } },
  "brandA.dark": { ... },
  "brandB.light": { ... },
  "brandB.dark": { ... }
}
```

### iOS Architecture

```
XCAssets/
├── brandA.light/[11 colors].colorset
├── brandA.dark/[11 colors].colorset
├── brandB.light/[11 colors].colorset
└── brandB.dark/[11 colors].colorset

Code/
├── Theme.swift (BrandSkin enum, Theme struct, @Environment key)
├── Colors struct (dynamic color accessor)
├── TypeScale struct (Font objects)
├── Space struct (CGFloat constants)
└── Metric struct (layout constants)
```

### Android Architecture

```
res/
├── values/colors.xml (default light theme)
├── values/dimens.xml
├── values/styles.xml (Material3 base)
├── values-night/colors.xml (dark mode)

com/nova/designsystem/
├── theme/Theme.kt (Compose CompositionLocal)
├── color/ColorScheme.kt (color definitions)
├── type/Typography.kt
├── dimension/Dimensions.kt
└── LocalTheme.kt (CompositionLocal helpers)
```

## Components and Interfaces

### iOS Theme.swift Interface

```swift
// Injection at App root
@main struct App: App {
  @Environment(\.colorScheme) var colorScheme
  var body: some Scene {
    WindowGroup {
      ContentView()
        .theme(.brandA, colorScheme: colorScheme)
    }
  }
}

// Usage in View
struct PostCard: View {
  @Environment(\.theme) var t
  var body: some View {
    VStack { /* ... */ }
      .background(t.colors.bgElevated)
      .cornerRadius(t.metric.postCorner)
  }
}

// Theme switching (runtime)
func switchBrand(to skin: BrandSkin) {
  UserDefaults.standard.set(skin.rawValue, forKey: "selectedBrand")
  // Refresh affected views via @State or AppDelegate
}
```

### Android Theme.kt Interface

```kotlin
@Composable fun NovaApp() {
  val isDarkTheme = isSystemInDarkTheme()
  val selectedBrand = remember { mutableStateOf(BrandSkin.BRAND_A) }

  CompositionLocalProvider(
    LocalBrandTheme provides selectedBrand.value,
    LocalColorScheme provides (if (isDarkTheme) darkColorScheme else lightColorScheme)
  ) {
    // All children auto-theme
    MainContent()
  }
}

@Composable fun PostCard() {
  val theme = LocalBrandTheme.current
  val colors = theme.getColors()

  Box(
    modifier = Modifier
      .background(colors.bgElevated)
      .clip(RoundedCornerShape(theme.metric.postCorner.dp))
  )
}
```

## Data Models

### Token JSON Structure (tokens.design.json)

11 Color Families per theme:
- bg.surface, bg.elevated
- fg.primary, fg.secondary
- brand.primary, brand.on
- border.subtle, border.strong
- state.success, state.warning, state.danger

3 Type Scales:
- label/sm: 12px, 600 weight
- body/md: 15px, 400 weight
- title/lg: 22px, 700 weight

6 Space Values: xs(4), sm(8), md(12), lg(16), xl(24), 2xl(32)

3 Radius Values: sm(8), md(12), lg(16)

2 Motion Values: fast(120ms), base(200ms), slow(320ms)

### Runtime Data Models

**iOS Theme.swift**
```swift
struct Theme {
  let skin: BrandSkin
  let dark: Bool
  var colors: Colors
  var type: TypeScale
  var space: Space
  var metric: Metric
}
```

**Android Theme.kt**
```kotlin
data class ThemeConfig(
  val brandSkin: BrandSkin,
  val isDark: Boolean,
  val colors: ColorScheme,
  val typography: Typography,
  val dimensions: Dimensions
)
```

## Error Handling

1. **Token Loading Failure**: Fallback to BrandA.light (hardcoded defaults)
2. **Missing Color Asset**: Return `.gray.50` (safe default)
3. **Font Load Timeout**: System font (SF Pro Text / Roboto native)
4. **Theme Switch During Animation**: Queue switch, apply after current animation completes

## Testing Strategy

1. **Unit Tests**
   - Token JSON schema validation
   - Theme object construction for all 8 combinations
   - Color accessor correctness

2. **Integration Tests**
   - Theme environment injection works in SwiftUI preview
   - CompositionLocal propagates in Compose preview
   - Theme switching updates all dependent views

3. **Visual Tests**
   - Screenshot all 8 theme combinations
   - Verify colors match Figma specs
   - Dark mode contrast compliance (WCAG AA+)

4. **Performance Tests**
   - Theme initialization < 16ms
   - Theme switch animation remains 60fps
