# NovaDesignDemo - iOS Design System Demo

A comprehensive iOS SwiftUI demo application showcasing the Nova Design System with full theme support.

## Overview

This demo app demonstrates:

- ✅ **8 Theme Combinations**: 2 brands × 2 color schemes (light/dark) × 2 modes = 8 total
- ✅ **Live Theme Switching**: Switch between brands and light/dark modes in real-time
- ✅ **Complete Token Coverage**: All colors, typography, spacing, and metrics
- ✅ **Component Examples**: PostCard, Buttons, State indicators
- ✅ **Color Palette Visualization**: All 11 semantic colors per theme
- ✅ **Typography Samples**: titleLG, bodyMD, labelSM
- ✅ **Spacing Scale**: xs, sm, md, lg, xl, xxl visual examples

## Project Structure

```
NovaDesignDemo/
├── project.yml                         # XcodeGen configuration
├── CREATE_XCODE_PROJECT.md             # Setup instructions
├── VERIFICATION_CHECKLIST.md           # Testing checklist
├── README.md                           # This file
└── NovaDesignDemo/
    ├── NovaDesignDemoApp.swift         # App entry point
    ├── ContentView.swift               # Main demo view with theme switcher
    ├── ThemeShowcaseView.swift         # Grid view of all 8 themes
    ├── PostCard.swift                  # Example component
    ├── Theme.swift                     # Design system theme implementation
    ├── Assets.xcassets/
    │   ├── AccentColor.colorset/
    │   ├── AppIcon.appiconset/
    │   ├── brandA.light/               # 11 color sets
    │   ├── brandA.dark/                # 11 color sets
    │   ├── brandB.light/               # 11 color sets
    │   └── brandB.dark/                # 11 color sets
    ├── Preview Content/
    │   └── Preview Assets.xcassets/
    └── Info.plist
```

## Quick Start

### Option 1: Using XcodeGen (Recommended)

```bash
# Install XcodeGen
brew install xcodegen

# Navigate to project directory
cd /Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo

# Generate Xcode project
xcodegen generate

# Open in Xcode
open NovaDesignDemo.xcodeproj
```

### Option 2: Manual Setup

See [CREATE_XCODE_PROJECT.md](./CREATE_XCODE_PROJECT.md) for detailed manual setup instructions.

## Running the App

1. Open `NovaDesignDemo.xcodeproj` in Xcode
2. Select a simulator (iPhone 15 Pro recommended)
3. Press **⌘R** to build and run
4. The app will launch showing the theme demo

## Features

### 1. Theme Switcher

At the top of the app, you can:

- **Switch Brands**: Toggle between Brand A and Brand B using the segmented control
- **Toggle Light/Dark Mode**: Use the switch to toggle between light and dark color schemes

All UI elements update instantly when themes change.

### 2. Color Palette Section

Displays all 11 semantic colors for the current theme:

- **Background Colors**: `bgSurface`, `bgElevated`
- **Foreground Colors**: `fgPrimary`, `fgSecondary`
- **Brand Colors**: `brandPrimary`, `brandOn`
- **Border Colors**: `borderSubtle`, `borderStrong`
- **State Colors**: `stateSuccess`, `stateWarning`, `stateDanger`

Each color is shown as a swatch with its name.

### 3. Typography Samples

Shows the three type scales:

- **Title Large**: 22pt, Bold, 28pt line height
- **Body Medium**: 15pt, Regular, 22pt line height
- **Label Small**: 12pt, Semibold, 16pt line height

### 4. Spacing Scale Visualization

Visual bars showing the six spacing values:

- **xs**: 4pt
- **sm**: 8pt
- **md**: 12pt
- **lg**: 16pt
- **xl**: 24pt
- **xxl**: 32pt

### 5. Component Examples

#### PostCard
A fully-functional social media post card demonstrating:
- Avatar with initial letter
- Author name and timestamp
- Post content
- Optional image
- Action buttons (Like, Comment, Share)

#### Buttons
- **Primary Button**: `brandPrimary` background with `brandOn` text
- **Secondary Button**: Outlined style with `borderStrong`

#### State Indicators
- **Success**: Green indicator with icon
- **Warning**: Yellow/orange indicator with icon
- **Danger**: Red indicator with icon

### 6. Theme Showcase (Optional View)

The `ThemeShowcaseView.swift` provides a grid displaying all 8 theme combinations simultaneously. This view can be navigated to from the main view.

## Design System Integration

### Theme Structure

```swift
Theme(skin: .brandA, dark: false)  // Brand A Light
Theme(skin: .brandA, dark: true)   // Brand A Dark
Theme(skin: .brandB, dark: false)  // Brand B Light
Theme(skin: .brandB, dark: true)   // Brand B Dark
```

### Using Themes in Components

```swift
struct MyView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Hello")
            .font(theme.type.bodyMD)
            .foregroundColor(theme.colors.fgPrimary)
            .padding(theme.space.md)
    }
}
```

### Available Design Tokens

#### Colors (11 semantic colors)
```swift
theme.colors.bgSurface
theme.colors.bgElevated
theme.colors.fgPrimary
theme.colors.fgSecondary
theme.colors.brandPrimary
theme.colors.brandOn
theme.colors.borderSubtle
theme.colors.borderStrong
theme.colors.stateSuccess
theme.colors.stateWarning
theme.colors.stateDanger
```

#### Typography (3 scales)
```swift
theme.type.titleLG    // 22pt Bold
theme.type.bodyMD     // 15pt Regular
theme.type.labelSM    // 12pt Semibold
```

#### Spacing (6 values)
```swift
theme.space.xs    // 4pt
theme.space.sm    // 8pt
theme.space.md    // 12pt
theme.space.lg    // 16pt
theme.space.xl    // 24pt
theme.space.xxl   // 32pt
```

#### Metrics (component dimensions)
```swift
theme.metric.avatarXS           // 24pt
theme.metric.avatarSM           // 32pt
theme.metric.avatarMD           // 40pt
theme.metric.avatarLG           // 56pt
theme.metric.iconMD             // 20pt
theme.metric.iconLG             // 24pt
theme.metric.postCardPaddingX   // 12pt
theme.metric.postCardPaddingY   // 8pt
theme.metric.postCardCorner     // 12pt
theme.metric.hitAreaMin         // 44pt
```

#### Radius (border radius)
```swift
theme.radius.sm    // 8pt
theme.radius.md    // 12pt
theme.radius.lg    // 16pt
```

#### Motion (animation timing)
```swift
theme.motion.durationFast       // 0.12s
theme.motion.durationBase       // 0.20s
theme.motion.durationSlow       // 0.32s
theme.motion.easingStandard     // (0.2, 0, 0, 1)
```

## Verification

Use the [VERIFICATION_CHECKLIST.md](./VERIFICATION_CHECKLIST.md) to systematically verify all aspects of the design system implementation.

## Requirements

- **Xcode**: 14.0 or later
- **iOS Deployment Target**: 15.0 or later
- **Swift**: 5.9 or later
- **Platform**: iOS (iPhone/iPad)

## Troubleshooting

### Colors Not Appearing

If colors show as default system colors:

1. Verify Asset Catalog contains all theme folders
2. Clean build folder: **Product → Clean Build Folder** (⇧⌘K)
3. Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
4. Rebuild the project

### Build Errors

If you encounter build errors:

1. Ensure all `.swift` files are added to the target
2. Check that `Info.plist` path is correct in Build Settings
3. Verify deployment target is iOS 15.0 or higher
4. Clean and rebuild

### Simulator Issues

If the simulator doesn't launch:

1. Quit Simulator
2. In Xcode: **Product → Clean Build Folder**
3. Restart Xcode
4. Try a different simulator

## Extending the Demo

### Adding New Components

1. Create a new Swift file in `NovaDesignDemo/`
2. Use `@Environment(\.theme)` to access theme
3. Apply design tokens consistently
4. Add to `ContentView.swift` for display

Example:

```swift
struct MyComponent: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.space.md) {
            Text("Custom Component")
                .font(theme.type.titleLG)
                .foregroundColor(theme.colors.fgPrimary)
        }
        .padding(theme.space.lg)
        .background(theme.colors.bgElevated)
        .cornerRadius(theme.radius.md)
    }
}
```

### Adding New Themes

To add a new brand (e.g., Brand C):

1. Generate color sets: Run `generate_colors.py` with new brand tokens
2. Copy color sets to `Assets.xcassets/brandC.light/` and `brandC.dark/`
3. Add `brandC` case to `BrandSkin` enum in `Theme.swift`
4. Rebuild and test

## Related Documentation

- [../README.md](../README.md) - Main iOS design system documentation
- [../QUICKSTART.md](../QUICKSTART.md) - Quick start guide
- [../GENERATION_MANIFEST.md](../GENERATION_MANIFEST.md) - Generation process details
- [../../shared/design-tokens/tokens.design.json](../../shared/design-tokens/tokens.design.json) - Source design tokens

## License

Copyright © 2025 Nova. All rights reserved.

## Support

For issues or questions:

1. Check the [VERIFICATION_CHECKLIST.md](./VERIFICATION_CHECKLIST.md)
2. Review [CREATE_XCODE_PROJECT.md](./CREATE_XCODE_PROJECT.md)
3. Consult the main design system documentation

---

**Happy theming!** 🎨
