# Xcode 项目设置指南

## 🎯 快速创建 Xcode 项目

### 方法 1: 从零创建（推荐）

#### 1. 创建新项目

```bash
# 在 Xcode 中：
# File → New → Project
# 或使用快捷键: Shift + Cmd + N
```

#### 2. 选择模板

```
iOS → App
```

#### 3. 配置项目

```
Product Name: NovaSocial
Team: [Your Team]
Organization Identifier: com.yourcompany
Interface: SwiftUI
Language: Swift
Storage: None (我们已有网络层)
Include Tests: ✅
```

#### 4. 保存位置

```
Save to: /Users/proerror/Documents/nova/ios/NovaSocial
Create Git repository: ✅ (如果还没有)
```

### 方法 2: 使用命令行（高级）

```bash
cd /Users/proerror/Documents/nova/ios

# 创建 Xcode 项目（需要安装 xcodeproj 工具）
# 或者直接在 Xcode 中创建
```

## 📁 添加源代码到项目

### 1. 删除默认文件

在 Xcode 中删除以下自动生成的文件：
- ❌ `ContentView.swift` (我们有自己的)
- ❌ `NovaSocialApp.swift` (我们有自己的)

### 2. 添加文件夹到项目

**重要**: 使用 "Add Files" 而不是直接拖拽

```
1. 右键点击项目根目录（蓝色图标）
2. 选择 "Add Files to NovaSocial..."
3. 导航到 /Users/proerror/Documents/nova/ios/NovaSocial
4. 选中以下文件夹：
   ✅ App/
   ✅ ViewModels/
   ✅ Views/
   ✅ Network/

5. 确保勾选：
   ✅ Copy items if needed (如果在项目外)
   ✅ Create groups (不是 Create folder references)
   ✅ Add to targets: NovaSocial

6. 点击 "Add"
```

### 3. 添加测试文件（可选）

```
1. 右键点击 NovaSocialTests 组
2. "Add Files to NovaSocial..."
3. 选择 Tests/ 文件夹
4. 确保勾选：
   ✅ Add to targets: NovaSocialTests
```

### 4. 验证文件添加

检查 Target Membership：
```
1. 选择任意 .swift 文件
2. 打开 File Inspector (Cmd + Opt + 1)
3. 确认 Target Membership:
   - App/ → NovaSocial ✅
   - ViewModels/ → NovaSocial ✅
   - Views/ → NovaSocial ✅
   - Network/ → NovaSocial ✅
   - Tests/ → NovaSocialTests ✅
```

## ⚙️ 项目配置

### 1. Info.plist 配置

添加必要的权限：

```xml
<!-- 相机权限 -->
<key>NSCameraUsageDescription</key>
<string>我们需要访问您的相机来拍摄照片</string>

<!-- 相册权限 -->
<key>NSPhotoLibraryUsageDescription</key>
<string>我们需要访问您的相册来选择照片</string>

<!-- 如果需要添加照片到相册 -->
<key>NSPhotoLibraryAddUsageDescription</key>
<string>我们需要保存照片到您的相册</string>

<!-- 网络配置（开发环境） -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <!-- 生产环境应该移除或限制 -->
</dict>
```

**如何编辑 Info.plist**:
```
1. 点击项目根目录（蓝色图标）
2. 选择 NovaSocial target
3. 点击 Info 标签
4. 右键 → Add Row
5. 添加上述 Key-Value
```

### 2. Build Settings

#### Minimum Deployment Target

```
iOS Deployment Target: 16.0
```

#### Swift Language Version

```
Swift Language Version: Swift 5
```

#### Other Swift Flags (可选，用于调试)

```
Debug:
-Xfrontend -warn-long-function-bodies=200
-Xfrontend -warn-long-expression-type-checking=200
```

### 3. Signing & Capabilities

#### Automatic Signing (推荐)

```
Team: [Select your team]
Automatically manage signing: ✅
```

#### Manual Signing (如果需要)

```
Provisioning Profile: [Select profile]
Signing Certificate: [Select certificate]
```

### 4. Capabilities (按需添加)

可能需要的 Capabilities：

```
- Push Notifications (如果要推送)
- Background Modes (如果要后台刷新)
  - Remote notifications
  - Background fetch
- App Groups (如果要 Widget)
```

添加方式：
```
1. 选择 NovaSocial target
2. 点击 "Signing & Capabilities" 标签
3. 点击 "+ Capability"
4. 搜索并添加需要的功能
```

## 🎨 Scheme 配置

### Debug Scheme (开发环境)

```
1. Product → Scheme → Edit Scheme
2. Run → Info
   Build Configuration: Debug
3. Run → Arguments
   Environment Variables:
   - API_BASE_URL: http://localhost:8080/api/v1
   - LOG_LEVEL: debug
```

### Release Scheme (生产环境)

```
1. Duplicate Scheme → 命名为 "NovaSocial-Release"
2. Run → Info
   Build Configuration: Release
3. Run → Arguments
   Environment Variables:
   - API_BASE_URL: https://api.yourapp.com/v1
   - LOG_LEVEL: error
```

## 📦 依赖管理

### Swift Package Manager (推荐)

如果要添加第三方库：

```
1. File → Add Packages...
2. 输入包 URL，例如：
   - Kingfisher: https://github.com/onevcat/Kingfisher.git
   - Alamofire: https://github.com/Alamofire/Alamofire.git
3. 选择版本规则
4. Add Package
```

### 常用推荐包

```swift
// 图片缓存
.package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.0.0")

// 网络（如果需要替换 URLSession）
.package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0")

// Keychain 封装
.package(url: "https://github.com/evgenyneu/keychain-swift.git", from: "20.0.0")
```

## 🔨 Build Phases

确保正确的编译顺序：

```
1. Dependencies (依赖)
2. Compile Sources (编译源代码)
   - 应该包含所有 .swift 文件
3. Link Binary With Libraries (链接库)
4. Copy Bundle Resources (复制资源)
   - 图片、字体等资源文件
```

检查方式：
```
1. 选择 NovaSocial target
2. 点击 "Build Phases" 标签
3. 展开 "Compile Sources"
4. 确认所有 .swift 文件都在列表中
```

## 🐛 常见问题解决

### 问题 1: "Cannot find type 'XXX' in scope"

**原因**: 文件没有添加到 Target

**解决**:
```
1. 选择报错的文件
2. File Inspector (Cmd + Opt + 1)
3. Target Membership: 勾选 ✅ NovaSocial
```

### 问题 2: "Multiple commands produce XXX"

**原因**: 文件被重复添加

**解决**:
```
1. Build Phases → Compile Sources
2. 找到重复的文件
3. 右键 → Delete (删除其中一个)
```

### 问题 3: "No such module 'XXX'"

**原因**: Swift Package 没有正确链接

**解决**:
```
1. File → Packages → Resolve Package Versions
2. 或者删除重新添加包
3. Clean Build Folder (Shift + Cmd + K)
```

### 问题 4: "App Transport Security"

**原因**: HTTP 请求被阻止（非 HTTPS）

**解决**:
```
开发环境：Info.plist 添加 NSAllowsArbitraryLoads
生产环境：使用 HTTPS 或配置 NSExceptionDomains
```

### 问题 5: 图片/资源找不到

**原因**: 资源没有添加到 Bundle

**解决**:
```
1. 选择资源文件
2. File Inspector
3. Target Membership: 勾选 ✅ NovaSocial
```

## 🚀 运行项目

### 第一次运行

```
1. 选择目标设备：
   - iOS Simulator (推荐: iPhone 15 Pro)
   - 或实体设备

2. 点击 Run (Cmd + R)

3. 等待编译完成

4. 检查控制台输出
```

### 快捷键

```
Cmd + R: 运行
Cmd + .: 停止
Cmd + B: 编译
Shift + Cmd + K: 清理
Cmd + U: 运行测试
```

### 调试技巧

```
1. 断点：
   - 点击行号左侧添加断点
   - Cmd + \ 快速添加断点

2. 控制台：
   - Cmd + Shift + Y 显示/隐藏
   - 查看 print() 和 Logger.log() 输出

3. View Hierarchy:
   - Debug → View Debugging → Capture View Hierarchy
   - 查看 SwiftUI 视图层级

4. Instruments:
   - Cmd + I 启动性能分析
   - 选择 Time Profiler 或 Allocations
```

## 📱 设备测试

### Simulator 测试

推荐设备：
```
- iPhone 15 Pro (最新)
- iPhone SE (小屏)
- iPad Pro (平板)
```

### 真机测试

```
1. 连接设备
2. 信任开发者证书
3. 选择设备作为 Run Destination
4. Cmd + R 运行
```

首次真机运行可能需要：
```
Settings → General → VPN & Device Management
→ Trust "Your Developer Account"
```

## 🎨 Assets Catalog

如果要添加 App Icon 和启动画面：

```
1. 创建 Assets.xcassets（如果没有）
2. 添加 AppIcon
   - 拖拽图片到各个尺寸槽位
3. 添加 Launch Screen
   - 创建 LaunchScreen.storyboard
   - 或使用纯色背景
```

## 📋 Project Navigator 推荐结构

```
NovaSocial/
├── 📱 App/
│   ├── NovaSocialApp.swift
│   └── ContentView.swift
├── 🧠 ViewModels/
│   ├── Auth/
│   ├── Feed/
│   ├── Post/
│   ├── User/
│   └── Common/
├── 🎨 Views/
│   ├── Auth/
│   ├── Feed/
│   ├── Post/
│   ├── User/
│   ├── Explore/
│   └── Common/
├── 🌐 Network/
│   ├── Core/
│   ├── Models/
│   ├── Repositories/
│   ├── Services/
│   └── Utils/
├── 🧪 Tests/
├── 📖 Examples/
├── 📄 README.md
├── 📄 QUICK_START.md
└── 📄 PROJECT_STRUCTURE.md
```

## ✅ 验证清单

运行前检查：

- [ ] 所有 .swift 文件都在 Project Navigator 中可见
- [ ] 所有文件都有正确的 Target Membership
- [ ] Info.plist 包含所有必要权限
- [ ] API_BASE_URL 配置正确
- [ ] Signing & Capabilities 配置完成
- [ ] Minimum Deployment Target = iOS 16.0
- [ ] 没有编译警告或错误

编译成功后：

- [ ] 应用启动显示登录界面
- [ ] 可以切换登录/注册页面
- [ ] 表单验证正常工作
- [ ] 错误提示正常显示
- [ ] 导航正常工作

## 🎓 学习资源

### 官方文档
- [SwiftUI Tutorials](https://developer.apple.com/tutorials/swiftui)
- [Xcode Documentation](https://developer.apple.com/documentation/xcode)
- [Swift Documentation](https://swift.org/documentation/)

### 推荐视频
- WWDC SwiftUI Sessions
- Paul Hudson's 100 Days of SwiftUI
- Sean Allen's SwiftUI Tutorials

### 社区资源
- [Swift Forums](https://forums.swift.org)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/swiftui)
- [Reddit r/swift](https://reddit.com/r/swift)

---

如果遇到问题，请参考：
- [README.md](README.md) - 项目说明
- [QUICK_START.md](QUICK_START.md) - 快速入门
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - 项目结构
