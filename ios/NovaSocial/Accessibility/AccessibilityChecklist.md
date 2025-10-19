# Accessibility Checklist (WCAG 2.1 AA)

## ✅ Completed Features

This checklist ensures NovaSocial meets WCAG 2.1 Level AA standards for accessibility.

---

## 1. Perceivable

### 1.1 Text Alternatives (A)

- [ ] **1.1.1 Non-text Content**: All images, icons, and graphics have text alternatives
  - [ ] Profile avatars have `accessibilityLabel` with username
  - [ ] Post images have descriptive labels
  - [ ] Decorative images are marked `accessibilityHidden(true)`
  - [ ] Icons in buttons have labels (like, share, comment)
  - [ ] Logo has alternative text

**Testing**:
```swift
// Enable VoiceOver and navigate through the app
// All interactive images should announce their purpose
```

### 1.2 Time-based Media (A/AA)

- [ ] **1.2.1 Audio-only and Video-only**: Alternatives provided for media
  - [ ] Video posts have captions option
  - [ ] Audio descriptions available for video content
  - [ ] Transcripts available for audio content

- [ ] **1.2.4 Captions (Live)**: Live video has captions
  - [ ] Live streaming includes real-time captions

### 1.3 Adaptable (A)

- [ ] **1.3.1 Info and Relationships**: Structure is programmatically determinable
  - [ ] Headings use proper hierarchy (`accessibilityAddTraits(.isHeader)`)
  - [ ] Lists use semantic markup
  - [ ] Form labels associated with inputs
  - [ ] Tables have headers

- [ ] **1.3.2 Meaningful Sequence**: Reading order is logical
  - [ ] VoiceOver navigation follows visual layout
  - [ ] Tab order makes sense for keyboard navigation

- [ ] **1.3.3 Sensory Characteristics**: Instructions don't rely solely on sensory characteristics
  - [ ] Color is not the only indicator of state
  - [ ] Shape/position combined with text labels
  - [ ] Sound alerts include visual indicators

- [ ] **1.3.4 Orientation**: Content adapts to portrait and landscape
  - [ ] No orientation lock (unless essential)
  - [ ] Layout responds to rotation

- [ ] **1.3.5 Identify Input Purpose**: Form fields have autocomplete hints
  - [ ] Email fields: `.textContentType(.emailAddress)`
  - [ ] Username fields: `.textContentType(.username)`
  - [ ] Password fields: `.textContentType(.password)`

### 1.4 Distinguishable (A/AA)

- [ ] **1.4.1 Use of Color**: Color is not the only visual means of conveying information
  - [ ] Error states use icon + color
  - [ ] Required fields marked with * and label
  - [ ] Links underlined or have other distinguishing feature

- [ ] **1.4.2 Audio Control**: Audio can be paused/stopped
  - [ ] Video player has pause/stop controls
  - [ ] Autoplay can be disabled

- [ ] **1.4.3 Contrast (Minimum)**: 4.5:1 for normal text, 3:1 for large text
  - [ ] All text meets contrast requirements
  - [ ] Use `AccessibilityHelper.meetsContrastRequirement()`
  - [ ] Test with dark mode and light mode

**Testing**:
```swift
// Use contrast checker
let foreground = Color.primary.uiColor
let background = Color.background.uiColor
let ratio = AccessibilityHelper.contrastRatio(foreground: foreground, background: background)
print("Contrast ratio: \(ratio):1") // Should be >= 4.5:1
```

- [ ] **1.4.4 Resize Text**: Text can be resized up to 200% without loss of content
  - [ ] All text uses Dynamic Type
  - [ ] Layout doesn't break at accessibility sizes
  - [ ] Test with largest accessibility category

**Testing**:
```swift
// Settings > Accessibility > Display & Text Size > Larger Text
// Enable Larger Accessibility Sizes
// All text should scale appropriately
```

- [ ] **1.4.5 Images of Text**: Use real text instead of images of text
  - [ ] Avoid text in images (except logos)
  - [ ] Use attributed strings for styled text

- [ ] **1.4.10 Reflow**: Content reflows for different viewport sizes
  - [ ] No horizontal scrolling required at 320pt width
  - [ ] Text wraps appropriately

- [ ] **1.4.11 Non-text Contrast**: UI components have 3:1 contrast
  - [ ] Buttons, borders, icons have sufficient contrast
  - [ ] Focus indicators are visible

- [ ] **1.4.12 Text Spacing**: Text adapts to user-defined spacing
  - [ ] Line height >= 1.5x font size
  - [ ] Paragraph spacing >= 2x font size
  - [ ] Letter spacing >= 0.12x font size
  - [ ] Word spacing >= 0.16x font size

- [ ] **1.4.13 Content on Hover or Focus**: Additional content is dismissible and hoverable
  - [ ] Tooltips can be dismissed
  - [ ] Hover content doesn't obscure other content
  - [ ] Pointer can move over hover content

---

## 2. Operable

### 2.1 Keyboard Accessible (A)

- [ ] **2.1.1 Keyboard**: All functionality available via keyboard
  - [ ] Full keyboard navigation support
  - [ ] Tab key moves between interactive elements
  - [ ] Enter/Space activates buttons
  - [ ] Arrow keys navigate lists

- [ ] **2.1.2 No Keyboard Trap**: Focus can move away from all components
  - [ ] Modal dialogs have close button
  - [ ] No infinite loops in tab order
  - [ ] Escape key closes overlays

- [ ] **2.1.4 Character Key Shortcuts**: Single-key shortcuts can be disabled or remapped
  - [ ] No single-key shortcuts, or they can be turned off
  - [ ] Shortcuts require modifier keys (Cmd, Option, etc.)

### 2.2 Enough Time (A)

- [ ] **2.2.1 Timing Adjustable**: Time limits can be extended or disabled
  - [ ] No automatic timeouts, or user can extend
  - [ ] Session timeout warnings with 20 seconds to respond

- [ ] **2.2.2 Pause, Stop, Hide**: Moving/auto-updating content can be controlled
  - [ ] Autoplay videos have pause button
  - [ ] Carousels have pause button
  - [ ] Animated content respects Reduce Motion

**Testing**:
```swift
// Settings > Accessibility > Motion > Reduce Motion
// All animations should be simplified or removed
AccessibilityHelper.isReduceMotionEnabled // true
```

### 2.3 Seizures and Physical Reactions (A)

- [ ] **2.3.1 Three Flashes or Below Threshold**: No content flashes more than 3 times per second
  - [ ] No rapid flashing animations
  - [ ] Loading spinners rotate smoothly
  - [ ] Alert animations are gentle

### 2.4 Navigable (A/AA)

- [ ] **2.4.1 Bypass Blocks**: Mechanism to skip repeated content
  - [ ] Main content has accessibility heading
  - [ ] Skip links for long lists

- [ ] **2.4.2 Page Titled**: Screens have descriptive titles
  - [ ] Navigation titles are clear
  - [ ] Screen changes announce new title

- [ ] **2.4.3 Focus Order**: Focus order preserves meaning
  - [ ] Tab order follows visual layout
  - [ ] VoiceOver reads in logical sequence

- [ ] **2.4.4 Link Purpose (In Context)**: Link purpose can be determined from text
  - [ ] Links have descriptive text (avoid "click here")
  - [ ] Button labels describe action

- [ ] **2.4.5 Multiple Ways**: Multiple ways to find content
  - [ ] Search functionality
  - [ ] Navigation tabs
  - [ ] Recent/trending sections

- [ ] **2.4.6 Headings and Labels**: Headings and labels describe topic/purpose
  - [ ] Section headings use `.accessibilityAddTraits(.isHeader)`
  - [ ] Form labels clearly describe fields

- [ ] **2.4.7 Focus Visible**: Keyboard focus indicator is visible
  - [ ] Focused elements have visible outline
  - [ ] Custom focus styles meet 3:1 contrast

### 2.5 Input Modalities (A)

- [ ] **2.5.1 Pointer Gestures**: All multi-point/path-based gestures have single-pointer alternative
  - [ ] Pinch-to-zoom has button alternative
  - [ ] Swipe gestures have button alternative

- [ ] **2.5.2 Pointer Cancellation**: Actions execute on up-event
  - [ ] Button actions trigger on touch up
  - [ ] Can cancel by dragging away

- [ ] **2.5.3 Label in Name**: Accessible name contains visible text
  - [ ] `accessibilityLabel` includes button text
  - [ ] Voice Control users can activate by visible label

- [ ] **2.5.4 Motion Actuation**: Functionality can be operated without device motion
  - [ ] Shake-to-undo has button alternative
  - [ ] Tilt gestures have alternatives

---

## 3. Understandable

### 3.1 Readable (A)

- [ ] **3.1.1 Language of Page**: Primary language of page is programmatically determined
  - [ ] `accessibilityLanguage` set where needed
  - [ ] VoiceOver uses correct pronunciation

- [ ] **3.1.2 Language of Parts**: Language of parts can be programmatically determined
  - [ ] Multi-language content marked appropriately

### 3.2 Predictable (A)

- [ ] **3.2.1 On Focus**: No unexpected context changes on focus
  - [ ] Focus doesn't trigger navigation
  - [ ] No automatic form submission

- [ ] **3.2.2 On Input**: No unexpected context changes on input
  - [ ] Text field changes don't navigate away
  - [ ] Checkbox doesn't trigger submission

- [ ] **3.2.3 Consistent Navigation**: Navigation is consistent
  - [ ] Tab bar always in same position
  - [ ] Navigation patterns consistent across screens

- [ ] **3.2.4 Consistent Identification**: Components with same functionality have consistent labels
  - [ ] "Like" button always labeled "Like"
  - [ ] Icons used consistently

### 3.3 Input Assistance (A/AA)

- [ ] **3.3.1 Error Identification**: Errors are identified and described
  - [ ] Form validation shows clear messages
  - [ ] Error announcements for screen readers
  - [ ] VoiceOver reads error messages

**Testing**:
```swift
AccessibilityHelper.announce("Invalid email address", priority: .announcement)
```

- [ ] **3.3.2 Labels or Instructions**: Labels/instructions provided for user input
  - [ ] All form fields have labels
  - [ ] Placeholder text is not the only label
  - [ ] Password requirements stated

- [ ] **3.3.3 Error Suggestion**: Suggestions provided for input errors
  - [ ] "Did you mean..." suggestions
  - [ ] Autocorrect for common mistakes

- [ ] **3.3.4 Error Prevention (Legal, Financial, Data)**: Submissions can be reviewed/corrected
  - [ ] Confirmation dialogs for destructive actions
  - [ ] Review step before posting
  - [ ] Undo functionality

---

## 4. Robust

### 4.1 Compatible (A)

- [ ] **4.1.1 Parsing**: Content can be parsed reliably
  - [ ] Valid SwiftUI/UIKit structure
  - [ ] No duplicate IDs

- [ ] **4.1.2 Name, Role, Value**: UI components have programmatically determinable properties
  - [ ] Buttons have `.button` trait
  - [ ] Links have `.link` trait
  - [ ] Toggles have `.isSelected` state
  - [ ] Custom controls expose state

- [ ] **4.1.3 Status Messages**: Status messages are programmatically determinable
  - [ ] Success/error messages announced
  - [ ] Loading states communicated
  - [ ] Progress updates announced

**Testing**:
```swift
AccessibilityHelper.announce("Post created successfully")
```

---

## Testing Procedures

### 1. VoiceOver Testing

```swift
// Enable VoiceOver: Settings > Accessibility > VoiceOver
// Gestures:
// - Swipe right: Next element
// - Swipe left: Previous element
// - Double tap: Activate
// - Two-finger double tap: Magic tap (play/pause)
// - Rotor: Two fingers rotate to change navigation mode
```

**Checklist**:
- [ ] All interactive elements are announced
- [ ] Reading order is logical
- [ ] Custom actions are available
- [ ] State changes are announced
- [ ] Images have appropriate labels
- [ ] Decorative elements are hidden

### 2. Dynamic Type Testing

```swift
// Settings > Accessibility > Display & Text Size > Larger Text
// Test all accessibility sizes
```

**Checklist**:
- [ ] Text scales appropriately
- [ ] Layout doesn't break
- [ ] No text truncation
- [ ] Buttons remain accessible
- [ ] Images scale with text (if appropriate)

### 3. Reduce Motion Testing

```swift
// Settings > Accessibility > Motion > Reduce Motion
```

**Checklist**:
- [ ] Animations are disabled or simplified
- [ ] Transitions are instant
- [ ] Auto-play is disabled
- [ ] Parallax effects removed

### 4. Keyboard Navigation Testing

**Checklist**:
- [ ] Tab key navigates all interactive elements
- [ ] Tab order is logical
- [ ] Enter/Space activates buttons
- [ ] Escape closes modals
- [ ] Arrow keys navigate lists
- [ ] No keyboard traps

### 5. Contrast Testing

```swift
// Use AccessibilityHelper.contrastRatio()
// Test in both light and dark modes
```

**Checklist**:
- [ ] Text: >= 4.5:1 (normal) or >= 3:1 (large)
- [ ] UI components: >= 3:1
- [ ] Test with color blindness simulator

### 6. Touch Target Testing

```swift
// All interactive elements >= 44x44pt
// Use AccessibilityHelper.validateTouchTarget()
```

**Checklist**:
- [ ] Buttons meet minimum size
- [ ] Links have adequate spacing
- [ ] Icons are large enough
- [ ] Padding increases touch area

---

## Automated Testing

### Unit Tests

```swift
func testAccessibilityLabels() {
    let button = LikeButton()
    XCTAssertNotNil(button.accessibilityLabel)
    XCTAssertFalse(button.accessibilityLabel.isEmpty)
}

func testTouchTargetSize() {
    let button = LikeButton()
    let size = button.frame.size
    XCTAssertTrue(AccessibilityHelper.validateTouchTarget(size: size))
}

func testContrastRatio() {
    let foreground = Color.primary
    let background = Color.background
    let ratio = foreground.contrastRatio(with: background)
    XCTAssertGreaterThanOrEqual(ratio, 4.5)
}
```

### UI Tests

```swift
func testVoiceOverNavigation() {
    app.launch()

    // Enable VoiceOver in simulator
    XCUIDevice.shared.voiceOverEnabled = true

    // Navigate through elements
    let firstElement = app.staticTexts.firstMatch
    XCTAssertTrue(firstElement.exists)

    // Swipe to next element
    firstElement.swipeRight()

    XCUIDevice.shared.voiceOverEnabled = false
}
```

---

## Quick Reference: Accessibility Traits

```swift
// SwiftUI Traits
.accessibilityAddTraits(.isButton)
.accessibilityAddTraits(.isHeader)
.accessibilityAddTraits(.isImage)
.accessibilityAddTraits(.isLink)
.accessibilityAddTraits(.isSearchField)
.accessibilityAddTraits(.isSelected)
.accessibilityAddTraits(.playsSound)
.accessibilityAddTraits(.startsMediaSession)
.accessibilityAddTraits(.updatesFrequently)
.accessibilityAddTraits(.allowsDirectInteraction)
.accessibilityAddTraits(.causesPageTurn)
```

---

## Resources

- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Apple Accessibility Documentation](https://developer.apple.com/accessibility/)
- [SwiftUI Accessibility Modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [iOS Human Interface Guidelines - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

---

## Sign-off

- [ ] **Developer**: All accessibility features implemented
- [ ] **QA**: All test cases pass
- [ ] **Accessibility Specialist**: WCAG 2.1 AA compliance verified
- [ ] **Product Manager**: Feature approved for release
