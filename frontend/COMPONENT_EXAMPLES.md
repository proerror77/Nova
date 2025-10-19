# Nova Design System - 组件示例库

完整的跨平台组件实现示例，展示如何正确使用 Design Tokens。

## 📋 包含内容

1. [PostCard](#postcard-卡片组件) - Instagram 风格卡片
2. [Button](#button-按钮) - 品牌按钮
3. [TextField](#textfield-输入框) - 表单输入
4. [Avatar](#avatar-头像) - 用户头像
5. [Badge](#badge-徽章) - 状态徽章

---

## PostCard 卡片组件

### 使用场景

显示用户发布的内容（图片 + 文字 + 互动）。

### iOS 实现

```swift
import SwiftUI

struct PostCard: View {
    @Environment(\.theme) var theme

    let author: String
    let content: String
    let imageURL: URL?
    @State var isLiked = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部 - 作者信息
            HStack(spacing: theme.space.md) {
                Circle()
                    .fill(theme.colors.brandPrimary)
                    .frame(width: theme.metric.avatarSM, height: theme.metric.avatarSM)

                Text(author)
                    .font(theme.type.bodyMD)
                    .foregroundColor(theme.colors.fgPrimary)

                Spacer()

                Image(systemName: "ellipsis")
                    .foregroundColor(theme.colors.fgSecondary)
            }
            .padding(theme.space.md)

            Divider()
                .background(theme.colors.borderSubtle)

            // 内容 - 图片
            if let imageURL = imageURL {
                AsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    ProgressView()
                        .frame(height: 300)
                }
                .frame(height: 300)
            }

            // 互动栏
            HStack(spacing: theme.space.lg) {
                Button(action: { isLiked.toggle() }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? .red : theme.colors.fgSecondary)
                }

                Button(action: {}) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(theme.colors.fgSecondary)
                }

                Button(action: {}) {
                    Image(systemName: "paperplane")
                        .foregroundColor(theme.colors.fgSecondary)
                }

                Spacer()
            }
            .font(.system(size: theme.metric.iconMD))
            .padding(theme.space.md)

            Divider()
                .background(theme.colors.borderSubtle)

            // 文字内容
            Text(content)
                .font(theme.type.bodyMD)
                .foregroundColor(theme.colors.fgPrimary)
                .padding(theme.space.md)
        }
        .background(theme.colors.bgElevated)
        .cornerRadius(theme.metric.postCorner)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metric.postCorner)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
    }
}

#Preview("BrandA Light") {
    PostCard(
        author: "John Doe",
        content: "Amazing sunset today! 🌅",
        imageURL: URL(string: "https://...")
    )
    .theme(.brandA, colorScheme: .light)
    .padding(theme.space.lg)
}
```

### Android 实现

```kotlin
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage

@Composable
fun PostCard(
    author: String,
    content: String,
    imageUrl: String? = null,
    modifier: Modifier = Modifier
) {
    val colors = LocalColorScheme.current
    val spacing = LocalSpacing.current
    val metric = LocalMetric.current

    var isLiked by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .background(
                colors.bgElevated,
                RoundedCornerShape(metric.postCorner.dp)
            )
            .border(
                1.dp,
                colors.borderSubtle,
                RoundedCornerShape(metric.postCorner.dp)
            )
    ) {
        // 头部
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(spacing.md.dp),
            horizontalArrangement = Arrangement.spacedBy(spacing.md.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(metric.avatarSM.dp)
                    .clip(CircleShape)
                    .background(colors.brandPrimary)
            )

            Text(
                author,
                style = LocalTypography.current.bodyMD,
                color = colors.fgPrimary
            )

            Spacer(Modifier.weight(1f))

            Text("···", color = colors.fgSecondary)
        }

        Divider(color = colors.borderSubtle, thickness = 1.dp)

        // 图片
        if (imageUrl != null) {
            AsyncImage(
                model = imageUrl,
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(300.dp),
                contentScale = ContentScale.Crop
            )
        }

        // 互动栏
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(spacing.md.dp),
            horizontalArrangement = Arrangement.spacedBy(spacing.lg.dp)
        ) {
            IconButton(onClick = { isLiked = !isLiked }) {
                Icon(
                    imageVector = if (isLiked) Icons.Filled.Favorite else Icons.Default.FavoriteBorder,
                    contentDescription = "Like",
                    tint = if (isLiked) Red else colors.fgSecondary
                )
            }

            IconButton(onClick = {}) {
                Icon(
                    imageVector = Icons.Default.Chat,
                    contentDescription = "Comment",
                    tint = colors.fgSecondary
                )
            }
        }

        Divider(color = colors.borderSubtle, thickness = 1.dp)

        // 文本内容
        Text(
            content,
            style = LocalTypography.current.bodyMD,
            color = colors.fgPrimary,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(spacing.md.dp)
        )
    }
}

@Preview(name = "BrandA Light")
@Composable
private fun PostCardPreviewBrandALight() {
    NovaTheme(skin = BrandSkin.BRAND_A, isDark = false) {
        PostCard(
            author = "John Doe",
            content = "Amazing sunset today! 🌅",
            imageUrl = "https://..."
        )
    }
}
```

---

## Button 按钮

### iOS

```swift
struct NovaButton: View {
    @Environment(\.theme) var theme

    let title: String
    let action: () -> Void
    var style: ButtonStyle = .primary

    enum ButtonStyle {
        case primary
        case secondary
        case ghost
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.type.bodyMD)
                .frame(maxWidth: .infinity)
                .padding(theme.space.md)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(theme.radius.md)
        }
        .disabled(false)
        .frame(minHeight: theme.metric.minHitArea)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return theme.colors.brandPrimary
        case .secondary:
            return theme.colors.borderSubtle
        case .ghost:
            return .clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return theme.colors.brandOn
        case .secondary, .ghost:
            return theme.colors.fgPrimary
        }
    }
}
```

### Android

```kotlin
@Composable
fun NovaButton(
    text: String,
    onClick: () -> Unit,
    style: ButtonStyle = ButtonStyle.PRIMARY,
    modifier: Modifier = Modifier
) {
    val colors = LocalColorScheme.current
    val spacing = LocalSpacing.current
    val radius = LocalRadius.current

    Button(
        onClick = onClick,
        modifier = modifier
            .height(44.dp)
            .clip(RoundedCornerShape(radius.md.dp)),
        colors = ButtonDefaults.buttonColors(
            containerColor = when (style) {
                ButtonStyle.PRIMARY -> colors.brandPrimary
                ButtonStyle.SECONDARY -> colors.borderSubtle
                ButtonStyle.GHOST -> Color.Transparent
            }
        )
    ) {
        Text(
            text,
            style = LocalTypography.current.bodyMD,
            color = when (style) {
                ButtonStyle.PRIMARY -> colors.brandOn
                else -> colors.fgPrimary
            }
        )
    }
}

enum class ButtonStyle {
    PRIMARY, SECONDARY, GHOST
}
```

---

## TextField 输入框

### iOS

```swift
struct NovaTextField: View {
    @Environment(\.theme) var theme
    @State private var text = ""

    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.sm) {
            TextField(placeholder, text: $text)
                .font(theme.type.bodyMD)
                .padding(theme.space.md)
                .background(theme.colors.bgSurface)
                .cornerRadius(theme.radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.md)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                )
        }
        .frame(minHeight: theme.metric.minHitArea)
    }
}
```

### Android

```kotlin
@Composable
fun NovaTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier
) {
    val colors = LocalColorScheme.current
    val spacing = LocalSpacing.current
    val radius = LocalRadius.current

    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder) },
        modifier = modifier
            .fillMaxWidth()
            .height(44.dp),
        shape = RoundedCornerShape(radius.md.dp),
        colors = OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = colors.borderSubtle,
            focusedBorderColor = colors.brandPrimary,
            cursorColor = colors.brandPrimary
        )
    )
}
```

---

## Avatar 头像

### iOS

```swift
struct NovaAvatar: View {
    @Environment(\.theme) var theme

    let imageURL: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: imageURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            Circle()
                .fill(theme.colors.brandPrimary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(theme.colors.borderSubtle, lineWidth: 2)
        )
    }
}
```

### Android

```kotlin
@Composable
fun NovaAvatar(
    imageUrl: String?,
    size: Int = 40,
    modifier: Modifier = Modifier
) {
    val colors = LocalColorScheme.current

    Box(
        modifier = modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(colors.brandPrimary)
            .border(2.dp, colors.borderSubtle, CircleShape)
    ) {
        if (imageUrl != null) {
            AsyncImage(
                model = imageUrl,
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        }
    }
}
```

---

## Badge 徽章

### iOS

```swift
struct NovaBadge: View {
    @Environment(\.theme) var theme

    let text: String
    let type: BadgeType

    enum BadgeType {
        case success, warning, danger
    }

    var body: some View {
        Text(text)
            .font(theme.type.labelSM)
            .padding(.horizontal, theme.space.sm)
            .padding(.vertical, theme.space.xs)
            .background(backgroundColor)
            .foregroundColor(theme.colors.brandOn)
            .cornerRadius(theme.radius.sm)
    }

    private var backgroundColor: Color {
        switch type {
        case .success:
            return theme.colors.stateSuccess
        case .warning:
            return theme.colors.stateWarning
        case .danger:
            return theme.colors.stateDanger
        }
    }
}
```

### Android

```kotlin
@Composable
fun NovaBadge(
    text: String,
    type: BadgeType,
    modifier: Modifier = Modifier
) {
    val colors = LocalColorScheme.current
    val spacing = LocalSpacing.current
    val radius = LocalRadius.current

    Box(
        modifier = modifier
            .background(
                when (type) {
                    BadgeType.SUCCESS -> colors.stateSuccess
                    BadgeType.WARNING -> colors.stateWarning
                    BadgeType.DANGER -> colors.stateDanger
                },
                RoundedCornerShape(radius.sm.dp)
            )
            .padding(
                horizontal = spacing.sm.dp,
                vertical = spacing.xs.dp
            ),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text,
            style = LocalTypography.current.labelSM,
            color = Color.White
        )
    }
}

enum class BadgeType {
    SUCCESS, WARNING, DANGER
}
```

---

## 最佳实践总结

✅ **必须做**

- 始终从 @Environment/@CompositionLocal 获取 theme
- 使用语义化颜色（brandPrimary, not #0086C9）
- 遵守间距系统（space.md, not 12）
- 使用设计系统定义的圆角
- 在预览中测试所有 4 个主题

❌ **不要做**

- 硬编码颜色或尺寸
- 创建新的颜色常量
- 忽略深色主题
- 混合不同的间距值
- 使用不同的圆角规范

---

**最后更新**: 2025-10-18
**难度**: 初级到中级
**相关**: INTEGRATION_GUIDE.md | design.md
