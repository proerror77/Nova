# Nova Android Design System

Complete Jetpack Compose implementation of the Nova design system with multi-brand support.

## Architecture Overview

```
android/
├── res/
│   ├── values/
│   │   ├── colors.xml          # BrandA Light (default)
│   │   └── dimens.xml          # Spacing, radius, component sizes
│   └── values-night/
│       └── colors.xml          # BrandA Dark
├── com/nova/designsystem/theme/
│   ├── Color.kt                # Color scheme definitions
│   ├── LocalTheme.kt           # CompositionLocal providers
│   ├── Theme.kt                # Main theme composable
│   ├── Type.kt                 # Typography scale
│   └── Spacing.kt              # Spacing and size tokens
└── examples/
    └── PostCard.kt             # Example component with previews
```

## Features

- **8 Theme Combinations**: BrandA/BrandB × Light/Dark
- **Material3 Integration**: Full Material Design 3 ColorScheme mapping
- **Type-Safe Access**: Compile-time checked theme tokens
- **Dynamic Color Support**: Android 12+ Material You compatibility
- **Preview Support**: 4 preview configurations per component

## Usage

### Basic Setup

```kotlin
import com.nova.designsystem.theme.*

@Composable
fun MyApp() {
    NovaTheme(
        skin = BrandSkin.BRAND_A,
        isDark = isSystemInDarkTheme()
    ) {
        // Your app content
    }
}
```

### Accessing Theme Values

```kotlin
@Composable
fun MyComponent() {
    val colors = NovaTheme.colors
    val brand = NovaTheme.brand

    Surface(
        color = colors.bgSurface,
        shape = RoundedCornerShape(NovaRadius.md)
    ) {
        Column(
            modifier = Modifier.padding(NovaSpacing.lg)
        ) {
            Text(
                text = "Hello Nova",
                color = colors.fgPrimary,
                style = MaterialTheme.typography.headlineMedium
            )
        }
    }
}
```

### Dynamic Brand Switching

```kotlin
var currentBrand by remember { mutableStateOf(BrandSkin.BRAND_A) }

NovaTheme(skin = currentBrand) {
    Button(onClick = {
        currentBrand = if (currentBrand == BrandSkin.BRAND_A)
            BrandSkin.BRAND_B
        else
            BrandSkin.BRAND_A
    }) {
        Text("Switch Brand")
    }
}
```

## Color Tokens

### Semantic Colors

| Token | Purpose | BrandA Light | BrandA Dark |
|-------|---------|--------------|-------------|
| `bgSurface` | Main background | #FFFFFF | #101828 |
| `bgElevated` | Elevated surfaces | #F9FAFB | #1D2939 |
| `fgPrimary` | Primary text | #101828 | #FFFFFF |
| `fgSecondary` | Secondary text | #475467 | #98A2B3 |
| `brandPrimary` | Brand color | #0086C9 | #0BA5EC |
| `brandOn` | Text on brand | #FFFFFF | #001119 |
| `borderSubtle` | Light borders | #E4E7EC | #1D2939 |
| `borderStrong` | Strong borders | #D0D5DD | #344054 |
| `stateSuccess` | Success state | #12B76A | #12B76A |
| `stateWarning` | Warning state | #F79009 | #F79009 |
| `stateDanger` | Error/danger | #F04438 | #F97066 |

### BrandB Overrides

- **BrandB Light**: `brandPrimary` = #F04438 (Red)
- **BrandB Dark**: `brandPrimary` = #F97066 (Light Red)

## Spacing Scale

```kotlin
NovaSpacing.xs    // 4dp
NovaSpacing.sm    // 8dp
NovaSpacing.md    // 12dp
NovaSpacing.lg    // 16dp
NovaSpacing.xl    // 24dp
NovaSpacing.xxl   // 32dp
```

## Border Radius

```kotlin
NovaRadius.sm     // 8dp
NovaRadius.md     // 12dp
NovaRadius.lg     // 16dp
```

## Component Sizes

### Avatars

```kotlin
NovaAvatarSize.xs  // 24dp
NovaAvatarSize.sm  // 32dp
NovaAvatarSize.md  // 40dp
NovaAvatarSize.lg  // 56dp
```

### Icons

```kotlin
NovaIconSize.md    // 20dp
NovaIconSize.lg    // 24dp
```

### Component-Specific

```kotlin
// Post Card
NovaComponents.PostCard.paddingX      // 12dp
NovaComponents.PostCard.paddingY      // 8dp
NovaComponents.PostCard.corner        // 12dp

// Story Ring
NovaComponents.Story.diameter         // 68dp
NovaComponents.Story.ring             // 2dp

// Grid
NovaComponents.Grid.columns           // 3
NovaComponents.Grid.gap               // 2dp
NovaComponents.Grid.thumbCorner       // 4dp

// Hit Area
NovaComponents.HitArea.min            // 44dp (accessibility minimum)
```

## Typography

Material3 typography scale with custom values:

```kotlin
MaterialTheme.typography.displayLarge      // 57sp, Bold
MaterialTheme.typography.headlineMedium    // 28sp, SemiBold
MaterialTheme.typography.titleLarge        // 22sp, SemiBold
MaterialTheme.typography.bodyMedium        // 14sp, Normal
MaterialTheme.typography.labelSmall        // 11sp, Medium
```

## Material3 Color Mapping

| Material3 | Nova Token |
|-----------|------------|
| `primary` | `brandPrimary` |
| `onPrimary` | `brandOn` |
| `background` | `bgSurface` |
| `surface` | `bgSurface` |
| `surfaceVariant` | `bgElevated` |
| `error` | `stateDanger` |
| `tertiary` | `stateSuccess` |
| `outline` | `borderStrong` |
| `outlineVariant` | `borderSubtle` |

## Previews

All components include 4 preview configurations:

```kotlin
@Preview(name = "BrandA Light")
@Composable
private fun MyComponentBrandALightPreview() {
    NovaThemeBrandALight {
        MyComponent()
    }
}

@Preview(name = "BrandA Dark")
@Composable
private fun MyComponentBrandADarkPreview() {
    NovaThemeBrandADark {
        MyComponent()
    }
}

// Similar for BrandB Light/Dark
```

## Example: PostCard Component

See `examples/PostCard.kt` for a complete Instagram-style post card implementation demonstrating:

- Avatar sizing
- Icon sizing
- Spacing scale usage
- Semantic color tokens
- Border radius
- Hit area minimums
- State management (like button)
- Typography scale

## Production Readiness

✅ Type-safe token access
✅ Dark mode support
✅ Multi-brand support
✅ Material3 integration
✅ Accessibility (44dp hit areas)
✅ System bar theming
✅ Preview configurations
✅ Dynamic color support (Android 12+)

## Integration

Add to your `build.gradle.kts`:

```kotlin
dependencies {
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.core:core-ktx")
}
```

## Design Tokens Source

All values derived from `/Users/proerror/Documents/nova/frontend/design-system/tokens.design.json`

---

**Built with Linus Torvalds' "Good Taste" philosophy**: Simple data structures, zero edge cases, production-ready code.
