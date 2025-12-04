# Translation Matrix (翻译矩阵)

## Translation Coverage Overview

| 类别 | 字符串数量 | zh-Hans | zh-Hant | en | 完成度 |
|------|-----------|---------|---------|----|----|
| Common | 23 | ✅ | ✅ | ✅ | 100% |
| Authentication | 14 | ✅ | ✅ | ✅ | 100% |
| Feed | 6 | ✅ | ✅ | ✅ | 100% |
| Post | 13 | ✅ | ✅ | ✅ | 100% |
| Profile | 9 | ✅ | ✅ | ✅ | 100% |
| Notification | 6 | ✅ | ✅ | ✅ | 100% |
| Search | 5 | ✅ | ✅ | ✅ | 100% |
| Settings | 14 | ✅ | ✅ | ✅ | 100% |
| Error Messages | 5 | ✅ | ✅ | ✅ | 100% |
| Create Post | 6 | ✅ | ✅ | ✅ | 100% |
| Language Selection | 6 | ✅ | ✅ | ✅ | 100% |
| **Total** | **107** | **107** | **107** | **107** | **100%** |

## Detailed String Mapping

### Common (通用)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| app.name | Nova | Nova | Nova | 品牌名称 |
| common.cancel | 取消 | 取消 | Cancel | |
| common.confirm | 确认 | 確認 | Confirm | |
| common.delete | 删除 | 刪除 | Delete | |
| common.edit | 编辑 | 編輯 | Edit | |
| common.save | 保存 | 儲存 | Save | |
| common.send | 发送 | 傳送 | Send | |
| common.done | 完成 | 完成 | Done | |
| common.back | 返回 | 返回 | Back | |
| common.next | 下一步 | 下一步 | Next | |
| common.skip | 跳过 | 略過 | Skip | |
| common.retry | 重试 | 重試 | Retry | |
| common.close | 关闭 | 關閉 | Close | |
| common.ok | 好的 | 好的 | OK | |
| common.yes | 是 | 是 | Yes | |
| common.no | 否 | 否 | No | |
| common.loading | 加载中... | 載入中... | Loading... | |
| common.error | 错误 | 錯誤 | Error | |
| common.success | 成功 | 成功 | Success | |
| common.warning | 警告 | 警告 | Warning | |

### Authentication (认证)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| auth.login | 登录 | 登入 | Login | |
| auth.register | 注册 | 註冊 | Sign Up | |
| auth.logout | 退出登录 | 登出 | Logout | |
| auth.email | 邮箱 | 電子郵件 | Email | |
| auth.password | 密码 | 密碼 | Password | |
| auth.username | 用户名 | 使用者名稱 | Username | |
| auth.forgot_password | 忘记密码？ | 忘記密碼？ | Forgot Password? | |
| auth.create_account | 创建账号 | 建立帳號 | Create Account | |
| auth.already_have_account | 已有账号？ | 已有帳號？ | Already have an account? | |
| auth.dont_have_account | 还没有账号？ | 還沒有帳號？ | Don't have an account? | |
| auth.error.invalid_credentials | 用户名或密码错误 | 使用者名稱或密碼錯誤 | Invalid username or password | |
| auth.error.password_too_short | 密码长度至少为 8 位 | 密碼長度至少為 8 位 | Password must be at least 8 characters | |
| auth.error.email_invalid | 邮箱格式不正确 | 電子郵件格式不正確 | Invalid email format | |

### Feed (动态流)

| Key | zh-Hans | zh-Hant | en | Format |
|-----|---------|---------|----|----|
| feed.title | 动态 | 動態 | Feed | |
| feed.new_post | 新动态 | 新動態 | New Post | |
| feed.refresh | 刷新 | 重新整理 | Refresh | |
| feed.no_more_posts | 没有更多内容了 | 沒有更多內容了 | No more posts | |
| feed.loading_more | 加载更多... | 載入更多... | Loading more... | |
| feed.posts_count | %d 条动态 | %d 則動態 | %d posts | %d |

### Post (帖子)

| Key | zh-Hans | zh-Hant | en | Format |
|-----|---------|---------|----|----|
| post.like | 点赞 | 按讚 | Like | |
| post.unlike | 取消点赞 | 取消按讚 | Unlike | |
| post.comment | 评论 | 留言 | Comment | |
| post.share | 分享 | 分享 | Share | |
| post.delete | 删除 | 刪除 | Delete | |
| post.edit | 编辑 | 編輯 | Edit | |
| post.report | 举报 | 檢舉 | Report | |
| post.save | 收藏 | 收藏 | Save | |
| post.unsave | 取消收藏 | 取消收藏 | Unsave | |
| post.likes_count | %d 个赞 | %d 個讚 | %d likes | %d |
| post.comments_count | %d 条评论 | %d 則留言 | %d comments | %d |
| post.shares_count | %d 次分享 | %d 次分享 | %d shares | %d |
| post.time_ago.minutes | %d 分钟前 | %d 分鐘前 | %d minutes ago | %d |
| post.time_ago.hours | %d 小时前 | %d 小時前 | %d hours ago | %d |
| post.time_ago.days | %d 天前 | %d 天前 | %d days ago | %d |

### Profile (个人资料)

| Key | zh-Hans | zh-Hant | en | Format |
|-----|---------|---------|----|----|
| profile.followers | 粉丝 | 粉絲 | Followers | |
| profile.following | 关注 | 追蹤中 | Following | |
| profile.posts | 帖子 | 貼文 | Posts | |
| profile.follow | 关注 | 追蹤 | Follow | |
| profile.unfollow | 取消关注 | 取消追蹤 | Unfollow | |
| profile.edit_profile | 编辑资料 | 編輯資料 | Edit Profile | |
| profile.settings | 设置 | 設定 | Settings | |
| profile.bio | 个人简介 | 個人簡介 | Bio | |
| profile.followers_count | %d 位粉丝 | %d 位粉絲 | %d followers | %d |
| profile.following_count | 关注 %d 人 | 追蹤 %d 人 | %d following | %d |
| profile.posts_count | %d 条帖子 | %d 則貼文 | %d posts | %d |

### Notification (通知)

| Key | zh-Hans | zh-Hant | en | Format |
|-----|---------|---------|----|----|
| notification.title | 通知 | 通知 | Notifications | |
| notification.mark_all_read | 全部标为已读 | 全部標示為已讀 | Mark All as Read | |
| notification.no_notifications | 暂无通知 | 暫無通知 | No notifications | |
| notification.liked_your_post | %@ 赞了你的帖子 | %@ 對你的貼文按讚 | %@ liked your post | %@ |
| notification.commented_on_your_post | %@ 评论了你的帖子 | %@ 留言了你的貼文 | %@ commented on your post | %@ |
| notification.followed_you | %@ 关注了你 | %@ 追蹤了你 | %@ followed you | %@ |

### Search (搜索)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| search.title | 搜索 | 搜尋 | Search | |
| search.placeholder | 搜索用户、标签... | 搜尋使用者、標籤... | Search users, tags... | |
| search.no_results | 未找到相关结果 | 未找到相關結果 | No results found | |
| search.recent | 最近搜索 | 最近搜尋 | Recent | |
| search.trending | 热门 | 熱門 | Trending | |

### Settings (设置)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| settings.title | 设置 | 設定 | Settings | |
| settings.account | 账号设置 | 帳號設定 | Account | |
| settings.privacy | 隐私设置 | 隱私設定 | Privacy | |
| settings.notifications | 通知设置 | 通知設定 | Notifications | |
| settings.language | 语言 | 語言 | Language | |
| settings.theme | 主题 | 主題 | Theme | |
| settings.about | 关于 | 關於 | About | |
| settings.version | 版本 | 版本 | Version | |
| settings.logout | 退出登录 | 登出 | Logout | |
| settings.terms_of_service | 服务条款 | 服務條款 | Terms of Service | |
| settings.privacy_policy | 隐私政策 | 隱私權政策 | Privacy Policy | |
| settings.help | 帮助与支持 | 說明與支援 | Help & Support | |
| settings.logout_confirm | 确定要退出登录吗？ | 確定要登出嗎？ | Are you sure you want to logout? | |

### Error Messages (错误消息)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| error.network_error | 网络连接失败，请检查网络设置 | 網路連線失敗，請檢查網路設定 | Network connection failed. Please check your network settings. | |
| error.unknown_error | 未知错误，请稍后重试 | 未知錯誤，請稍後重試 | Unknown error occurred. Please try again later. | |
| error.server_error | 服务器错误，请稍后重试 | 伺服器錯誤，請稍後重試 | Server error. Please try again later. | |
| error.invalid_input | 输入内容无效 | 輸入內容無效 | Invalid input | |
| error.unauthorized | 未授权，请重新登录 | 未授權，請重新登入 | Unauthorized. Please login again. | |

### Create Post (创建帖子)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| create_post.title | 发布动态 | 發佈動態 | Create Post | |
| create_post.caption | 说点什么... | 說點什麼... | Write a caption... | |
| create_post.caption_placeholder | 分享你的想法... | 分享你的想法... | Share your thoughts... | |
| create_post.select_media | 选择图片或视频 | 選擇圖片或影片 | Select Photo or Video | |
| create_post.publish | 发布 | 發佈 | Publish | |
| create_post.uploading | 上传中... | 上傳中... | Uploading... | |

### Language Selection (语言选择)

| Key | zh-Hans | zh-Hant | en | Notes |
|-----|---------|---------|----|----|
| language_selection.title | 选择语言 | 選擇語言 | Language | |
| language_selection.current_language | 当前语言 | 目前語言 | Current Language | |
| language_selection.system_language | 跟随系统 | 跟隨系統 | System Default | |
| language_selection.footer | 更改语言将更新应用界面。某些更改可能需要重启应用才能完全生效。 | 更改語言將更新應用程式介面。某些變更可能需要重新啟動應用程式才能完全生效。 | Changing the language will update the app interface. Some changes may require restarting the app to fully apply. | |
| language_selection.changed_title | 语言已更改 | 語言已變更 | Language Changed | |
| language_selection.changed_message | 应用语言已更改。某些功能可能需要重启应用才能完全生效。 | 應用程式語言已變更。某些功能可能需要重新啟動應用程式才能完全生效。 | The app language has been changed. Some features may require restarting the app to fully apply. | |

## Translation Quality Checklist

### Terminology Consistency

| English | zh-Hans | zh-Hant | Notes |
|---------|---------|---------|-------|
| Post | 动态/帖子 | 動態/貼文 | 根据上下文 |
| Feed | 动态流 | 動態 | |
| Like | 点赞 | 按讚 | |
| Comment | 评论 | 留言 | |
| Follow | 关注 | 追蹤 | |
| Follower | 粉丝 | 粉絲 | |
| Settings | 设置 | 設定 | |
| Privacy | 隐私 | 隱私 | |
| Notification | 通知 | 通知 | |

### Formatting Guidelines

1. **数字格式**
   - zh-Hans: `1,234,567`
   - zh-Hant: `1,234,567`
   - en: `1,234,567`

2. **日期格式**
   - zh-Hans: `2024年1月15日`
   - zh-Hant: `2024年1月15日`
   - en: `January 15, 2024`

3. **时间格式**
   - zh-Hans: `下午3:30`
   - zh-Hant: `下午3:30`
   - en: `3:30 PM`

4. **百分比**
   - All: `75%`

5. **货币**
   - zh-Hans: `¥100.00` (CNY) or `US$100.00` (USD)
   - zh-Hant: `NT$100` (TWD) or `US$100.00` (USD)
   - en: `$100.00` (USD)

### Tone & Style

| Language | Tone | Formality | Examples |
|----------|------|-----------|----------|
| zh-Hans | 友好、简洁 | 中等 | "点击确认" vs "请点击确认按钮" |
| zh-Hant | 专业、礼貌 | 稍高 | "按一下確認" |
| en | Casual, Direct | Low | "Tap Confirm" vs "Please tap the confirm button" |

## Missing Translations Report

### Current Status: ✅ All strings translated

No missing translations detected as of 2024-10-19.

## Future Additions Needed

### Planned Features

1. **Reels/Video System** (Spec 008)
   - Video player controls
   - Video upload UI
   - Video editing features

2. **Direct Messages**
   - Chat interface
   - Message notifications
   - Typing indicators

3. **Stories**
   - Story creation
   - Story viewer
   - Story interactions

4. **E-commerce**
   - Product listings
   - Shopping cart
   - Checkout flow

### Estimated Strings to Add

| Feature | Estimated Strings | Priority |
|---------|------------------|----------|
| Reels/Video | 30-40 | High |
| Direct Messages | 25-35 | High |
| Stories | 15-20 | Medium |
| E-commerce | 50-70 | Low |

## Translation Workflow

### For Developers

1. Add new feature strings to `L10n.swift`
2. Add English strings to `en.lproj/Localizable.strings`
3. Mark for translation in tracking sheet
4. Request translations for zh-Hans and zh-Hant
5. Review and merge translations
6. Update this matrix

### For Translators

1. Receive new string list
2. Translate to zh-Hans and zh-Hant
3. Maintain consistency with existing terminology
4. Submit translations via PR
5. Respond to review feedback

## Tools & Resources

### Recommended Translation Tools

- **Google Translate**: 初步翻译
- **DeepL**: 高质量机器翻译
- **ChatGPT**: 上下文优化
- **Xcode**: XLIFF 导出/导入

### Style Guides

- [Apple Human Interface Guidelines (中文)](https://developer.apple.com/cn/design/human-interface-guidelines/)
- [iOS Terminology Glossary](https://developer.apple.com/library/archive/documentation/Miscellaneous/Conceptual/iPhoneOSTechOverview/Introduction/Introduction.html)

---

**最后更新**: 2024-10-19
**翻译状态**: 100% 完成
**维护者**: Nova iOS Team
