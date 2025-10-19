# Nova iOS - Accessibility Guide

## Target: WCAG 2.1 AA Compliance

## VoiceOver Support

### Image Labels
All images must have descriptive labels:

```swift
Image(systemName: "heart.fill")
    .accessibilityLabel("Like button")
    .accessibilityHint("Double tap to like this post")
```

### Button Actions
```swift
Button("Sign In") { }
    .accessibilityLabel("Sign In")
    .accessibilityHint("Sign in to your account")
```

### Post Cards
```swift
PostCard(post: post)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(post.author.displayName) posted \(post.caption ?? "a photo")")
    .accessibilityHint("Double tap to view details")
```

## Dynamic Type Support

### Font Scaling
All text must use Theme.Typography (which uses `.system()` fonts):

```swift
Text("Hello")
    .font(Theme.Typography.body) // Auto-scales with user settings
```

### Test Sizes
Test app with all Dynamic Type sizes:
- Extra Small (xS)
- Small (S)
- Medium (M) - Default
- Large (L)
- Extra Large (xL)
- Accessibility Large (aL)
- Accessibility Extra Large (axL)

### Layout Constraints
Avoid fixed heights for text containers:
```swift
// ❌ Bad
Text(caption)
    .frame(height: 50)

// ✅ Good
Text(caption)
    .lineLimit(nil) // Allow wrapping
    .fixedSize(horizontal: false, vertical: true)
```

## Color Contrast

### Minimum Ratios (WCAG AA)
- **Normal text (< 18pt):** 4.5:1
- **Large text (≥ 18pt):** 3:1
- **UI components:** 3:1

### Theme Colors
All Theme.Colors must pass contrast checks:
- `textPrimary` on `background`: 4.5:1 ✅
- `textSecondary` on `background`: 4.5:1 ✅
- `primary` on `onPrimary`: 4.5:1 ✅

### Testing Tools
- Xcode Accessibility Inspector
- Contrast Checker: https://webaim.org/resources/contrastchecker/

## Reduce Motion

Support users with motion sensitivity:

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

var body: some View {
    view
        .animation(reduceMotion ? .none : .default, value: state)
}
```

Disable animations when `reduceMotion` is enabled:
- Skeleton loader shimmer
- Page transitions
- Like heart animation

## Focus Management

### Navigation
Ensure focus moves logically when navigating:

```swift
@AccessibilityFocusState var focusedField: Field?

TextField("Username", text: $username)
    .accessibilityFocused($focusedField, equals: .username)

SecureField("Password", text: $password)
    .accessibilityFocused($focusedField, equals: .password)
    .onSubmit {
        focusedField = .password // Move focus to password
    }
```

### Alerts & Errors
Use `.announcement()` for important messages:

```swift
Text("Sign in failed")
    .accessibilityAddTraits(.isStaticText)
    .accessibilityElement(children: .combine)
    .accessibilityAnnouncement("Sign in failed. Please check your credentials.")
```

## Accessibility Traits

### Buttons
```swift
Button("Like") { }
    .accessibilityAddTraits(.isButton)
    .accessibilityRemoveTraits(.isImage) // If using Image as button
```

### Headers
```swift
Text("Feed")
    .font(Theme.Typography.h1)
    .accessibilityAddTraits(.isHeader)
```

### Selected State
```swift
TabView {
    FeedView()
        .tabItem { Label("Home", systemImage: "house") }
        .accessibilityAddTraits(selectedTab == .feed ? .isSelected : [])
}
```

## Form Accessibility

### Field Labels
Always provide labels for form fields:

```swift
VStack(alignment: .leading) {
    Text("Email")
        .font(Theme.Typography.label)
        .accessibilityAddTraits(.isStaticText)

    TextField("", text: $email)
        .accessibilityLabel("Email address")
        .accessibilityHint("Enter your email")
}
```

### Error States
```swift
if let error = emailError {
    Text(error)
        .foregroundColor(Theme.Colors.error)
        .accessibilityLabel("Email error: \(error)")
}
```

## List Accessibility

### Post Feed
```swift
LazyVStack {
    ForEach(posts) { post in
        PostCard(post: post)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(postLabel(for: post))
            .accessibilityHint("Double tap to view details")
    }
}
.accessibilityLabel("Feed")
.accessibilityHint("Swipe up or down to scroll through posts")
```

### Helper Function
```swift
func postLabel(for post: Post) -> String {
    var label = "\(post.author.displayName) posted"
    if let caption = post.caption {
        label += " \(caption)"
    }
    label += ". \(post.likeCount) likes, \(post.commentCount) comments."
    return label
}
```

## Image Accessibility

### Alt Text
Provide meaningful descriptions:

```swift
AsyncImage(url: post.imageURL) { image in
    image
        .resizable()
        .accessibilityLabel(post.caption ?? "Post image")
}
```

### Decorative Images
Mark decorative images as hidden:

```swift
Image("decorative-pattern")
    .accessibilityHidden(true)
```

## Testing Checklist

### VoiceOver
- [ ] Navigate entire app with VoiceOver only
- [ ] All buttons announce their purpose
- [ ] All images have labels (except decorative)
- [ ] Forms announce field labels and errors
- [ ] Notifications announce correctly

### Dynamic Type
- [ ] Test at all 7 Dynamic Type sizes
- [ ] No text truncation at largest size
- [ ] Layouts reflow correctly
- [ ] No overlapping elements

### Color Contrast
- [ ] All text passes 4.5:1 ratio
- [ ] UI components pass 3:1 ratio
- [ ] Test in light and dark modes

### Reduce Motion
- [ ] Animations disabled when enabled
- [ ] App still functional without animations

### Switch Control
- [ ] All interactive elements reachable
- [ ] Focus order logical
- [ ] No focus traps

## Common Issues & Fixes

### Issue: Image button not accessible
```swift
// ❌ Bad
Image(systemName: "heart")
    .onTapGesture { }

// ✅ Good
Button(action: { }) {
    Image(systemName: "heart")
}
.accessibilityLabel("Like")
```

### Issue: Text truncated at large sizes
```swift
// ❌ Bad
Text(caption)
    .lineLimit(2)

// ✅ Good
Text(caption)
    .lineLimit(nil)
    .fixedSize(horizontal: false, vertical: true)
```

### Issue: Low contrast text
```swift
// ❌ Bad
Text("Subtitle")
    .foregroundColor(.gray.opacity(0.3)) // Too light

// ✅ Good
Text("Subtitle")
    .foregroundColor(Theme.Colors.textSecondary) // 4.5:1 contrast
```

## Resources

- [Apple Accessibility Guidelines](https://developer.apple.com/accessibility/)
- [WCAG 2.1 AA](https://www.w3.org/WAI/WCAG21/quickref/?currentsidebar=%23col_customize&levels=aaa)
- [SwiftUI Accessibility](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [Xcode Accessibility Inspector](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXTestingApps.html)
