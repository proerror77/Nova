# NovaDesignDemo Verification Checklist

Use this checklist to verify that the Nova Design System is correctly implemented in the iOS demo app.

## Prerequisites

- [ ] Xcode project successfully created and opened
- [ ] App builds without errors
- [ ] Simulator is running (iPhone 15 Pro recommended)
- [ ] App launches successfully

---

## 1. Theme Switching Functionality

### Brand Switching
- [ ] **Brand A** selector is visible
- [ ] **Brand B** selector is visible
- [ ] Switching between brands updates all UI elements
- [ ] Brand switch is smooth with no lag

### Light/Dark Mode Toggle
- [ ] Light mode toggle works
- [ ] Dark mode toggle works
- [ ] Toggle icon changes (sun/moon)
- [ ] Mode switch updates entire app UI
- [ ] Mode switch is animated smoothly

---

## 2. Color Palette Verification

### Brand A Light Theme
Verify these colors render correctly:

- [ ] `bgSurface` - Light background (should be very light/white)
- [ ] `bgElevated` - Slightly elevated surface
- [ ] `fgPrimary` - Primary text (dark, high contrast)
- [ ] `fgSecondary` - Secondary text (medium contrast)
- [ ] `brandPrimary` - Brand A's primary color
- [ ] `brandOn` - Text/icons on brand color (should contrast with brandPrimary)
- [ ] `borderSubtle` - Light border
- [ ] `borderStrong` - Stronger border
- [ ] `stateSuccess` - Green success color
- [ ] `stateWarning` - Yellow/orange warning color
- [ ] `stateDanger` - Red danger color

### Brand A Dark Theme
Switch to dark mode and verify:

- [ ] `bgSurface` - Dark background
- [ ] `bgElevated` - Lighter dark surface
- [ ] `fgPrimary` - Light text (high contrast on dark)
- [ ] `fgSecondary` - Dimmer light text
- [ ] All other colors adjust appropriately for dark mode
- [ ] Borders are visible but not harsh

### Brand B Light Theme
Switch to Brand B and verify:

- [ ] Brand colors are **different** from Brand A
- [ ] All 11 colors render correctly
- [ ] Colors maintain proper contrast ratios

### Brand B Dark Theme
Switch to Brand B Dark and verify:

- [ ] Brand colors differ from Brand A Dark
- [ ] All 11 colors render correctly
- [ ] Dark mode maintains readability

---

## 3. Typography Verification

For each theme combination, verify:

### Title Large (titleLG)
- [ ] Font size appears to be **22pt**
- [ ] Font weight is **Bold** (700)
- [ ] Line height appears appropriate (~28pt)
- [ ] Color matches `fgPrimary`

### Body Medium (bodyMD)
- [ ] Font size appears to be **15pt**
- [ ] Font weight is **Regular** (400)
- [ ] Line height appears appropriate (~22pt)
- [ ] Color matches `fgPrimary` for main text

### Label Small (labelSM)
- [ ] Font size appears to be **12pt**
- [ ] Font weight is **Semibold** (600)
- [ ] Line height appears appropriate (~16pt)
- [ ] Used for labels and captions

---

## 4. Spacing Scale Verification

Verify the spacing visualization bars:

- [ ] `xs` (4pt) - Very small bar
- [ ] `sm` (8pt) - Small bar
- [ ] `md` (12pt) - Medium bar
- [ ] `lg` (16pt) - Large bar
- [ ] `xl` (24pt) - Extra large bar
- [ ] `xxl` (32pt) - Largest bar

Check spacing consistency:

- [ ] Spacing between sections uses `xl` (24pt)
- [ ] Spacing within components uses `md` (12pt)
- [ ] Small gaps use `sm` (8pt)

---

## 5. Component Rendering

### PostCard Component
- [ ] Avatar circle renders with correct size (40pt diameter)
- [ ] Avatar shows first letter of author name
- [ ] Avatar background uses `brandPrimary`
- [ ] Avatar text uses `brandOn`
- [ ] Author name is bold and uses `labelSM`
- [ ] Timestamp is dimmer and uses `labelSM`
- [ ] Content text uses `bodyMD`
- [ ] Image placeholder (if present) renders correctly
- [ ] Action buttons (Like, Comment, Share) render
- [ ] Card has rounded corners (12pt radius)
- [ ] Card has subtle border
- [ ] Card background uses `bgSurface`

### Buttons
- [ ] Primary button has `brandPrimary` background
- [ ] Primary button text uses `brandOn`
- [ ] Secondary button has border
- [ ] Secondary button uses `bgElevated`
- [ ] Buttons have proper corner radius (12pt)
- [ ] Buttons have adequate padding

### State Indicators
- [ ] Success box shows green color
- [ ] Warning box shows yellow/orange color
- [ ] Danger box shows red color
- [ ] State boxes have semi-transparent backgrounds
- [ ] Icons are visible and properly colored

---

## 6. Border Radius Verification

Check corner radius consistency:

- [ ] Small radius (`sm` - 8pt) on color swatches
- [ ] Medium radius (`md` - 12pt) on cards and buttons
- [ ] PostCard corners are appropriately rounded

---

## 7. Cross-Theme Consistency

Test all 4 combinations and verify:

- [ ] All components maintain structure across themes
- [ ] Only colors change, not layout
- [ ] Spacing remains consistent
- [ ] Typography sizes remain consistent
- [ ] No elements are cut off or misaligned

---

## 8. Performance and Animations

- [ ] Theme switching is instant (no loading delay)
- [ ] No visible flickering when switching themes
- [ ] Scrolling is smooth
- [ ] No lag when toggling dark/light mode
- [ ] App remains responsive during interactions

---

## 9. Console Errors

Open the Xcode console and verify:

- [ ] No build errors
- [ ] No runtime warnings
- [ ] No "Cannot find color" errors
- [ ] No missing asset warnings
- [ ] No layout constraint errors

---

## 10. Asset Catalog Verification

In Xcode's Project Navigator, verify `Assets.xcassets` contains:

### Brand A Light
- [ ] `bgSurface.colorset`
- [ ] `bgElevated.colorset`
- [ ] `fgPrimary.colorset`
- [ ] `fgSecondary.colorset`
- [ ] `brandPrimary.colorset`
- [ ] `brandOn.colorset`
- [ ] `borderSubtle.colorset`
- [ ] `borderStrong.colorset`
- [ ] `stateSuccess.colorset`
- [ ] `stateWarning.colorset`
- [ ] `stateDanger.colorset`

### Brand A Dark
- [ ] All 11 color sets present

### Brand B Light
- [ ] All 11 color sets present

### Brand B Dark
- [ ] All 11 color sets present

---

## 11. Token Alignment Verification

Compare colors with source tokens file:

1. Open `/Users/proerror/Documents/nova/shared/design-tokens/tokens.design.json`
2. For each theme, verify at least 3 colors match the hex values in the JSON file

### Brand A Light Sample Check
- [ ] `brandPrimary` matches JSON value
- [ ] `fgPrimary` matches JSON value
- [ ] `bgSurface` matches JSON value

### Brand A Dark Sample Check
- [ ] Values differ from light theme as expected
- [ ] Colors maintain design system intent

---

## 12. Accessibility Checks

- [ ] All text is readable against backgrounds
- [ ] Contrast ratios appear sufficient
- [ ] Colors are distinguishable (test by enabling color blind simulation if available)
- [ ] Interactive elements have adequate hit areas (minimum 44pt)

---

## 13. iPad Compatibility (Optional)

If testing on iPad simulator:

- [ ] App scales appropriately
- [ ] Layout adapts to larger screen
- [ ] All themes work on iPad

---

## Final Verification

- [ ] All 4 theme combinations tested
- [ ] No crashes or freezes
- [ ] All components render as expected
- [ ] Design system tokens are correctly applied
- [ ] App is ready for further development/testing

---

## Issues Found

Document any issues below:

```
Issue 1: [Description]
Theme: [Brand A Light / Brand A Dark / Brand B Light / Brand B Dark]
Component: [PostCard / Button / etc.]
Expected: [What should happen]
Actual: [What actually happened]

Issue 2: ...
```

---

## Sign-Off

- **Tester Name**: ___________________
- **Date**: ___________________
- **Overall Status**: ☐ Pass  ☐ Fail  ☐ Pass with Minor Issues

---

## Next Steps

After verification:

1. If all checks pass, the design system implementation is validated
2. If issues are found, reference the console logs and Asset Catalog
3. Consider adding additional components to test the design system
4. Explore creating custom themes or extending the system

For questions or issues, refer to:
- [CREATE_XCODE_PROJECT.md](./CREATE_XCODE_PROJECT.md)
- [../README.md](../README.md)
- [../QUICKSTART.md](../QUICKSTART.md)
