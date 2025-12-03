import SwiftUI

// MARK: - Localization Usage Examples

/// 示例 1: 基本文本本地化
struct BasicLocalizationExample: View {
    var body: some View {
        VStack(spacing: 16) {
            // 方法 A: 使用 L10n 枚举（推荐）
            Text(L10n.Common.cancel)

            // 方法 B: 使用 String 扩展
            Text("common.confirm".localized)

            // 方法 C: LocalizedStringKey（SwiftUI 自动查找）
            Text("common.save")

            // 按钮
            Button(L10n.Common.done) {
                print("Done tapped")
            }
        }
        .padding()
    }
}

/// 示例 2: 带参数的本地化字符串
struct ParameterizedLocalizationExample: View {
    let likeCount = 42
    let username = "Alice"

    var body: some View {
        VStack(spacing: 16) {
            // 单个整数参数
            Text(L10n.Post.likesCount(likeCount))
            // zh-Hans: "42 个赞"
            // en: "42 likes"

            // 字符串参数
            Text(L10n.Notification.followedYou(username: username))
            // zh-Hans: "Alice 关注了你"
            // en: "Alice followed you"

            // 多个参数
            let format = String.localizedStringWithFormat(
                "post.time_ago.hours".localized,
                2
            )
            Text(format)
            // zh-Hans: "2 小时前"
            // en: "2 hours ago"
        }
        .padding()
    }
}

/// 示例 3: 日期时间格式化
struct DateTimeFormattingExample: View {
    let date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("Full Date:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(date.fullDateString)
                    .font(.body)
                // zh-Hans: "2024年10月19日"
                // en: "October 19, 2024"
            }

            Divider()

            Group {
                Text("Short Date:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(date.shortDateString)
                    .font(.body)
                // zh-Hans: "2024/10/19"
                // en: "10/19/24"
            }

            Divider()

            Group {
                Text("Time:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(date.shortTimeString)
                    .font(.body)
                // zh-Hans: "下午3:30"
                // en: "3:30 PM"
            }

            Divider()

            Group {
                Text("Relative Time:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(date.relativeTimeString)
                    .font(.body)
                // zh-Hans: "刚刚"
                // en: "just now"
            }

            Divider()

            Group {
                Text("Smart Time:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(date.smartTimeString)
                    .font(.body)
                // Today: "下午3:30" / "3:30 PM"
                // Yesterday: "昨天 下午3:30"
                // Older: "2024/10/15"
            }
        }
        .padding()
    }
}

/// 示例 4: 数字格式化
struct NumberFormattingExample: View {
    let largeNumber = 1234567
    let price = 99.99
    let percentage = 0.75

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("Standard Number:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(largeNumber.standardString)
                    .font(.body)
                // "1,234,567"
            }

            Divider()

            Group {
                Text("Compact Number:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(largeNumber.compactString)
                    .font(.body)
                // "1.2M"
            }

            Divider()

            Group {
                Text("Currency (USD):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(price.currencyString(code: "USD"))
                    .font(.body)
                // zh-Hans: "US$99.99"
                // en: "$99.99"
            }

            Divider()

            Group {
                Text("Percentage:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(percentage.percentString)
                    .font(.body)
                // "75%"
            }

            Divider()

            Group {
                Text("Ordinal:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(3.ordinalString)
                    .font(.body)
                // zh-Hans: "第3"
                // en: "3rd"
            }
        }
        .padding()
    }
}

/// 示例 5: 语言切换
struct LanguageSwitchingExample: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("Current Language:")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(localizationManager.currentLanguage.nativeName)
                .font(.title2)
                .fontWeight(.bold)

            Divider()

            VStack(spacing: 12) {
                Button("简体中文") {
                    withAnimation {
                        localizationManager.setLanguage(.chineseSimplified)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localizationManager.currentLanguage == .chineseSimplified)

                Button("繁體中文") {
                    withAnimation {
                        localizationManager.setLanguage(.chineseTraditional)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localizationManager.currentLanguage == .chineseTraditional)

                Button("English") {
                    withAnimation {
                        localizationManager.setLanguage(.english)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(localizationManager.currentLanguage == .english)
            }

            Divider()

            // 本地化内容示例
            VStack(spacing: 8) {
                Text(L10n.Feed.title)
                    .font(.headline)

                HStack {
                    Button(L10n.Common.cancel) { }
                        .buttonStyle(.bordered)
                    Button(L10n.Common.confirm) { }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}

/// 示例 6: 完整的本地化 View
struct CompleteLocalizedViewExample: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared

    let post = MockPost(
        author: "Alice",
        likes: 42,
        comments: 15,
        shares: 3,
        createdAt: Date().addingTimeInterval(-3600 * 2) // 2 hours ago
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text(post.author)
                    .font(.headline)
                Spacer()
                Text(post.createdAt.relativeTimeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Content (would be actual post content)
            Text("This is a sample post content.")
                .font(.body)

            Divider()

            // Actions
            HStack(spacing: 24) {
                // Like
                HStack(spacing: 4) {
                    Image(systemName: "heart")
                    Text(post.likes.compactString)
                }

                // Comment
                HStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                    Text(post.comments.compactString)
                }

                // Share
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text(post.shares.compactString)
                }

                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)

            // Detailed Stats
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Post.likesCount(post.likes))
                Text(L10n.Post.commentsCount(post.comments))
                Text(L10n.Post.sharesCount(post.shares))
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
        .padding()
    }
}

// MARK: - Mock Data

struct MockPost {
    let author: String
    let likes: Int
    let comments: Int
    let shares: Int
    let createdAt: Date
}

// MARK: - Preview

struct LocalizationExamples_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                List {
                    Section("Basic Localization") {
                        BasicLocalizationExample()
                    }

                    Section("Parameterized Strings") {
                        ParameterizedLocalizationExample()
                    }

                    Section("Date & Time Formatting") {
                        DateTimeFormattingExample()
                    }

                    Section("Number Formatting") {
                        NumberFormattingExample()
                    }

                    Section("Language Switching") {
                        LanguageSwitchingExample()
                    }

                    Section("Complete Example") {
                        CompleteLocalizedViewExample()
                    }
                }
                .navigationTitle("Localization Examples")
            }
            .previewDisplayName("Chinese Simplified")
            .environment(\.locale, .init(identifier: "zh-Hans"))

            NavigationView {
                List {
                    Section("Basic Localization") {
                        BasicLocalizationExample()
                    }

                    Section("Parameterized Strings") {
                        ParameterizedLocalizationExample()
                    }

                    Section("Date & Time Formatting") {
                        DateTimeFormattingExample()
                    }

                    Section("Number Formatting") {
                        NumberFormattingExample()
                    }

                    Section("Language Switching") {
                        LanguageSwitchingExample()
                    }

                    Section("Complete Example") {
                        CompleteLocalizedViewExample()
                    }
                }
                .navigationTitle("Localization Examples")
            }
            .previewDisplayName("English")
            .environment(\.locale, .init(identifier: "en"))
        }
    }
}
