#!/bin/bash

# AWS CodeBuild 快速部署脚本
# 使用 CloudFormation 一键创建 Nova CodeBuild 构建流程

set -e

AWS_REGION="ap-northeast-1"
AWS_ACCOUNT_ID="025434362120"
STACK_NAME="nova-codebuild-stack"
TEMPLATE_FILE="aws/codebuild-template.yaml"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Nova CodeBuild 快速部署"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 检查 AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI 未安装"
    echo "安装: https://aws.amazon.com/cli/"
    exit 1
fi

echo "✅ AWS CLI 已安装"
echo ""

# 检查凭证
echo "🔐 检查 AWS 凭证..."
if ! aws sts get-caller-identity --region $AWS_REGION &> /dev/null; then
    echo "❌ AWS 凭证无效或未配置"
    exit 1
fi

IDENTITY=$(aws sts get-caller-identity --region $AWS_REGION)
echo "✅ AWS 账户: $AWS_ACCOUNT_ID"
echo ""

# 验证模板
echo "📋 验证 CloudFormation 模板..."
if ! aws cloudformation validate-template \
    --template-body file://$TEMPLATE_FILE \
    --region $AWS_REGION > /dev/null; then
    echo "❌ 模板验证失败"
    exit 1
fi
echo "✅ 模板验证成功"
echo ""

# 创建或更新堆栈
echo "🔧 部署 CloudFormation 堆栈..."
echo "堆栈名称: $STACK_NAME"
echo "区域: $AWS_REGION"
echo ""

if aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $AWS_REGION &> /dev/null; then
    echo "📦 更新现有堆栈..."
    aws cloudformation update-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION

    echo "⏳ 等待堆栈更新..."
    aws cloudformation wait stack-update-complete \
        --stack-name $STACK_NAME \
        --region $AWS_REGION
else
    echo "📦 创建新堆栈..."
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-body file://$TEMPLATE_FILE \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $AWS_REGION

    echo "⏳ 等待堆栈创建..."
    aws cloudformation wait stack-create-complete \
        --stack-name $STACK_NAME \
        --region $AWS_REGION
fi

echo "✅ 堆栈部署成功"
echo ""

# 获取输出
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 部署结果"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $AWS_REGION \
    --query 'Stacks[0].Outputs')

echo "$OUTPUTS" | jq .

echo ""
echo "✨ CodeBuild 项目已准备就绪！"
echo ""

# 显示后续步骤
PROJECT_NAME=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="CodeBuildProjectName") | .OutputValue')
LOG_GROUP=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="CloudWatchLogsGroupName") | .OutputValue')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 后续步骤"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1️⃣ 启动构建（命令行）："
echo "   aws codebuild start-build --project-name $PROJECT_NAME --region $AWS_REGION"
echo ""
echo "2️⃣ 查看构建日志："
echo "   aws logs tail $LOG_GROUP --follow --region $AWS_REGION"
echo ""
echo "3️⃣ 查看构建历史："
echo "   aws codebuild batch-get-builds --ids <BUILD_ID> --region $AWS_REGION"
echo ""
echo "4️⃣ 在 AWS 控制台查看："
echo "   https://console.aws.amazon.com/codesuite/codebuild/projects/$PROJECT_NAME/history"
echo ""
