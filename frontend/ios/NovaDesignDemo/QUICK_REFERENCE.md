# NovaDesignDemo - Quick Reference

## Immediate Steps to Launch

### Using XcodeGen (2 commands)

```bash
cd /Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo
xcodegen generate && open NovaDesignDemo.xcodeproj
```

### In Xcode

1. Select **iPhone 15 Pro** simulator
2. Press **⌘R**
3. App launches - start testing themes!

---

## Testing Flow

1. **Launch app** → See Brand A Light theme by default
2. **Toggle segment control** → Switch to Brand B
3. **Flip dark mode switch** → Test Brand B Dark
4. **Switch back to Brand A** → Test Brand A Dark
5. **Scroll through sections** → Verify all components

---

## What to Verify

### Quick Visual Check

- [ ] Brand A and Brand B have **different colors**
- [ ] Dark mode makes background **dark** and text **light**
- [ ] All 11 color swatches appear (no missing colors)
- [ ] PostCard component renders with rounded corners
- [ ] Buttons are tappable (44pt hit area)
- [ ] No console errors in Xcode

### Color Quick Test

| Color | Expected Behavior |
|-------|-------------------|
| `bgSurface` | White (light) / Dark gray (dark) |
| `fgPrimary` | Black (light) / White (dark) |
| `brandPrimary` | Distinct color per brand |
| `stateSuccess` | Green |
| `stateWarning` | Yellow/Orange |
| `stateDanger` | Red |

---

## Common Commands

### Generate Project
```bash
cd /Users/proerror/Documents/nova/frontend/ios/NovaDesignDemo
xcodegen generate
```

### Open Project
```bash
open NovaDesignDemo.xcodeproj
```

### Clean Build
In Xcode: **Product → Clean Build Folder** (⇧⌘K)

### Run Tests (if added)
In Xcode: **Product → Test** (⌘U)

---

## File Locations

### Source Files
```
NovaDesignDemo/NovaDesignDemo/
├── NovaDesignDemoApp.swift      # Entry point
├── ContentView.swift            # Main demo UI
├── ThemeShowcaseView.swift      # All themes grid
├── PostCard.swift               # Example component
└── Theme.swift                  # Design system
```

### Asset Catalog
```
NovaDesignDemo/NovaDesignDemo/Assets.xcassets/
├── brandA.light/   (11 colors)
├── brandA.dark/    (11 colors)
├── brandB.light/   (11 colors)
└── brandB.dark/    (11 colors)
```

---

## Design Token Reference

### Colors (Access via `theme.colors`)

```swift
bgSurface, bgElevated           // Backgrounds
fgPrimary, fgSecondary          // Text
brandPrimary, brandOn           // Brand
borderSubtle, borderStrong      // Borders
stateSuccess, stateWarning, stateDanger  // States
```

### Typography (Access via `theme.type`)

```swift
titleLG   // 22pt, Bold
bodyMD    // 15pt, Regular
labelSM   // 12pt, Semibold
```

### Spacing (Access via `theme.space`)

```swift
xs  (4pt)   sm  (8pt)   md  (12pt)
lg  (16pt)  xl  (24pt)  xxl (32pt)
```

### Radius (Access via `theme.radius`)

```swift
sm (8pt)   md (12pt)   lg (16pt)
```

---

## Code Snippets

### Access Current Theme
```swift
@Environment(\.theme) private var theme
```

### Create Custom Component
```swift
VStack(spacing: theme.space.md) {
    Text("Title")
        .font(theme.type.titleLG)
        .foregroundColor(theme.colors.fgPrimary)
}
.padding(theme.space.lg)
.background(theme.colors.bgElevated)
.cornerRadius(theme.radius.md)
```

### Apply Theme to View
```swift
MyView()
    .theme(skin: .brandA, dark: false)
```

---

## Troubleshooting One-Liners

| Issue | Fix |
|-------|-----|
| Colors missing | Clean build (⇧⌘K) + rebuild |
| Build errors | Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData` |
| Simulator won't launch | Restart Xcode |
| Theme not switching | Check Asset Catalog has all 4 folders |

---

## Expected Results

### Brand A Light
- Light background
- Dark text
- Brand A's primary color (e.g., blue)

### Brand A Dark
- Dark background
- Light text
- Brand A's primary color adjusted for dark mode

### Brand B Light
- Light background
- Dark text
- Brand B's primary color (different from Brand A)

### Brand B Dark
- Dark background
- Light text
- Brand B's primary color adjusted for dark mode

---

## Success Criteria

✅ **App launches without errors**
✅ **All 4 theme combinations work**
✅ **Theme switching is instant**
✅ **Components render correctly**
✅ **Colors match design tokens**
✅ **No console warnings**

---

## Next Actions After Verification

1. ✅ Design system is validated
2. 📝 Document any issues found
3. 🎨 Consider adding more components
4. 🚀 Integrate into main project

---

For detailed verification, see [VERIFICATION_CHECKLIST.md](./VERIFICATION_CHECKLIST.md)
