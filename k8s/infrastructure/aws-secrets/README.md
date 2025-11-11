# AWS Secrets Manager IRSA Configuration

This directory contains Kubernetes manifests and AWS configuration for IRSA (IAM Roles for Service Accounts) to enable Nova services to access JWT secrets from AWS Secrets Manager.

## Overview

IRSA allows Kubernetes pods to assume AWS IAM roles without managing AWS credentials. This is achieved through:
1. EKS OIDC provider integration
2. IAM role with trust relationship to OIDC provider
3. Kubernetes ServiceAccount with IAM role annotation
4. Pods using the ServiceAccount inherit AWS credentials automatically

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes Pod (identity-service)                              │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Container: identity-service                              │  │
│  │  ServiceAccount: aws-secrets-manager                      │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │ AWS SDK (aws-secrets library)                       │  │  │
│  │  │ 1. Reads ServiceAccount token from filesystem       │  │  │
│  │  │ 2. Exchanges token for AWS credentials via STS      │  │  │
│  │  │ 3. Uses credentials to call Secrets Manager API     │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  EKS OIDC Provider                                              │
│  Verifies ServiceAccount token signature                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS IAM Role: nova-secrets-manager-role                        │
│  Trust Policy: Allows EKS OIDC provider to assume role          │
│  Attached Policy: NovaSecretsManagerPolicy                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  AWS Secrets Manager                                            │
│  Secret: prod/nova/jwt-config                                   │
│  {                                                              │
│    "signing_key": "base64-encoded-key",                         │
│    "algorithm": "HS256",                                        │
│    "issuer": "nova-platform",                                   │
│    "audience": ["api", "web"],                                  │
│    "expiry_seconds": 3600                                       │
│  }                                                              │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **EKS Cluster** with OIDC provider enabled
2. **AWS CLI** configured with admin permissions
3. **kubectl** configured to access the cluster
4. **eksctl** (optional, for easier OIDC provider setup)

## Setup Instructions

### Step 1: Enable OIDC Provider for EKS Cluster

Check if OIDC provider is already enabled:
```bash
aws eks describe-cluster --name <CLUSTER_NAME> --query "cluster.identity.oidc.issuer" --output text
```

If not enabled, use eksctl to enable:
```bash
eksctl utils associate-iam-oidc-provider --cluster <CLUSTER_NAME> --approve
```

Or manually via AWS Console:
1. Go to EKS → Your Cluster → Configuration → Details
2. Copy the "OpenID Connect provider URL"
3. Go to IAM → Identity providers → Add provider
4. Provider type: OpenID Connect
5. Provider URL: paste the OIDC URL
6. Audience: sts.amazonaws.com

### Step 2: Create JWT Secret in AWS Secrets Manager

```bash
# Create secret with JSON content
aws secretsmanager create-secret \
  --name prod/nova/jwt-config \
  --description "Nova JWT configuration for identity-service and graphql-gateway" \
  --secret-string '{
    "signing_key": "your-base64-encoded-hs256-key-here",
    "algorithm": "HS256",
    "issuer": "nova-platform",
    "audience": ["api", "web", "mobile"],
    "expiry_seconds": 3600
  }' \
  --region us-west-2
```

**For Production with RS256 (Asymmetric Keys)**:
```bash
# Generate RS256 key pair
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem

# Base64 encode keys (remove newlines)
SIGNING_KEY=$(cat private_key.pem | base64 -w 0)
VALIDATION_KEY=$(cat public_key.pem | base64 -w 0)

# Create secret
aws secretsmanager create-secret \
  --name prod/nova/jwt-config \
  --secret-string "{
    \"signing_key\": \"$SIGNING_KEY\",
    \"validation_key\": \"$VALIDATION_KEY\",
    \"algorithm\": \"RS256\",
    \"issuer\": \"nova-platform\",
    \"audience\": [\"api\", \"web\", \"mobile\"],
    \"expiry_seconds\": 3600
  }" \
  --region us-west-2

# Clean up private key from local filesystem
shred -u private_key.pem
```

### Step 3: Create IAM Policy

Replace `<ACCOUNT_ID>` and `<REGION>` with your values:

```bash
# Create policy file
cat > /tmp/secrets-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:<REGION>:<ACCOUNT_ID>:secret:prod/nova/jwt-config-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
      "Resource": [
        "arn:aws:kms:<REGION>:<ACCOUNT_ID>:key/*"
      ],
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.<REGION>.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create policy
aws iam create-policy \
  --policy-name NovaSecretsManagerPolicy \
  --policy-document file:///tmp/secrets-policy.json \
  --description "Policy for Nova services to access JWT secrets"
```

### Step 4: Create IAM Role with Trust Relationship

Get your OIDC provider ID:
```bash
aws eks describe-cluster --name <CLUSTER_NAME> --query "cluster.identity.oidc.issuer" --output text | sed 's/https:\/\///'
# Output example: oidc.eks.us-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE
```

Replace placeholders in trust policy:
```bash
# Create trust policy file
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>:sub": "system:serviceaccount:nova:aws-secrets-manager",
          "oidc.eks.<REGION>.amazonaws.com/id/<OIDC_ID>:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name nova-secrets-manager-role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "IRSA role for Nova services to access AWS Secrets Manager"
```

### Step 5: Attach Policy to Role

```bash
aws iam attach-role-policy \
  --role-name nova-secrets-manager-role \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/NovaSecretsManagerPolicy
```

### Step 6: Update ServiceAccount with IAM Role ARN

Edit `serviceaccount.yaml` and replace `<ACCOUNT_ID>`:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/nova-secrets-manager-role
```

Apply the manifest:
```bash
kubectl apply -f serviceaccount.yaml
```

### Step 7: Update Service Deployments

For each service that needs AWS Secrets Manager access (identity-service, graphql-gateway):

1. Add `serviceAccountName: aws-secrets-manager` to pod spec
2. Add environment variables:
   ```yaml
   - name: AWS_SECRETS_JWT_NAME
     value: "prod/nova/jwt-config"
   - name: AWS_REGION
     value: "us-west-2"
   ```
3. Remove hardcoded `JWT_SECRET` environment variable

Example deployments are provided in `deployment-example.yaml`.

Apply updated deployments:
```bash
kubectl apply -f deployment-example.yaml
```

## Verification

### Test IRSA Configuration

Deploy a test pod to verify IRSA is working:
```bash
kubectl run aws-cli-test \
  --rm -it \
  --image=amazon/aws-cli \
  --serviceaccount=aws-secrets-manager \
  --namespace=nova \
  -- secretsmanager get-secret-value \
     --secret-id prod/nova/jwt-config \
     --region us-west-2
```

Expected output:
```json
{
    "ARN": "arn:aws:secretsmanager:us-west-2:<ACCOUNT_ID>:secret:prod/nova/jwt-config-XXXXXX",
    "Name": "prod/nova/jwt-config",
    "VersionId": "...",
    "SecretString": "{\"signing_key\":\"...\",\"algorithm\":\"HS256\",...}",
    "VersionStages": ["AWSCURRENT"],
    "CreatedDate": "..."
}
```

### Check Service Logs

After deploying services with IRSA configuration:

**identity-service**:
```bash
kubectl logs -n nova -l app=identity-service --tail=50 | grep -i "jwt\|secrets"
```

Expected log:
```
{"level":"INFO","message":"Loading JWT config from AWS Secrets Manager: prod/nova/jwt-config"}
{"level":"INFO","message":"Secret fetched and cached from AWS Secrets Manager","secret_name":"prod/nova/jwt-config"}
```

**graphql-gateway**:
```bash
kubectl logs -n nova -l app=graphql-gateway --tail=50 | grep -i "jwt\|secrets"
```

### Troubleshooting

**AccessDeniedException**:
```
Error: An error occurred (AccessDeniedException) when calling the GetSecretValue operation: User: arn:aws:sts::<ACCOUNT_ID>:assumed-role/nova-secrets-manager-role/... is not authorized
```

**Causes**:
1. IAM policy doesn't include the secret ARN
2. Secret name doesn't match policy Resource pattern
3. KMS key permissions not granted

**Solution**:
```bash
# Check IAM role trust policy
aws iam get-role --role-name nova-secrets-manager-role

# Check attached policies
aws iam list-attached-role-policies --role-name nova-secrets-manager-role

# Verify policy permissions
aws iam get-policy-version \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/NovaSecretsManagerPolicy \
  --version-id v1
```

**ServiceAccount not found**:
```
Error: serviceaccounts "aws-secrets-manager" not found
```

**Solution**:
```bash
kubectl apply -f serviceaccount.yaml
kubectl get serviceaccount aws-secrets-manager -n nova -o yaml
```

**OIDC provider not configured**:
```
Error: An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation: No OpenIDConnect provider found
```

**Solution**:
```bash
eksctl utils associate-iam-oidc-provider --cluster <CLUSTER_NAME> --approve
```

## Secret Rotation

AWS Secrets Manager supports automatic rotation. To enable:

1. **Create Lambda rotation function** (AWS provides templates):
   - AWS Console → Secrets Manager → Your secret → Rotation configuration
   - Choose "Create a new Lambda function" or use existing

2. **Configure rotation schedule**:
   ```bash
   aws secretsmanager rotate-secret \
     --secret-id prod/nova/jwt-config \
     --rotation-lambda-arn arn:aws:lambda:<REGION>:<ACCOUNT_ID>:function:SecretsManagerRotation \
     --rotation-rules AutomaticallyAfterDays=90
   ```

3. **Monitor rotation**:
   - CloudWatch Logs: `/aws/lambda/SecretsManagerRotation`
   - Service logs: Cache will auto-refresh after TTL (5 minutes)

**Important**: When rotating JWT signing keys:
- Use asymmetric keys (RS256) to allow gradual rollout
- Rotation function should create new key pair, update secret
- Old validation key remains valid for `expiry_seconds` duration
- Services automatically fetch new keys after cache TTL

## Security Best Practices

1. **Least Privilege**: IAM policy only grants `GetSecretValue` (not `PutSecretValue` or `DeleteSecret`)
2. **Resource-Based Restrictions**: Policy Resource field uses wildcard suffix (`-*`) for version IDs
3. **KMS Encryption**: Secrets are encrypted with AWS-managed KMS keys by default
4. **Audit Logging**: All secret access is logged to CloudTrail
5. **Cache TTL**: Default 5 minutes balances performance vs. rotation latency
6. **Network Policies**: Restrict egress to AWS API endpoints only (see `deployment-example.yaml`)

## Cost Optimization

- **Secrets Manager Pricing** (us-west-2, as of 2024):
  - $0.40 per secret per month
  - $0.05 per 10,000 API calls

- **Nova Usage Estimate** (with caching):
  - 1 secret: $0.40/month
  - Cache TTL: 5 minutes
  - API calls per service per day: (24 * 60 / 5) = 288 calls
  - 2 services × 288 calls × 30 days = 17,280 calls/month
  - Cost: $0.40 + (17,280 / 10,000 × $0.05) = **$0.49/month**

## Related Documentation

- [P0 Completion Status](../../../backend/P0_COMPLETION_STATUS.md) - AWS Secrets Manager integration status
- [aws-secrets Library](../../../backend/libs/aws-secrets/src/lib.rs) - Rust implementation
- [identity-service Config](../../../backend/identity-service/src/config.rs) - JWT config loading
- [graphql-gateway Config](../../../backend/graphql-gateway/src/config.rs) - JWT validation config
- [AWS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS Secrets Manager Rotation](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)

## Terraform Alternative

For infrastructure-as-code approach, see `iam-policy.yaml` for complete Terraform configuration.

```bash
# Initialize Terraform
cd terraform/
terraform init

# Plan changes
terraform plan -var="account_id=<ACCOUNT_ID>" -var="cluster_name=<CLUSTER_NAME>"

# Apply configuration
terraform apply -var="account_id=<ACCOUNT_ID>" -var="cluster_name=<CLUSTER_NAME>"

# Get IAM role ARN for ServiceAccount
terraform output irsa_role_arn
```
