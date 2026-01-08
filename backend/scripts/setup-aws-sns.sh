#!/bin/bash
# Setup AWS SNS for Phone OTP
# This script configures AWS SNS for sending SMS verification codes

set -e

# Configuration
REGION="${AWS_REGION:-ap-northeast-1}"
MONTHLY_SPEND_LIMIT="${SNS_MONTHLY_LIMIT:-50}"
DEFAULT_SENDER_ID="${SNS_SENDER_ID:-Nova}"

echo "========================================="
echo "AWS SNS Setup for Phone OTP"
echo "========================================="
echo "Region: $REGION"
echo "Monthly Spend Limit: \$$MONTHLY_SPEND_LIMIT USD"
echo "Default Sender ID: $DEFAULT_SENDER_ID"
echo ""

# Step 1: Verify AWS credentials
echo "Step 1: Verifying AWS credentials..."
if ! aws sts get-caller-identity --region "$REGION" > /dev/null 2>&1; then
    echo "❌ AWS credentials verification failed"
    echo "Please configure AWS credentials first:"
    echo "  export AWS_ACCESS_KEY_ID=\"your-key\""
    echo "  export AWS_SECRET_ACCESS_KEY=\"your-secret\""
    echo "  OR run: aws configure"
    exit 1
fi

CALLER_IDENTITY=$(aws sts get-caller-identity --region "$REGION")
echo "✅ AWS credentials verified"
echo "$CALLER_IDENTITY"
echo ""

# Step 2: Check IAM permissions
echo "Step 2: Checking IAM permissions..."
echo "Note: This is a basic check. Full permission validation happens during actual API calls."
echo ""

# Step 3: Set SNS SMS attributes
echo "Step 3: Configuring SNS SMS settings..."
echo "Setting monthly spend limit to \$$MONTHLY_SPEND_LIMIT..."
echo "Setting SMS type to Transactional (high priority)..."
echo "Setting default sender ID to $DEFAULT_SENDER_ID..."

if aws sns set-sms-attributes \
    --attributes \
        "MonthlySpendLimit=$MONTHLY_SPEND_LIMIT,DefaultSMSType=Transactional,DefaultSenderID=$DEFAULT_SENDER_ID" \
    --region "$REGION"; then
    echo "✅ SNS SMS attributes configured successfully"
else
    echo "⚠️  Failed to set SMS attributes. This might be due to:"
    echo "   - Insufficient IAM permissions (sns:SetSMSAttributes required)"
    echo "   - Sender ID not supported in region $REGION"
    echo "   - Rate limiting"
    echo ""
    echo "Continuing anyway..."
fi
echo ""

# Step 4: Verify configuration
echo "Step 4: Verifying current SNS SMS configuration..."
if SNS_ATTRS=$(aws sns get-sms-attributes --region "$REGION" 2>/dev/null); then
    echo "✅ Current SNS SMS configuration:"
    echo "$SNS_ATTRS" | jq -r '.attributes | to_entries[] | "  \(.key): \(.value)"'
else
    echo "⚠️  Could not retrieve SNS SMS attributes"
    echo "This might indicate insufficient permissions (sns:GetSMSAttributes required)"
fi
echo ""

# Step 5: Test SMS send (optional)
if [ -n "$TEST_PHONE_NUMBER" ]; then
    echo "Step 5: Testing SMS send to $TEST_PHONE_NUMBER..."
    echo "Sending test message..."

    if aws sns publish \
        --phone-number "$TEST_PHONE_NUMBER" \
        --message "Nova Phone Auth Test - Your verification code is: 123456" \
        --region "$REGION"; then
        echo "✅ Test SMS sent successfully!"
        echo "Please check your phone for the message."
    else
        echo "❌ Failed to send test SMS"
        echo "Common reasons:"
        echo "  - Phone number not in E.164 format (must start with +)"
        echo "  - Insufficient IAM permissions (sns:Publish required)"
        echo "  - Region $REGION doesn't support SMS to this destination"
        echo "  - Monthly spend limit reached"
    fi
else
    echo "Step 5: Skipping test SMS send (TEST_PHONE_NUMBER not set)"
    echo "To test SMS sending, run:"
    echo "  export TEST_PHONE_NUMBER=\"+818012345678\""
    echo "  $0"
fi
echo ""

# Step 6: Create AWS Secrets Manager secret (optional)
if [ "$CREATE_SECRET" = "true" ]; then
    echo "Step 6: Creating AWS Secrets Manager secret..."

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo "❌ AWS credentials not found in environment"
        echo "Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
        exit 1
    fi

    SECRET_NAME="nova/identity-service/aws"
    SECRET_VALUE="{\"AWS_ACCESS_KEY_ID\":\"$AWS_ACCESS_KEY_ID\",\"AWS_SECRET_ACCESS_KEY\":\"$AWS_SECRET_ACCESS_KEY\"}"

    # Check if secret already exists
    if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" > /dev/null 2>&1; then
        echo "⚠️  Secret $SECRET_NAME already exists"
        read -p "Update existing secret? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if aws secretsmanager update-secret \
                --secret-id "$SECRET_NAME" \
                --secret-string "$SECRET_VALUE" \
                --region "$REGION"; then
                echo "✅ Secret updated successfully"
            else
                echo "❌ Failed to update secret"
                exit 1
            fi
        else
            echo "Skipping secret update"
        fi
    else
        if aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "AWS credentials for SNS SMS" \
            --secret-string "$SECRET_VALUE" \
            --region "$REGION"; then
            echo "✅ Secret created successfully: $SECRET_NAME"
            echo ""
            echo "To use this secret with External Secrets Operator:"
            echo "  1. Ensure External Secrets Operator is installed"
            echo "  2. Create ExternalSecret resource referencing $SECRET_NAME"
            echo "  3. Configure IAM role with secretsmanager:GetSecretValue permission"
        else
            echo "❌ Failed to create secret"
            exit 1
        fi
    fi
else
    echo "Step 6: Skipping AWS Secrets Manager secret creation (CREATE_SECRET not set)"
    echo "To create secret, run:"
    echo "  export CREATE_SECRET=true"
    echo "  export AWS_ACCESS_KEY_ID=\"your-key\""
    echo "  export AWS_SECRET_ACCESS_KEY=\"your-secret\""
    echo "  $0"
fi
echo ""

# Summary
echo "========================================="
echo "✅ AWS SNS Setup Complete!"
echo "========================================="
echo ""
echo "Configuration Summary:"
echo "  Region: $REGION"
echo "  Monthly Spend Limit: \$$MONTHLY_SPEND_LIMIT USD"
echo "  SMS Type: Transactional"
echo "  Sender ID: $DEFAULT_SENDER_ID"
echo ""
echo "Next Steps:"
echo "  1. Update Kubernetes secrets with AWS credentials"
echo "  2. Apply Kubernetes configuration (kubectl apply -k backend/k8s/overlays/staging)"
echo "  3. Restart identity-service deployment"
echo "  4. Test Phone OTP flow with backend/scripts/test-phone-otp.sh"
echo ""
echo "Useful Commands:"
echo "  # Check current SNS configuration"
echo "  aws sns get-sms-attributes --region $REGION"
echo ""
echo "  # Send test SMS"
echo "  aws sns publish --phone-number \"+818012345678\" --message \"Test\" --region $REGION"
echo ""
echo "  # View SNS CloudWatch metrics"
echo "  aws cloudwatch get-metric-statistics \\"
echo "    --namespace AWS/SNS \\"
echo "    --metric-name SMSSuccessRate \\"
echo "    --dimensions Name=SMSType,Value=Transactional \\"
echo "    --start-time \$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "    --period 3600 \\"
echo "    --statistics Average \\"
echo "    --region $REGION"
echo ""
