# Nova iOS Design System

Complete SwiftUI theme implementation with 4 theme combinations (2 brands × 2 color modes).

## 📁 Structure

```
ios/
├── DesignTokens/              # xcassets color bundles
│   ├── brandA.light/          # 11 color assets
│   ├── brandA.dark/           # 11 color assets
│   ├── brandB.light/          # 11 color assets
│   └── brandB.dark/           # 11 color assets
├── Theme.swift                # Runtime theme system
├── ExamplePostCard.swift      # Usage example
└── README.md                  # This file
```

## 🎨 Color Assets (44 total)

Each theme contains 11 semantic colors:

- **Background**: `bgSurface`, `bgElevated`
- **Foreground**: `fgPrimary`, `fgSecondary`
- **Brand**: `brandPrimary`, `brandOn`
- **Border**: `borderSubtle`, `borderStrong`
- **State**: `stateSuccess`, `stateWarning`, `stateDanger`

### Theme Combinations

| Theme ID      | Brand   | Mode  | Primary Color |
|---------------|---------|-------|---------------|
| brandA.light  | Brand A | Light | Blue #0086C9  |
| brandA.dark   | Brand A | Dark  | Blue #0BA5EC  |
| brandB.light  | Brand B | Light | Coral #F04438 |
| brandB.dark   | Brand B | Dark  | Coral #F97066 |

## 🚀 Usage

### Basic Setup

```swift
import SwiftUI

@main
struct NovaApp: App {
    @State private var currentTheme = Theme(skin: .brandA, dark: false)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .theme(currentTheme)
        }
    }
}
```

### Accessing Theme in Views

```swift
struct MyView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.space.md) {
            Text("Hello World")
                .font(theme.type.titleLG)
                .foregroundColor(theme.colors.fgPrimary)

            Button("Action") { }
                .foregroundColor(theme.colors.brandOn)
                .background(theme.colors.brandPrimary)
                .cornerRadius(theme.radius.md)
        }
        .padding(theme.space.lg)
        .background(theme.colors.bgSurface)
    }
}
```

### Theme Switching

```swift
struct ThemeSwitcher: View {
    @Environment(\.theme) private var theme
    @State private var selectedSkin: BrandSkin = .brandA
    @State private var isDark = false

    var body: some View {
        VStack {
            Picker("Brand", selection: $selectedSkin) {
                ForEach(BrandSkin.allCases) { skin in
                    Text(skin.displayName).tag(skin)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Dark Mode", isOn: $isDark)
        }
        .theme(skin: selectedSkin, dark: isDark)
    }
}
```

## 📐 Design Tokens

### Colors
Access via `theme.colors.*`:
- `bgSurface`, `bgElevated`
- `fgPrimary`, `fgSecondary`
- `brandPrimary`, `brandOn`
- `borderSubtle`, `borderStrong`
- `stateSuccess`, `stateWarning`, `stateDanger`

### Typography
Access via `theme.type.*`:
- `labelSM` - 12pt semibold (labels, captions)
- `bodyMD` - 15pt regular (body text)
- `titleLG` - 22pt bold (headings)

### Spacing
Access via `theme.space.*`:
- `xs` (4pt), `sm` (8pt), `md` (12pt)
- `lg` (16pt), `xl` (24pt), `xxl` (32pt)

### Metrics (Component Dimensions)
Access via `theme.metric.*`:

**Avatars**: `avatarXS` (24), `avatarSM` (32), `avatarMD` (40), `avatarLG` (56)

**Icons**: `iconMD` (20), `iconLG` (24)

**Post Card**: `postCardPaddingX` (12), `postCardPaddingY` (8), `postCardCorner` (12)

**Story**: `storyDiameter` (68), `storyRing` (2)

**Grid**: `gridProfileColumns` (3), `gridGap` (2), `gridThumbCorner` (4)

**Hit Area**: `hitAreaMin` (44)

### Radius
Access via `theme.radius.*`:
- `sm` (8pt), `md` (12pt), `lg` (16pt)

### Motion
Access via `theme.motion.*`:
- `durationFast` (0.12s), `durationBase` (0.2s), `durationSlow` (0.32s)
- `easingStandard` - Cubic Bezier (0.2, 0, 0, 1)

## 📱 Example: Post Card Component

See `ExamplePostCard.swift` for a complete implementation showing:
- ✅ Theme-aware colors
- ✅ Typography scale usage
- ✅ Spacing consistency
- ✅ Component metrics
- ✅ Minimum hit areas (44pt)
- ✅ Preview variants for all themes

## 🔧 Integration with Xcode

### Adding to Xcode Project

1. **Add Color Assets**:
   - Drag `DesignTokens/` folder into your Xcode project
   - Ensure "Copy items if needed" is checked
   - Target membership: Main app target

2. **Add Swift Files**:
   - Add `Theme.swift` to your project
   - Add `ExamplePostCard.swift` (optional, for reference)

3. **Asset Catalog Setup**:
   - Colors are already in the correct `.colorset` format
   - Xcode will recognize them automatically
   - Access via `Color("brandA.light/bgSurface")`

### Build Settings

No special build settings required. Standard SwiftUI project configuration.

## 🎨 Design System Philosophy

### Semantic Naming
Colors are named by purpose, not appearance:
- ✅ `bgSurface` (purpose-driven)
- ❌ `white` (appearance-driven)

### Theme Independence
Components should only reference semantic tokens:
```swift
// ✅ Good
.foregroundColor(theme.colors.fgPrimary)

// ❌ Bad
.foregroundColor(.black)
```

### Consistency
All spacing uses the scale:
```swift
// ✅ Good
.padding(theme.space.md)

// ❌ Bad
.padding(10)
```

## 📊 Technical Details

### Color Format
- **Color Space**: sRGB
- **Precision**: 3 decimal places (0.000-1.000)
- **Alpha**: Always 1.000 (fully opaque)

### File Structure
```
brandA.light/
└── bgSurface.colorset/
    └── Contents.json
        {
          "colors": [{
            "idiom": "universal",
            "color": {
              "color-space": "srgb",
              "components": {
                "red": "1.000",
                "green": "1.000",
                "blue": "1.000",
                "alpha": "1.000"
              }
            }
          }],
          "info": { "version": 1, "author": "xcode" }
        }
```

### Theme Resolution
Themes are resolved at runtime based on:
1. **Brand Skin**: `brandA` or `brandB`
2. **Color Mode**: `light` or `dark`
3. **Theme ID**: `{skin}.{mode}` (e.g., "brandA.light")

## 🧪 Testing

### Preview All Themes
```swift
struct MyView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(Theme.allCombinations, id: \.themeId) { theme in
            MyView()
                .theme(theme)
                .previewDisplayName(theme.themeId)
        }
    }
}
```

### Verify Colors
```swift
// Color components are accessible for testing
let theme = Theme.brandALight
let bgColor = theme.colors.bgSurface
// Use UIColor(bgColor) to extract RGB components if needed
```

## 🔍 Troubleshooting

### Colors Not Showing

1. **Check asset bundle**:
   - Verify `DesignTokens/` is in your Xcode project
   - Check target membership

2. **Verify color path**:
   ```swift
   // Correct format
   Color("brandA.light/bgSurface", bundle: .main)
   ```

3. **Clean build**:
   - Product → Clean Build Folder (Shift+Cmd+K)
   - Rebuild project

### Theme Not Applied

1. **Verify environment injection**:
   ```swift
   ContentView()
       .theme(Theme(skin: .brandA, dark: false))
   ```

2. **Check @Environment access**:
   ```swift
   @Environment(\.theme) private var theme // Must be private
   ```

## 📚 Source

Generated from `/Users/proerror/Documents/nova/frontend/design-system/tokens.design.json`

All values match the design tokens specification exactly.

## 🎯 Next Steps

1. **Import into Xcode**: Drag folders into your project
2. **Test Themes**: Run the ExamplePostCard preview
3. **Build Components**: Use theme tokens in your views
4. **Extend**: Add custom components following the same pattern

## 📄 License

Copyright © 2025 Nova. All rights reserved.
