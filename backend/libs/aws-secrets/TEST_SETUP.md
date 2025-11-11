# AWS Secrets Manager Integration Test Setup

This guide explains how to set up and run integration tests for the aws-secrets library with real AWS Secrets Manager.

## Prerequisites

1. **AWS Account** with Secrets Manager access
2. **AWS CLI** configured with credentials
3. **IAM Permissions**:
   - `secretsmanager:CreateSecret`
   - `secretsmanager:GetSecretValue`
   - `secretsmanager:DeleteSecret`
   - `secretsmanager:DescribeSecret`

## Quick Setup

### 1. Configure AWS Credentials

**Option A: AWS CLI Configuration**
```bash
aws configure
# AWS Access Key ID: [your-key-id]
# AWS Secret Access Key: [your-secret-key]
# Default region name: us-west-2
# Default output format: json
```

**Option B: Environment Variables**
```bash
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-west-2"
```

**Option C: IRSA (In Kubernetes)**
```bash
# Tests will automatically use IRSA credentials if running in EKS pod
# with ServiceAccount annotation: eks.amazonaws.com/role-arn
```

### 2. Create Test Secret

```bash
# Create JWT config secret for testing
aws secretsmanager create-secret \
  --name test/nova/jwt-config \
  --description "Test JWT configuration for integration tests" \
  --secret-string '{
    "signing_key": "dGVzdC1zaWduaW5nLWtleS1mb3ItaW50ZWdyYXRpb24tdGVzdHM=",
    "algorithm": "HS256",
    "issuer": "nova-test",
    "audience": ["api", "test"],
    "expiry_seconds": 3600
  }' \
  --region us-west-2
```

**Expected Output**:
```json
{
    "ARN": "arn:aws:secretsmanager:us-west-2:123456789012:secret:test/nova/jwt-config-AbCdEf",
    "Name": "test/nova/jwt-config",
    "VersionId": "..."
}
```

### 3. Set Environment Variable

```bash
export AWS_SECRETS_TEST_SECRET_NAME="test/nova/jwt-config"
```

### 4. Run Tests

**Run all integration tests**:
```bash
cargo test --package aws-secrets --test integration_test -- --nocapture
```

**Run specific test**:
```bash
cargo test --package aws-secrets --test integration_test test_secret_fetch_and_cache -- --nocapture
```

**Run with verbose output**:
```bash
RUST_LOG=aws_secrets=debug cargo test --package aws-secrets --test integration_test -- --nocapture
```

## Test Coverage

The integration test suite covers:

### 1. Basic Operations
- ✅ SecretManager initialization
- ✅ Secret fetching from AWS
- ✅ Caching behavior
- ✅ JWT config parsing

### 2. Cache Management
- ✅ Cache invalidation
- ✅ Cache TTL expiration
- ✅ Multiple secrets in cache
- ✅ Custom cache TTL configuration

### 3. Rotation Simulation
- ✅ Cache invalidation on rotation
- ✅ Automatic refresh after TTL
- ✅ Concurrent access during rotation

### 4. Error Handling
- ✅ Non-existent secret error (NotFound)
- ✅ Invalid JWT config format error
- ✅ AWS SDK error mapping

### 5. Concurrency
- ✅ Concurrent cache access (10 parallel requests)
- ✅ Thread-safe cache operations

### 6. Configuration
- ✅ SecretManagerBuilder pattern
- ✅ Custom cache TTL
- ✅ Custom max cache entries

## Test Scenarios

### Test 1: Secret Fetch and Cache Hit
```bash
cargo test test_secret_fetch_and_cache -- --nocapture
```

**Expected Output**:
```
running 1 test
test test_secret_fetch_and_cache ... ok
```

**Behavior**:
1. First fetch: Calls AWS API → caches result
2. Second fetch: Returns cached value (no AWS call)
3. Verifies cache statistics

### Test 2: Cache TTL Expiration
```bash
cargo test test_cache_ttl_expiration -- --nocapture
```

**Expected Output**:
```
running 1 test
test test_cache_ttl_expiration ... ok
```

**Behavior**:
1. Creates manager with 2-second TTL
2. Fetches secret → cached
3. Waits 3 seconds
4. Verifies cache is empty
5. Fetches again → re-cached

### Test 3: Secret Rotation Simulation
```bash
cargo test test_secret_rotation_simulation -- --nocapture
```

**Expected Output**:
```
running 1 test
Secret V1 fetched (length: 234)
Simulating secret rotation (invalidating cache)...
Secret V2 fetched (length: 234)
Secret rotation simulation complete
In production, after AWS rotation:
1. Rotation Lambda updates secret in AWS
2. Cache expires after TTL (5 minutes default)
3. Next fetch gets new secret version
4. Old JWT tokens remain valid until expiry
test test_secret_rotation_simulation ... ok
```

### Test 4: Concurrent Access
```bash
cargo test test_concurrent_cache_access -- --nocapture
```

**Expected Output**:
```
running 1 test
Task 0: Ok(234)
Task 1: Ok(234)
Task 2: Ok(234)
...
Task 9: Ok(234)
All 10 concurrent tasks completed successfully
test test_concurrent_cache_access ... ok
```

**Behavior**:
- Spawns 10 concurrent tokio tasks
- All fetch the same secret
- Only 1 AWS API call made (rest hit cache)
- Verifies thread-safe cache access

## Real Secret Rotation Test

To test actual secret rotation (requires AWS Lambda setup):

### 1. Create Rotation Lambda

Use AWS Console or AWS CLI to create a rotation Lambda function:

**AWS Console**:
1. Go to AWS Secrets Manager → Your secret → Rotation configuration
2. Click "Enable automatic rotation"
3. Choose "Create a new Lambda function"
4. Select rotation interval (e.g., 90 days)

**AWS CLI**:
```bash
# Create Lambda function (simplified example)
aws lambda create-function \
  --function-name NovaJwtSecretRotation \
  --runtime python3.11 \
  --role arn:aws:iam::123456789012:role/lambda-rotation-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://rotation-function.zip

# Enable rotation
aws secretsmanager rotate-secret \
  --secret-id test/nova/jwt-config \
  --rotation-lambda-arn arn:aws:lambda:us-west-2:123456789012:function:NovaJwtSecretRotation \
  --rotation-rules AutomaticallyAfterDays=90
```

### 2. Trigger Manual Rotation

```bash
aws secretsmanager rotate-secret \
  --secret-id test/nova/jwt-config
```

### 3. Run Rotation Test

```bash
# Terminal 1: Run test with continuous monitoring
while true; do
  cargo test test_secret_rotation_simulation -- --nocapture
  sleep 10
done

# Terminal 2: Trigger rotation
aws secretsmanager rotate-secret --secret-id test/nova/jwt-config

# Observe: Test will continue fetching cached value until TTL expires,
# then fetch the new rotated secret
```

## Cleanup

After testing, delete the test secret:

```bash
aws secretsmanager delete-secret \
  --secret-id test/nova/jwt-config \
  --force-delete-without-recovery
```

**Without force-delete** (recommended for production):
```bash
aws secretsmanager delete-secret \
  --secret-id test/nova/jwt-config \
  --recovery-window-in-days 7
```

## Troubleshooting

### Error: "Secret not found"

**Symptom**:
```
Skipping test: Secret 'test/nova/jwt-config' not found in AWS Secrets Manager
```

**Solution**:
```bash
# Verify secret exists
aws secretsmanager describe-secret --secret-id test/nova/jwt-config

# If not found, create it (see step 2 above)
```

### Error: "AccessDeniedException"

**Symptom**:
```
thread 'test_secret_fetch_and_cache' panicked at 'Failed to fetch secret: AwsSdk("User: arn:aws:iam::123456789012:user/test-user is not authorized to perform: secretsmanager:GetSecretValue")'
```

**Solution**:
```bash
# Check IAM permissions
aws iam list-user-policies --user-name test-user
aws iam list-attached-user-policies --user-name test-user

# Attach policy
aws iam attach-user-policy \
  --user-name test-user \
  --policy-arn arn:aws:iam::123456789012:policy/NovaSecretsManagerPolicy
```

### Error: "Invalid JWT config format"

**Symptom**:
```
thread 'test_jwt_config_parsing' panicked at 'Failed to parse JWT config: InvalidFormat("Failed to parse JWT config: missing field `algorithm`")'
```

**Solution**:
```bash
# Update secret with correct format
aws secretsmanager put-secret-value \
  --secret-id test/nova/jwt-config \
  --secret-string '{
    "signing_key": "dGVzdC1zaWduaW5nLWtleS1mb3ItaW50ZWdyYXRpb24tdGVzdHM=",
    "algorithm": "HS256",
    "issuer": "nova-test",
    "audience": ["api", "test"],
    "expiry_seconds": 3600
  }'
```

### Error: "RegionDisabled"

**Symptom**:
```
Error: AwsSdk("The security token included in the request is invalid: RegionDisabledException")
```

**Solution**:
```bash
# Enable Secrets Manager in your region
aws secretsmanager list-secrets --region us-west-2

# Or change region
export AWS_DEFAULT_REGION="us-east-1"
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  integration-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-west-2

      - name: Create test secret
        run: |
          aws secretsmanager create-secret \
            --name test/nova/jwt-config-${{ github.run_id }} \
            --secret-string '{
              "signing_key": "dGVzdC1zaWduaW5nLWtleS1mb3ItaW50ZWdyYXRpb24tdGVzdHM=",
              "algorithm": "HS256",
              "issuer": "nova-test",
              "audience": ["api", "test"],
              "expiry_seconds": 3600
            }' || true

      - name: Run integration tests
        env:
          AWS_SECRETS_TEST_SECRET_NAME: test/nova/jwt-config-${{ github.run_id }}
        run: |
          cargo test --package aws-secrets --test integration_test

      - name: Cleanup test secret
        if: always()
        run: |
          aws secretsmanager delete-secret \
            --secret-id test/nova/jwt-config-${{ github.run_id }} \
            --force-delete-without-recovery || true
```

## Performance Benchmarks

Expected performance metrics:

| Operation | First Call (AWS) | Cached Call | TTL Expired |
|-----------|------------------|-------------|-------------|
| get_secret() | 50-150ms | <1ms | 50-150ms |
| get_jwt_config() | 50-150ms | <1ms | 50-150ms |
| invalidate_cache() | - | <1ms | - |

**Benchmark test**:
```bash
cargo test test_concurrent_cache_access -- --nocapture --ignored
```

## Security Notes

1. **Test Secrets**: Use separate secrets for testing (prefix: `test/`)
2. **Rotation**: Test with real rotation to verify production behavior
3. **IAM Policies**: Use least-privilege policies for test users
4. **Cleanup**: Always delete test secrets after testing
5. **Audit**: Review CloudTrail logs for test secret access

## References

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [aws-secrets Library](../src/lib.rs)
- [IRSA Setup Guide](../../../k8s/infrastructure/aws-secrets/README.md)
