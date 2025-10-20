# iOS Design System - Quick Start Guide

## 🚀 5-Minute Integration

### 1. Add Files to Xcode (2 min)

**Open your Xcode project**, then:

1. **Add Color Assets**:
   - Drag `DesignTokens/` folder into Xcode's project navigator
   - ✅ Check "Copy items if needed"
   - ✅ Select your app target
   - Click "Finish"

2. **Add Theme File**:
   - Drag `Theme.swift` into your project
   - ✅ Check "Copy items if needed"
   - ✅ Add to app target
   - Click "Finish"

### 2. Test the Theme (1 min)

Create a new SwiftUI view:

```swift
import SwiftUI

struct TestThemeView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.space.lg) {
            Text("Design System Works!")
                .font(theme.type.titleLG)
                .foregroundColor(theme.colors.fgPrimary)

            Text("Theme: \(theme.themeId)")
                .font(theme.type.bodyMD)
                .foregroundColor(theme.colors.fgSecondary)

            HStack {
                Circle()
                    .fill(theme.colors.brandPrimary)
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(theme.colors.stateSuccess)
                    .frame(width: 60, height: 60)

                Circle()
                    .fill(theme.colors.stateWarning)
                    .frame(width: 60, height: 60)
            }
        }
        .padding(theme.space.xl)
        .background(theme.colors.bgSurface)
    }
}

struct TestThemeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TestThemeView()
                .theme(.brandALight)
                .previewDisplayName("Brand A Light")

            TestThemeView()
                .theme(.brandADark)
                .previewDisplayName("Brand A Dark")
                .preferredColorScheme(.dark)
        }
    }
}
```

### 3. Apply to Your App (1 min)

Update your `App.swift`:

```swift
import SwiftUI

@main
struct YourApp: App {
    @State private var currentTheme = Theme.brandALight

    var body: some Scene {
        WindowGroup {
            ContentView()
                .theme(currentTheme)
        }
    }
}
```

### 4. Preview Example Component (1 min)

Open `ExamplePostCard.swift` in Xcode:
- Click "Resume" in Canvas
- See all 4 theme variants automatically

---

## 🎨 Common Usage Patterns

### Colors
```swift
@Environment(\.theme) private var theme

// Background
.background(theme.colors.bgSurface)
.background(theme.colors.bgElevated)

// Text
.foregroundColor(theme.colors.fgPrimary)
.foregroundColor(theme.colors.fgSecondary)

// Brand
.foregroundColor(theme.colors.brandOn)
.background(theme.colors.brandPrimary)

// Borders
.border(theme.colors.borderSubtle)
.border(theme.colors.borderStrong)

// States
.foregroundColor(theme.colors.stateSuccess)  // Green
.foregroundColor(theme.colors.stateWarning)  // Orange
.foregroundColor(theme.colors.stateDanger)   // Red
```

### Typography
```swift
@Environment(\.theme) private var theme

Text("Label").font(theme.type.labelSM)   // 12pt semibold
Text("Body").font(theme.type.bodyMD)     // 15pt regular
Text("Title").font(theme.type.titleLG)   // 22pt bold
```

### Spacing
```swift
@Environment(\.theme) private var theme

.padding(theme.space.xs)   // 4pt
.padding(theme.space.sm)   // 8pt
.padding(theme.space.md)   // 12pt
.padding(theme.space.lg)   // 16pt
.padding(theme.space.xl)   // 24pt
.padding(theme.space.xxl)  // 32pt

// Or specific edges
.padding(.horizontal, theme.space.md)
.padding(.vertical, theme.space.lg)
```

### Component Dimensions
```swift
@Environment(\.theme) private var theme

// Avatars
.frame(width: theme.metric.avatarXS)  // 24
.frame(width: theme.metric.avatarSM)  // 32
.frame(width: theme.metric.avatarMD)  // 40
.frame(width: theme.metric.avatarLG)  // 56

// Icons
Image(systemName: "heart")
    .font(.system(size: theme.metric.iconMD))  // 20

// Minimum touch target
Button("Tap") { }
    .frame(minWidth: theme.metric.hitAreaMin,
           minHeight: theme.metric.hitAreaMin)  // 44×44
```

### Corner Radius
```swift
@Environment(\.theme) private var theme

.cornerRadius(theme.radius.sm)  // 8
.cornerRadius(theme.radius.md)  // 12
.cornerRadius(theme.radius.lg)  // 16
```

### Animations
```swift
@Environment(\.theme) private var theme

// Duration
withAnimation(.easeInOut(duration: theme.motion.durationFast)) { }   // 0.12s
withAnimation(.easeInOut(duration: theme.motion.durationBase)) { }   // 0.20s
withAnimation(.easeInOut(duration: theme.motion.durationSlow)) { }   // 0.32s

// With standard easing
withAnimation(theme.motion.easingStandard) { }
```

---

## 🔄 Theme Switching

### Static Theme
```swift
ContentView()
    .theme(skin: .brandA, dark: false)
```

### Dynamic Theme
```swift
struct RootView: View {
    @State private var skin: BrandSkin = .brandA
    @State private var isDark = false

    var body: some View {
        TabView {
            // Your views here
        }
        .theme(skin: skin, dark: isDark)
        .onChange(of: colorScheme) { newScheme in
            isDark = (newScheme == .dark)
        }
    }
}
```

### With User Defaults
```swift
class ThemeManager: ObservableObject {
    @AppStorage("selectedSkin") var skinRaw = "brandA"
    @AppStorage("darkMode") var isDark = false

    var skin: BrandSkin {
        BrandSkin(rawValue: skinRaw) ?? .brandA
    }

    var theme: Theme {
        Theme(skin: skin, dark: isDark)
    }
}

@StateObject var themeManager = ThemeManager()

ContentView()
    .theme(themeManager.theme)
```

---

## 📱 Available Themes

| Theme ID      | Usage                                | Primary Color |
|---------------|--------------------------------------|---------------|
| brandALight   | `Theme.brandALight` or `.theme(.brandALight)` | Blue #0086C9  |
| brandADark    | `Theme.brandADark` or `.theme(.brandADark)`   | Blue #0BA5EC  |
| brandBLight   | `Theme.brandBLight` or `.theme(.brandBLight)` | Coral #F04438 |
| brandBDark    | `Theme.brandBDark` or `.theme(.brandBDark)`   | Coral #F97066 |

---

## ✅ Checklist

After integration, verify:

- [ ] `DesignTokens/` folder visible in Xcode project navigator
- [ ] `Theme.swift` compiles without errors
- [ ] Preview shows themed colors correctly
- [ ] Can access `@Environment(\.theme)` in views
- [ ] Theme switching updates colors in real-time
- [ ] All 4 theme variants preview correctly

---

## 🆘 Troubleshooting

### Colors Not Showing
**Problem**: Colors appear as default/wrong colors

**Solution**:
1. Verify `DesignTokens/` is in project (not just referenced)
2. Check target membership (right-click folder → Target Membership)
3. Clean build: Product → Clean Build Folder (⇧⌘K)
4. Rebuild project

### Theme Not Applied
**Problem**: `@Environment(\.theme)` not working

**Solution**:
```swift
// ❌ Wrong
@Environment(\.theme) var theme

// ✅ Correct
@Environment(\.theme) private var theme
```

### Colors Wrong in Dark Mode
**Problem**: Colors don't adapt to system dark mode

**Solution**:
Explicitly set `.preferredColorScheme()`:
```swift
ContentView()
    .theme(skin: .brandA, dark: isDark)
```

---

## 📚 Full Documentation

For complete API reference and advanced usage, see:
- `README.md` - Complete documentation
- `ExamplePostCard.swift` - Real-world example
- `Theme.swift` - Full API source code

---

**Ready to build!** 🎉

Start using theme tokens in your views and enjoy consistent, themeable UI across your entire app.
