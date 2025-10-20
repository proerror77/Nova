# Localization System

## Quick Start

### 1. Use Localized Strings in Views

```swift
import SwiftUI

struct MyView: View {
    var body: some View {
        VStack {
            // Method 1: L10n enum (Recommended)
            Text(L10n.Common.cancel)

            // Method 2: String extension
            Text("common.confirm".localized)

            // Method 3: Button with localized title
            Button(L10n.Common.save) {
                // Action
            }
        }
    }
}
```

### 2. Use Parameterized Strings

```swift
// Single parameter
Text(L10n.Post.likesCount(42))
// Output: "42 个赞" / "42 likes"

// String parameter
Text(L10n.Notification.followedYou(username: "Alice"))
// Output: "Alice 关注了你" / "Alice followed you"
```

### 3. Format Dates and Numbers

```swift
let date = Date()
let number = 1234567

// Date formatting
Text(date.fullDateString)  // "2024年10月19日" / "October 19, 2024"
Text(date.relativeTimeString)  // "2小时前" / "2 hours ago"

// Number formatting
Text(number.compactString)  // "1.2M"
Text(99.99.currencyString(code: "USD"))  // "$99.99"
```

### 4. Switch Language

```swift
import SwiftUI

struct LanguageSwitcher: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        Button("Switch to English") {
            localizationManager.setLanguage(.english)
        }
    }
}
```

## File Structure

```
Localization/
├── Language.swift                  # Language enum
├── LocalizationManager.swift       # Localization manager (singleton)
├── L10n.swift                      # Type-safe string accessor
├── DateTimeFormatters.swift        # Date/time formatting
└── NumberFormatters.swift          # Number formatting

Resources/
├── zh-Hans.lproj/
│   └── Localizable.strings         # Chinese Simplified
├── zh-Hant.lproj/
│   └── Localizable.strings         # Chinese Traditional
└── en.lproj/
    └── Localizable.strings         # English
```

## Key Components

### Language.swift
Defines supported languages and locale mapping.

### LocalizationManager.swift
- Manages current language
- Automatically switches Bundle
- Persists language preference to UserDefaults
- Integrates with SwiftUI Environment

### L10n.swift
Type-safe accessor for all localized strings:
- `L10n.Common.*` - Common strings
- `L10n.Auth.*` - Authentication
- `L10n.Feed.*` - Feed
- `L10n.Post.*` - Posts
- `L10n.Profile.*` - Profile
- etc.

### DateTimeFormatters.swift
Date and time formatting utilities:
- `date.fullDateString`
- `date.shortDateString`
- `date.relativeTimeString`
- `date.smartTimeString`

### NumberFormatters.swift
Number formatting utilities:
- `number.standardString` - "1,234,567"
- `number.compactString` - "1.2M"
- `number.currencyString(code:)` - "$99.99"
- `number.percentString` - "75%"

## Supported Languages

- 🇨🇳 Chinese Simplified (zh-Hans)
- 🇹🇼 Chinese Traditional (zh-Hant)
- 🇺🇸 English (en)

## Translation Coverage

✅ **100% Complete** - 107 strings fully translated across all languages

## Documentation

- **[LOCALIZATION_GUIDE.md](../Documentation/LOCALIZATION_GUIDE.md)** - Complete usage guide
- **[TRANSLATION_MATRIX.md](../Documentation/TRANSLATION_MATRIX.md)** - Translation matrix and quality checklist
- **[LOCALIZATION_IMPLEMENTATION_SUMMARY.md](../LOCALIZATION_IMPLEMENTATION_SUMMARY.md)** - Implementation summary

## Examples

See `Examples/LocalizationExamples.swift` for complete code examples.

## Adding New Strings

1. Add to `L10n.swift`:
```swift
enum L10n {
    enum MyFeature {
        static let title = "my_feature.title".localized
    }
}
```

2. Add to all `Localizable.strings` files:
```
"my_feature.title" = "My Feature";  // en
"my_feature.title" = "我的功能";     // zh-Hans
"my_feature.title" = "我的功能";     // zh-Hant
```

3. Use in code:
```swift
Text(L10n.MyFeature.title)
```

## Best Practices

✅ **DO**:
- Use `L10n` enum for type safety
- Use formatters for dates and numbers
- Avoid hardcoded user-visible strings
- Test all supported languages

❌ **DON'T**:
- Hardcode strings: `Text("Cancel")`
- Concatenate strings: `"\(user.name) followed you"`
- Use magic strings: `Text("common.cancel")`
- Forget to add translations to all languages

---

**Version**: 1.0.0
**Last Updated**: 2024-10-19
