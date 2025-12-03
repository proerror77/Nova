# 图标资源映射表

本文档记录了项目中所有图标资源及其使用规范。

## 📦 新添加的图标（共 41 个）

### 🧭 导航按钮图标

| 图标名称 | 用途 | 尺寸 |
|---------|------|------|
| `Home-button-on` | 首页按钮（激活状态） | 36x36 |
| `Home-button-off` | 首页按钮（未激活） | 36x36 |
| `Message-button-on` | 消息按钮（激活状态） | 36x36 |
| `Message-button-off` | 消息按钮（未激活） | 36x36 |
| `alice-button-on` | Alice按钮（激活状态） | 36x36 |
| `alice-button-off` | Alice按钮（未激活） | 36x36 |
| `Account-button-on` | 账户按钮（激活状态） | 36x36 |
| `Account-button-off` | 账户按钮（未激活） | 36x36 |
| `Newpost` | 新建帖子按钮 | 44x32 |

### 🔍 搜索图标

| 图标名称 | 用途 | 颜色 |
|---------|------|------|
| `search(black)` | 黑色搜索图标 | 黑色 |
| `search(white)` | 白色搜索图标 | 白色 |
| `search(gray)` | 灰色搜索图标 | 灰色 |

### ⬅️ 导航控制

| 图标名称 | 用途 |
|---------|------|
| `back-black` | 黑色返回按钮 |
| `back-white` | 白色返回按钮 |

### 🎯 功能图标

| 图标名称 | 用途 |
|---------|------|
| `bell` | 通知/铃铛 |
| `chat` | 聊天 |
| `heart` | 收藏/喜欢（空心） |
| `share` | 分享 |
| `Share-black` | 黑色分享图标 |
| `collect` | 收藏 |
| `collect2` | 收藏（变体2） |
| `information` | 信息/详情 |
| `Send-Icon` | 发送图标 |

### 🛠️ UI控制图标

| 图标名称 | 用途 |
|---------|------|
| `Add` | 添加 |
| `More` | 更多选项 |
| `Setting(white)` | 白色设置图标 |
| `RedClose` | 红色关闭按钮 |
| `Close-W` | 白色关闭 |
| `Close-B` | 黑色关闭 |
| `Dropdown` | 下拉菜单 |
| `Blue-v` | 蓝色对勾 |
| `Trash` | 删除/垃圾桶 |

### 📱 社交功能

| 图标名称 | 用途 |
|---------|------|
| `AddFriends` | 添加好友 |
| `GroupChat` | 群聊 |
| `Scan` | 扫描二维码 |

### 📸 媒体相关

| 图标名称 | 用途 |
|---------|------|
| `Takephoto` | 拍照 |
| `Album` | 相册 |
| `Voice` | 语音 |
| `Loction` | 位置 |

### 🏷️ 品牌与其他

| 图标名称 | 用途 |
|---------|------|
| `Icered-AI` | Icered AI Logo |
| `翻页` | 翻页指示器 |

---

## 🔄 图标替换映射

### 旧图标 → 新图标

| 旧图标名 | 新图标名 | 说明 |
|---------|---------|------|
| `home-icon` | `Home-button-on` 或 `Home-button-off` | 根据激活状态选择 |
| `alice-icon` | `alice-button-on` 或 `alice-button-off` | 根据激活状态选择 |
| `Account-icon` | `Account-button-on` 或 `Account-button-off` | 根据激活状态选择 |
| `Message-icon-black` | `Message-button-off` | 未激活状态 |
| `Message-icon-red` | `Message-button-on` | 激活状态 |
| `Newpost-icon` | `Newpost` | 保持使用新图标 |
| `Back-icon` | `back-black` 或 `back-white` | 根据背景颜色选择 |

---

## 📝 使用规范

### 底部导航栏规范

**当前页面（激活状态）**：
```swift
Image("Home-button-on")      // 高亮显示
    .resizable()
    .scaledToFit()
    .frame(width: 36, height: 36)
```

**其他页面（未激活状态）**：
```swift
Image("Home-button-off")     // 灰色/黑色显示
    .resizable()
    .scaledToFit()
    .frame(width: 36, height: 36)
```

### 命名规范

- **激活状态**：使用 `-on` 后缀
- **未激活状态**：使用 `-off` 后缀
- **颜色变体**：使用 `-black`、`-white`、`-gray` 等后缀
- **多分辨率**：自动支持 @1x, @2x, @3x

---

## ✅ 已更新的文件

- ✅ `Features/Alice/Views/AliceView.swift` - 使用新图标
- 📋 其他文件待后续更新

---

*更新时间: 2025年11月20日*
