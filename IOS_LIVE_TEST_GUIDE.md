# iOS 应用测试 - 实时测试指南

**测试时间**: 2026-01-09 06:55 GMT+8
**测试环境**: iPhone 16 Pro 模拟器 (iOS 26.1)
**应用状态**: ✅ 已启动并运行
**日志捕获**: ✅ 已启用 (Session ID: 4e5ef1e6-dd84-4f72-9ea0-ae125bdbbddf)

---

## 🎯 当前状态

### ✅ 已完成
1. iOS 应用构建成功
2. 应用已安装到模拟器
3. 模拟器已启动 (iPhone 16 Pro)
4. 应用已启动并运行
5. 日志捕获已启用

### 📱 应用信息
- **Bundle ID**: com.app.icered.pro
- **构建路径**: `/Users/proerror/Library/Developer/Xcode/DerivedData/ICERED-eciycymohknvnvakfmscswlfhffv/Build/Products/Debug-iphonesimulator/ICERED.app`
- **模拟器 ID**: EEDC000F-29A0-4997-89E0-B6A20ECB0B2D

---

## 🧪 测试步骤

### 测试 1: Liked Tab 功能测试

#### 步骤 1: 登录应用
1. 在模拟器中打开 ICERED 应用
2. 使用测试账号登录
3. 导航到 Home feed

#### 步骤 2: 点赞一个帖子
1. 在 Home feed 中找到一个帖子
2. 点击心形图标进行点赞
3. 观察心形图标是否变为填充状态

#### 步骤 3: 检查 Profile Liked Tab
1. 点击底部导航栏的 Profile 图标
2. 切换到 "Liked" 标签
3. **验证**: 刚才点赞的帖子应该出现在列表顶部

#### 步骤 4: 测试刷新
1. 下拉刷新 Liked 列表
2. **验证**: 帖子仍然可见（没有消失）

#### 步骤 5: 取消点赞
1. 在 Liked 标签中找到刚才的帖子
2. 点击心形图标取消点赞
3. 刷新列表
4. **验证**: 帖子从列表中移除

---

### 测试 2: Saved Tab 功能测试

#### 步骤 1: 保存一个帖子
1. 返回 Home feed
2. 找到一个帖子
3. 点击书签图标进行保存
4. 观察书签图标是否变为填充状态

#### 步骤 2: 检查 Profile Saved Tab
1. 导航到 Profile
2. 切换到 "Saved" 标签
3. **验证**: 刚才保存的帖子应该出现在列表顶部

#### 步骤 3: 测试刷新
1. 下拉刷新 Saved 列表
2. **验证**: 帖子仍然可见（没有消失）

#### 步骤 4: 取消保存
1. 在 Saved 标签中找到刚才的帖子
2. 点击书签图标取消保存
3. 刷新列表
4. **验证**: 帖子从列表中移除

---

### 测试 3: 分页测试

#### Liked Tab 分页
1. 在 Profile → Liked 标签中
2. 向下滚动到列表底部
3. **验证**: 更多帖子自动加载
4. **验证**: 没有重复的帖子

#### Saved Tab 分页
1. 在 Profile → Saved 标签中
2. 向下滚动到列表底部
3. **验证**: 更多帖子自动加载
4. **验证**: 没有重复的帖子

---

### 测试 4: 跨功能一致性测试

#### 测试场景 A: Like → Profile → Home
1. 在 Home feed 点赞一个帖子
2. 检查 Profile → Liked 标签（应该显示）
3. 在 Liked 标签取消点赞
4. 返回 Home feed
5. **验证**: 心形图标未填充

#### 测试场景 B: Save → Profile → Detail
1. 在 Home feed 保存一个帖子
2. 检查 Profile → Saved 标签（应该显示）
3. 点击帖子进入 Post Detail 视图
4. 在 Detail 视图取消保存
5. 返回 Profile → Saved 标签
6. **验证**: 帖子已从列表移除

---

## 📊 测试检查清单

### Liked Tab
- [ ] 新点赞的帖子立即出现
- [ ] 刷新后帖子仍然可见
- [ ] 取消点赞后帖子移除
- [ ] 分页功能正常
- [ ] 无崩溃或错误

### Saved Tab
- [ ] 新保存的帖子立即出现
- [ ] 刷新后帖子仍然可见
- [ ] 取消保存后帖子移除
- [ ] 分页功能正常
- [ ] 无崩溃或错误

### 跨功能一致性
- [ ] Like/unlike 状态在所有视图一致
- [ ] Save/unsave 状态在所有视图一致
- [ ] 无竞态条件或状态不同步

---

## 🔍 调试信息

### 查看日志
应用日志正在实时捕获中。测试完成后，使用以下命令获取日志：

```bash
# 停止日志捕获并查看
stop_sim_log_cap({ logSessionId: "4e5ef1e6-dd84-4f72-9ea0-ae125bdbbddf" })
```

### 预期的日志输出
测试过程中应该看到以下日志：

```
[ProfileData] ❤️ Loading liked posts for userId: <uuid>
[ProfileData] ✅ Loaded X liked posts
[ProfileData] 🔖 Loading saved posts for userId: <uuid>
[ProfileData] ✅ Loaded X saved posts
```

### API 调用验证
应该调用以下端点：
- ✅ `GET /api/v2/social/users/{userId}/liked-posts`
- ✅ `GET /api/v2/social/saved-posts`

不应该调用：
- ❌ `GET /api/v1/posts/user/{userId}/liked`
- ❌ `GET /api/v1/posts/user/{userId}/saved`

---

## 🐛 已知问题

### 问题 1: 空状态显示
**症状**: 首次打开 Liked/Saved 标签时显示空白
**原因**: 数据尚未加载
**解决**: 等待 1-2 秒，数据应该自动加载

### 问题 2: 刷新延迟
**症状**: 下拉刷新后数据更新有延迟
**原因**: 网络请求需要时间
**解决**: 正常现象，等待加载完成

---

## 📝 测试结果记录

### 测试 1: Liked Tab
**状态**: ⏳ 待测试
**结果**:
**问题**:
**截图**:

### 测试 2: Saved Tab
**状态**: ⏳ 待测试
**结果**:
**问题**:
**截图**:

### 测试 3: 分页
**状态**: ⏳ 待测试
**结果**:
**问题**:

### 测试 4: 跨功能一致性
**状态**: ⏳ 待测试
**结果**:
**问题**:

---

## 🎉 测试完成后

1. 停止日志捕获并保存日志
2. 记录所有测试结果
3. 截图保存关键界面
4. 更新 `IOS_TEST_REPORT.md`
5. 如有问题，创建 GitHub Issues

---

**测试人员**: Claude Code
**开始时间**: 2026-01-09 06:55 GMT+8
**预计时长**: 15-20 分钟
**状态**: 🟢 准备就绪，可以开始测试
