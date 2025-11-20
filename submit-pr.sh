#!/bin/bash

# Nova 主仓库 PR 提交助手
# 直接在 proerror77/Nova 仓库中创建 PR

echo "🚀 Nova PR 提交助手 (主仓库模式)"
echo "======================================="
echo ""

# 确保在 Nova 目录
cd /Users/bruce/Documents/Nova || exit 1

# 检查 git remote
REMOTE=$(git remote -v | grep origin | head -1)
if [[ ! $REMOTE == *"proerror77/Nova"* ]]; then
    echo "❌ 错误: 当前目录不是 proerror77/Nova 仓库"
    exit 1
fi

echo "✅ 当前仓库: proerror77/Nova"
echo ""

# 步骤 1: 检查并保存当前工作
echo "📋 步骤 1/7: 检查当前工作状态"
if [[ -n $(git status -s) ]]; then
    echo "⚠️  检测到未提交的更改:"
    git status -s
    echo ""
    read -p "是否暂存这些更改? (y/n): " STASH_CHANGES
    if [ "$STASH_CHANGES" = "y" ]; then
        git stash save "临时保存 - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "✅ 已暂存更改"
        STASHED=true
    else
        STASHED=false
    fi
else
    echo "✅ 工作目录干净"
    STASHED=false
fi

echo ""

# 步骤 2: 同步 main 分支
echo "📥 步骤 2/7: 同步 main 分支到最新"
git checkout main
git pull origin main
echo "✅ main 分支已更新"

echo ""

# 步骤 3: 创建新的功能分支
echo "🌿 步骤 3/7: 创建新功能分支"
echo ""
echo "分支命名建议:"
echo "  - feature/功能名  (新功能)"
echo "  - fix/问题名      (bug 修复)"
echo "  - docs/文档名     (文档更新)"
echo "  - refactor/重构名 (代码重构)"
echo ""
read -p "请输入新分支名称: " BRANCH_NAME

if [ -z "$BRANCH_NAME" ]; then
    echo "❌ 分支名称不能为空!"
    exit 1
fi

# 检查分支是否已存在
if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
    echo "⚠️  分支 '$BRANCH_NAME' 已存在"
    read -p "是否切换到该分支继续工作? (y/n): " USE_EXISTING
    if [ "$USE_EXISTING" = "y" ]; then
        git checkout "$BRANCH_NAME"
    else
        exit 1
    fi
else
    git checkout -b "$BRANCH_NAME"
    echo "✅ 已创建并切换到分支: $BRANCH_NAME"
fi

# 恢复暂存的更改
if [ "$STASHED" = true ]; then
    echo ""
    read -p "是否恢复之前暂存的更改到这个分支? (y/n): " RESTORE_STASH
    if [ "$RESTORE_STASH" = "y" ]; then
        git stash pop
        echo "✅ 已恢复暂存的更改"
    fi
fi

echo ""

# 步骤 4: 进行开发工作
echo "💻 步骤 4/7: 进行你的开发工作"
echo ""
echo "现在可以:"
echo "  - 在 Xcode 中修改代码"
echo "  - 添加新文件"
echo "  - 修改现有文件"
echo "  - 测试你的更改"
echo ""
read -p "完成开发工作后按 Enter 继续..."

echo ""

# 步骤 5: 查看并提交更改
echo "📊 步骤 5/7: 提交更改"
echo ""
echo "当前修改的文件:"
git status -s

if [[ -z $(git status -s) ]]; then
    echo "⚠️  没有检测到任何更改"
    exit 0
fi

echo ""
read -p "是否添加所有修改的文件? (y/n): " ADD_ALL

if [ "$ADD_ALL" = "y" ]; then
    git add .
    echo "✅ 已添加所有文件"
else
    echo ""
    echo "请手动添加文件:"
    echo "  git add <文件路径>"
    echo ""
    read -p "添加完成后按 Enter 继续..."
fi

echo ""
echo "提交信息格式建议:"
echo "  feat(scope): 功能描述"
echo "  fix(scope): 修复描述"
echo "  docs(scope): 文档更新"
echo ""
echo "示例:"
echo "  feat(ios): Add new Alice chat page"
echo "  fix(ios): Fix navigation bar alignment"
echo ""
read -p "请输入提交信息: " COMMIT_MSG

if [ -z "$COMMIT_MSG" ]; then
    echo "❌ 提交信息不能为空!"
    exit 1
fi

git commit -m "$COMMIT_MSG"
echo "✅ 已提交更改"

echo ""

# 步骤 6: 推送到远程仓库
echo "📤 步骤 6/7: 推送分支到 proerror77/Nova"
echo ""
read -p "确认推送分支 '$BRANCH_NAME' 到 proerror77/Nova? (y/n): " CONFIRM_PUSH

if [ "$CONFIRM_PUSH" != "y" ]; then
    echo "❌ 取消推送"
    exit 1
fi

git push -u origin "$BRANCH_NAME"

if [ $? -eq 0 ]; then
    echo "✅ 已成功推送到 origin/$BRANCH_NAME"
else
    echo "❌ 推送失败!"
    exit 1
fi

echo ""

# 步骤 7: 创建 Pull Request
echo "📝 步骤 7/7: 创建 Pull Request"
echo ""
echo "PR 将从以下分支合并到 main:"
echo "  proerror77/Nova:$BRANCH_NAME → proerror77/Nova:main"
echo ""

# GitHub PR URL
PR_URL="https://github.com/proerror77/Nova/pull/new/$BRANCH_NAME"

echo "方法 1: 自动打开浏览器创建 PR"
read -p "是否在浏览器中打开 PR 创建页面? (y/n): " OPEN_BROWSER

if [ "$OPEN_BROWSER" = "y" ]; then
    open "$PR_URL"
    echo "✅ 已在浏览器中打开 PR 创建页面"
else
    echo ""
    echo "请手动访问以下链接创建 PR:"
    echo "$PR_URL"
fi

echo ""
echo "方法 2: 使用 GitHub CLI (如果已安装)"
if command -v gh &> /dev/null; then
    read -p "是否使用 gh CLI 创建 PR? (y/n): " USE_GH

    if [ "$USE_GH" = "y" ]; then
        echo ""
        read -p "PR 标题: " PR_TITLE

        if [ -z "$PR_TITLE" ]; then
            PR_TITLE="$COMMIT_MSG"
        fi

        echo ""
        echo "PR 描述 (可选,按 Enter 跳过或输入描述):"
        read PR_BODY

        if [ -z "$PR_BODY" ]; then
            gh pr create --base main --title "$PR_TITLE"
        else
            gh pr create --base main --title "$PR_TITLE" --body "$PR_BODY"
        fi

        if [ $? -eq 0 ]; then
            echo "✅ PR 已创建成功!"
        fi
    fi
else
    echo "ℹ️  GitHub CLI 未安装"
    echo "   安装命令: brew install gh"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 完成! PR 提交流程已完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 摘要:"
echo "  仓库: proerror77/Nova"
echo "  分支: $BRANCH_NAME"
echo "  提交: $COMMIT_MSG"
echo "  状态: ✅ 已推送,等待创建 PR"
echo ""
echo "下一步:"
echo "  1. 创建 PR (如果还没创建)"
echo "  2. 等待代码审查"
echo "  3. 根据反馈修改 (如需要)"
echo "  4. PR 批准后会自动合并到 main"
echo ""
