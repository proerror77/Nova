# Localization Quick Reference Card

## 🚀 Quick Start (30 seconds)

### 1. Basic Text
```swift
Text(L10n.Common.cancel)
```

### 2. Parameterized String
```swift
Text(L10n.Post.likesCount(42))
```

### 3. Date Formatting
```swift
Text(date.fullDateString)
```

### 4. Number Formatting
```swift
Text(number.compactString)
```

### 5. Language Switching
```swift
localizationManager.setLanguage(.english)
```

---

## 📚 Documentation Files

| Quick Access | File Path |
|--------------|-----------|
| **Quick Start** | `Localization/README.md` |
| **Full Guide** | `Documentation/LOCALIZATION_GUIDE.md` |
| **Translation Map** | `Documentation/TRANSLATION_MATRIX.md` |
| **Examples** | `Examples/LocalizationExamples.swift` |
| **Final Delivery** | `LOCALIZATION_FINAL_DELIVERY.md` |

---

## 🎯 Common Tasks

### Add New String

1. **Add to L10n.swift**:
```swift
enum L10n {
    enum MyFeature {
        static let title = "my_feature.title".localized
    }
}
```

2. **Add to all Localizable.strings**:
```
"my_feature.title" = "My Feature";     // en
"my_feature.title" = "我的功能";        // zh-Hans
"my_feature.title" = "我的功能";        // zh-Hant
```

3. **Use in code**:
```swift
Text(L10n.MyFeature.title)
```

---

## 🌍 Supported Languages

| Language | Code | Status |
|----------|------|--------|
| 🇨🇳 Chinese Simplified | zh-Hans | ✅ 100% |
| 🇹🇼 Chinese Traditional | zh-Hant | ✅ 100% |
| 🇺🇸 English | en | ✅ 100% |

---

## 💡 Cheat Sheet

### String Access
```swift
// DO ✅
Text(L10n.Common.cancel)

// DON'T ❌
Text("Cancel")
Text("common.cancel")
```

### Dates
```swift
date.fullDateString      // "2024年10月19日" / "October 19, 2024"
date.shortDateString     // "2024/10/19" / "10/19/24"
date.relativeTimeString  // "2小时前" / "2 hours ago"
date.smartTimeString     // Today: "下午3:30" / "3:30 PM"
```

### Numbers
```swift
number.standardString    // "1,234,567"
number.compactString     // "1.2M"
price.currencyString()   // "$99.99"
percent.percentString    // "75%"
```

### Language
```swift
// Get current
localizationManager.currentLanguage

// Switch language
localizationManager.setLanguage(.english)
localizationManager.setLanguage(.chineseSimplified)
localizationManager.setLanguage(.chineseTraditional)
```

---

## 🔧 File Locations

```
Localization/          # Core framework
Resources/*/           # Translations
Views/Settings/        # Language picker UI
Documentation/         # Guides
Examples/             # Code examples
```

---

## 🎯 Stats

- **Languages**: 3
- **Strings**: 106 per language
- **Total Translations**: 318
- **Coverage**: 100%

---

**Version**: 1.0.0
**Status**: ✅ Production Ready
