# Debezium CDC Security Hardening Guide

## 威胁模型

### 潜在攻击面

```
┌────────────────────────────────────────────────────┐
│           Attack Surface Analysis                 │
├────────────────────────────────────────────────────┤
│ 1. PostgreSQL Replication Connection              │
│    Risk: Credentials leak → Full DB access        │
│    Severity: CRITICAL                              │
│                                                    │
│ 2. Kafka Topics (CDC data streams)                │
│    Risk: Unauthorized read → PII exposure         │
│    Severity: HIGH                                  │
│                                                    │
│ 3. Debezium Connect REST API                      │
│    Risk: Connector manipulation → Data loss       │
│    Severity: HIGH                                  │
│                                                    │
│ 4. Network Traffic                                │
│    Risk: Man-in-the-middle → Data interception   │
│    Severity: MEDIUM                                │
│                                                    │
│ 5. Container Images                               │
│    Risk: Supply chain attack → Backdoor           │
│    Severity: MEDIUM                                │
└────────────────────────────────────────────────────┘
```

---

## 1. PostgreSQL 安全加固

### 1.1 最小权限原则（Least Privilege）

**创建专用 CDC 用户**：
```sql
-- 创建只读复制用户
CREATE USER debezium_user WITH PASSWORD 'REPLACE_WITH_STRONG_PASSWORD' REPLICATION;

-- 仅授权需要的表
GRANT CONNECT ON DATABASE nova TO debezium_user;
GRANT USAGE ON SCHEMA public TO debezium_user;
GRANT SELECT ON public.users TO debezium_user;
GRANT SELECT ON public.posts TO debezium_user;
GRANT SELECT ON public.follows TO debezium_user;
GRANT SELECT ON public.comments TO debezium_user;
GRANT SELECT ON public.likes TO debezium_user;

-- 允许创建 publication（必需）
ALTER USER debezium_user WITH CREATEDB;  -- 仅用于创建 publication，不用于创建其他 DB

-- 撤销不必要的权限
REVOKE CREATE ON SCHEMA public FROM debezium_user;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM debezium_user;
GRANT SELECT ON ONLY public.users, public.posts, public.follows, public.comments, public.likes TO debezium_user;
```

**验证权限**：
```sql
-- 检查用户权限
SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'debezium_user';

-- 确认无写权限
SELECT has_table_privilege('debezium_user', 'public.users', 'INSERT');  -- Should return false
```

---

### 1.2 密码安全

**强密码策略**（至少 32 字符）：
```bash
# 生成强密码
openssl rand -base64 32

# 示例：8vZ3x7J2mN9qL4wP5tY6uR8sA1bC9dE0
```

**使用 AWS Secrets Manager**：
```bash
# 存储密码
aws secretsmanager create-secret \
  --name nova/debezium/postgres-password \
  --secret-string "8vZ3x7J2mN9qL4wP5tY6uR8sA1bC9dE0" \
  --tags Key=Project,Value=nova Key=Component,Value=cdc

# Debezium 容器中读取
export DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id nova/debezium/postgres-password \
  --query SecretString --output text)
```

**启用密码轮换**（90 天周期）：
```sql
-- 创建新密码并更新
ALTER USER debezium_user WITH PASSWORD 'NEW_PASSWORD';

-- 更新 Debezium Connector 配置
curl -X PUT http://debezium:8083/connectors/nova-postgres-cdc-connector/config \
  -H "Content-Type: application/json" \
  -d '{
    "database.password": "NEW_PASSWORD"
  }'
```

---

### 1.3 网络隔离

**PostgreSQL Security Group**（仅允许 Debezium 访问）：
```hcl
# Terraform 示例
resource "aws_security_group" "postgres" {
  name        = "nova-postgres-sg"
  description = "Allow PostgreSQL access from Debezium only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Debezium"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.debezium.id]  # Only Debezium SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**禁用公网访问**：
```hcl
resource "aws_db_instance" "postgres" {
  publicly_accessible = false  # 强制使用 VPC 内部访问
  ...
}
```

**启用 SSL/TLS 加密**：
```sql
-- 强制 SSL 连接
ALTER SYSTEM SET ssl = on;
ALTER USER debezium_user SET sslmode = 'require';
SELECT pg_reload_conf();
```

**Debezium 连接配置**：
```json
{
  "database.sslmode": "require",
  "database.sslrootcert": "/etc/ssl/certs/rds-ca-2019-root.pem",
  "database.sslcert": "/etc/ssl/certs/client-cert.pem",
  "database.sslkey": "/etc/ssl/private/client-key.pem"
}
```

---

### 1.4 审计日志

**启用 PostgreSQL 日志**：
```sql
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_statement = 'ddl';  -- 记录 DDL 语句
ALTER SYSTEM SET log_min_duration_statement = 1000;  -- 慢查询 > 1s
SELECT pg_reload_conf();
```

**监控 Replication Connections**：
```sql
-- 检查当前复制连接
SELECT
    client_addr,
    usename,
    application_name,
    state,
    backend_start
FROM pg_stat_replication;

-- 告警：非预期连接
SELECT *
FROM pg_stat_replication
WHERE application_name != 'debezium' OR usename != 'debezium_user';
```

---

## 2. Kafka 安全加固

### 2.1 SASL/SCRAM 认证

**启用 SCRAM-SHA-512**：
```properties
# kafka/config/server.properties
listeners=SASL_SSL://0.0.0.0:9093
security.inter.broker.protocol=SASL_SSL
sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
sasl.enabled.mechanisms=SCRAM-SHA-512

# SSL 配置
ssl.keystore.location=/etc/kafka/secrets/kafka.keystore.jks
ssl.keystore.password=keystore_password
ssl.key.password=key_password
ssl.truststore.location=/etc/kafka/secrets/kafka.truststore.jks
ssl.truststore.password=truststore_password
```

**创建 Kafka 用户**：
```bash
# 创建 Debezium 用户
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --add-config 'SCRAM-SHA-512=[password=debezium_password]' \
  --entity-type users --entity-name debezium_user

# 创建 Flink 消费者用户
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --add-config 'SCRAM-SHA-512=[password=flink_password]' \
  --entity-type users --entity-name flink_consumer
```

**Debezium 客户端配置**：
```json
{
  "producer.security.protocol": "SASL_SSL",
  "producer.sasl.mechanism": "SCRAM-SHA-512",
  "producer.sasl.jaas.config": "org.apache.kafka.common.security.scram.ScramLoginModule required username=\"debezium_user\" password=\"debezium_password\";",
  "producer.ssl.truststore.location": "/etc/kafka/secrets/truststore.jks",
  "producer.ssl.truststore.password": "truststore_password"
}
```

---

### 2.2 ACL 权限控制

**启用 ACL**：
```properties
# server.properties
authorizer.class.name=kafka.security.authorizer.AclAuthorizer
allow.everyone.if.no.acl.found=false  # 默认拒绝所有访问
```

**配置 Debezium 权限**（仅生产者）：
```bash
# 允许写入 CDC topics
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add --allow-principal User:debezium_user \
  --operation Write --topic 'cdc.*'

# 允许创建 topics（首次启动）
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add --allow-principal User:debezium_user \
  --operation Create --cluster

# 允许访问 consumer group（Debezium Connect 内部使用）
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add --allow-principal User:debezium_user \
  --operation All --group 'debezium-nova'
```

**配置 Flink 权限**（仅消费者）：
```bash
# 允许读取 CDC topics
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add --allow-principal User:flink_consumer \
  --operation Read --topic 'cdc.*'

# 允许管理 consumer group offsets
kafka-acls.sh --bootstrap-server localhost:9092 \
  --add --allow-principal User:flink_consumer \
  --operation Read --group 'flink-cdc-consumer'
```

**验证 ACL**：
```bash
# 列出所有 ACL
kafka-acls.sh --bootstrap-server localhost:9092 --list

# 测试权限
kafka-console-producer.sh --bootstrap-server localhost:9092 \
  --topic cdc.users \
  --producer-property security.protocol=SASL_SSL \
  --producer-property sasl.mechanism=SCRAM-SHA-512 \
  --producer-property sasl.jaas.config='...'
```

---

### 2.3 数据加密

**传输加密（TLS 1.3）**：
```bash
# 生成 CA 证书
openssl req -new -x509 -keyout ca-key -out ca-cert -days 3650

# 生成 Broker 证书
keytool -keystore kafka.keystore.jks -alias localhost -validity 3650 -genkey \
  -keyalg RSA -ext SAN=DNS:kafka-broker-1.example.com

# 签名证书
keytool -keystore kafka.keystore.jks -alias localhost -certreq -file cert-file
openssl x509 -req -CA ca-cert -CAkey ca-key -in cert-file -out cert-signed -days 3650 -CAcreateserial
keytool -keystore kafka.keystore.jks -alias localhost -import -file cert-signed
```

**静态数据加密（AWS KMS）**：
```hcl
resource "aws_msk_cluster" "nova_kafka" {
  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.kafka.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }
}

resource "aws_kms_key" "kafka" {
  description = "KMS key for Kafka encryption"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::ACCOUNT_ID:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}
```

---

### 2.4 Topic 级数据脱敏

**敏感字段脱敏**（在 Debezium 中处理）：
```json
{
  "transforms": "maskEmail,maskPhone",

  "transforms.maskEmail.type": "org.apache.kafka.connect.transforms.MaskField$Value",
  "transforms.maskEmail.fields": "email",
  "transforms.maskEmail.replacement": "***@***.com",

  "transforms.maskPhone.type": "org.apache.kafka.connect.transforms.ReplaceField$Value",
  "transforms.maskPhone.renames": "phone:phone_masked",
  "transforms.maskPhone.replacement": "XXX-XXX-1234"
}
```

**更好的方案：在 Flink 中脱敏**（保留原始数据用于审计）：
```java
DataStream<RowData> maskedStream = cdcStream.map(row -> {
    String email = row.getString("email");
    if (email != null) {
        // 保留域名用于分析，脱敏用户名
        String maskedEmail = email.replaceAll("(^[^@]{3})[^@]+(@.*)", "$1***$2");
        row.setField("email", maskedEmail);
    }
    return row;
});
```

---

## 3. Debezium Connect 安全加固

### 3.1 REST API 认证

**启用 HTTP Basic Auth**：
```properties
# connect-distributed.properties
rest.extension.classes=io.confluent.connect.security.ConnectSecurityExtension
confluent.metadata.basic.auth.user.info=admin:admin_password
```

**使用 API Gateway + IAM 认证**（AWS）：
```hcl
resource "aws_api_gateway_rest_api" "debezium" {
  name = "debezium-connect-api"

  endpoint_configuration {
    types = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.apigw.id]
  }
}

resource "aws_api_gateway_authorizer" "iam" {
  name        = "iam-authorizer"
  rest_api_id = aws_api_gateway_rest_api.debezium.id
  type        = "AWS_IAM"
}
```

**调用 API 示例**：
```bash
# 使用 AWS SigV4 签名
aws-api-call \
  --region us-east-1 \
  --service execute-api \
  --endpoint https://debezium-api.example.com/connectors/nova-postgres-cdc-connector/status
```

---

### 3.2 容器镜像扫描

**使用 Trivy 扫描漏洞**：
```bash
# 扫描 Debezium 官方镜像
trivy image debezium/connect:2.4

# 输出示例
# Total: 3 (CRITICAL: 1, HIGH: 2)
# CVE-2023-xxxxx: OpenSSL vulnerability
```

**仅使用签名镜像**：
```yaml
# docker-compose.yml
services:
  debezium:
    image: debezium/connect@sha256:abc123...  # 使用 digest 而非 tag
    ...
```

**定期更新镜像**（每月）：
```bash
# 拉取最新镜像
docker pull debezium/connect:2.4

# 检查更新日志
curl https://debezium.io/releases/2.4/release-notes/
```

---

### 3.3 运行时安全

**非 root 用户运行**：
```dockerfile
# Dockerfile
FROM debezium/connect:2.4

# 创建非特权用户
RUN groupadd -r debezium && useradd -r -g debezium debezium
USER debezium
```

**限制容器权限**：
```yaml
# docker-compose.yml
services:
  debezium:
    image: debezium/connect:2.4
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp
      - /var/tmp
```

**资源限制**：
```yaml
services:
  debezium:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
          pids: 200  # 防止 fork bomb
```

---

## 4. 网络安全

### 4.1 VPC 设计

**三层隔离**：
```
┌─────────────────────────────────────────────────┐
│              VPC: 10.0.0.0/16                   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  Public Subnet: 10.0.1.0/24             │   │
│  │  (ALB, NAT Gateway)                     │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  Private Subnet: 10.0.10.0/24           │   │
│  │  (Debezium, Flink, App Servers)         │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  Database Subnet: 10.0.20.0/24          │   │
│  │  (PostgreSQL, Kafka - No Internet)      │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

**Terraform 示例**：
```hcl
resource "aws_subnet" "database" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "nova-database-subnet"
    Tier = "database"
  }
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id
  # 无 Internet Gateway 路由，完全隔离
}
```

---

### 4.2 Network ACLs

**Database Subnet NACL**（仅允许内部流量）：
```hcl
resource "aws_network_acl" "database" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.database.id]

  # 允许来自 Private Subnet 的 PostgreSQL 连接
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    from_port  = 5432
    to_port    = 5432
    cidr_block = "10.0.10.0/24"  # Private Subnet
    action     = "allow"
  }

  # 允许来自 Private Subnet 的 Kafka 连接
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    from_port  = 9092
    to_port    = 9092
    cidr_block = "10.0.10.0/24"
    action     = "allow"
  }

  # 拒绝所有其他流量
  ingress {
    rule_no    = 999
    protocol   = "-1"
    cidr_block = "0.0.0.0/0"
    action     = "deny"
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    cidr_block = "10.0.10.0/24"
    action     = "allow"
  }
}
```

---

### 4.3 WAF 防护（可选）

**保护 Debezium REST API**：
```hcl
resource "aws_wafv2_web_acl" "debezium_api" {
  name  = "debezium-api-waf"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "AllowInternalIPs"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.internal_ips.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowInternalIPs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "RateLimitRule"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }
}
```

---

## 5. 合规性（GDPR/CCPA）

### 5.1 数据保留策略

**Kafka Topic 配置**：
```bash
# 用户数据：7 天保留（满足"被遗忘权"）
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --entity-type topics --entity-name cdc.users \
  --add-config retention.ms=604800000

# 审计日志：5 年保留（法规要求）
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --entity-type topics --entity-name audit-logs \
  --add-config retention.ms=157680000000
```

**自动删除脚本**：
```bash
#!/bin/bash
# delete-user-data.sh

USER_ID=$1

# 1. 软删除 PostgreSQL（触发 CDC）
psql -U postgres -d nova -c \
  "UPDATE users SET deleted_at = NOW() WHERE id = $USER_ID;"

# 2. Debezium 发送 tombstone 到 Kafka

# 3. Flink 消费后删除 ClickHouse 数据
clickhouse-client --query "ALTER TABLE users DELETE WHERE id = $USER_ID;"

# 4. 删除 Redis 缓存
redis-cli DEL "user:$USER_ID:*"

echo "User $USER_ID data deleted from all systems."
```

---

### 5.2 数据访问审计

**记录所有 Kafka 消费**：
```java
// Flink Consumer with Audit
KafkaSource<RowData> source = KafkaSource.<RowData>builder()
    .setValueOnlyDeserializer(new RowDataDeserializer())
    .setTopics("cdc.users")
    .setProperty("group.id", "flink-cdc-consumer")
    .setProperty("enable.auto.commit", "false")
    .setProperty("audit.log.enabled", "true")  // 自定义审计
    .build();

// 审计逻辑
stream.map(new AuditMapFunction())
    .addSink(new AuditLogSink());  // 写入审计日志 Topic

public class AuditMapFunction implements MapFunction<RowData, AuditLog> {
    @Override
    public AuditLog map(RowData row) {
        return new AuditLog(
            System.currentTimeMillis(),
            "flink-cdc-consumer",
            "READ",
            "cdc.users",
            row.getLong("id"),
            row.getString("email")  // 脱敏后的
        );
    }
}
```

**审计日志格式**：
```json
{
  "timestamp": 1697123456789,
  "service": "flink-cdc-consumer",
  "action": "READ",
  "resource": "cdc.users",
  "user_id": 123,
  "data_accessed": "m***@example.com",
  "ip_address": "10.0.10.50",
  "compliance": "GDPR"
}
```

---

## 6. 事件响应计划

### 6.1 安全事件分类

| 严重级别 | 事件示例 | 响应时间 |
|---------|---------|---------|
| P0 (Critical) | Debezium 凭据泄露 | 15 分钟 |
| P1 (High) | 未授权 Kafka 访问 | 1 小时 |
| P2 (Medium) | 异常流量峰值 | 4 小时 |
| P3 (Low) | 容器镜像漏洞 | 24 小时 |

---

### 6.2 响应流程（P0 示例）

**场景**：Debezium PostgreSQL 密码泄露

**1. 检测**（自动告警）：
```bash
# CloudWatch Alarm: 检测到非预期 IP 连接 PostgreSQL
aws cloudwatch put-metric-alarm \
  --alarm-name postgres-unexpected-connection \
  --alarm-actions arn:aws:sns:us-east-1:ACCOUNT_ID:security-alerts \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold
```

**2. 隔离**（立即执行）：
```bash
# 撤销 debezium_user 权限
psql -U postgres -d nova -c "REVOKE ALL ON DATABASE nova FROM debezium_user;"

# 暂停 Debezium Connector
curl -X PUT http://debezium:8083/connectors/nova-postgres-cdc-connector/pause

# 阻止可疑 IP（Security Group）
aws ec2 revoke-security-group-ingress \
  --group-id sg-xxxxxx \
  --ip-permissions IpProtocol=tcp,FromPort=5432,ToPort=5432,IpRanges=[{CidrIp=SUSPICIOUS_IP/32}]
```

**3. 根因分析**：
```sql
-- 检查审计日志
SELECT
    event_time,
    database_name,
    user_name,
    remote_host,
    command_tag
FROM rds_audit_log
WHERE user_name = 'debezium_user'
  AND event_time > NOW() - INTERVAL '1 hour'
ORDER BY event_time DESC;
```

**4. 恢复**：
```bash
# 轮换密码
NEW_PASSWORD=$(openssl rand -base64 32)
psql -U postgres -d nova -c "ALTER USER debezium_user WITH PASSWORD '$NEW_PASSWORD';"

# 更新 Secrets Manager
aws secretsmanager update-secret \
  --secret-id nova/debezium/postgres-password \
  --secret-string "$NEW_PASSWORD"

# 重新授权
psql -U postgres -d nova -c "GRANT SELECT ON public.users, public.posts, public.follows, public.comments, public.likes TO debezium_user;"

# 重启 Connector
curl -X PUT http://debezium:8083/connectors/nova-postgres-cdc-connector/resume
```

**5. 事后总结**：
- 为什么凭据泄露？（Git 提交、日志泄露、供应链攻击？）
- 如何预防？（强制使用 Secrets Manager、代码审查、镜像扫描）
- 更新 Runbook

---

## 7. 安全检查清单

### 部署前检查

- [ ] PostgreSQL 使用专用低权限用户
- [ ] 密码存储在 Secrets Manager（不在代码/配置文件中）
- [ ] PostgreSQL 仅在 VPC 内部访问（禁用公网）
- [ ] 启用 PostgreSQL SSL/TLS
- [ ] Kafka 启用 SASL/SCRAM + TLS
- [ ] Kafka 配置 ACL（最小权限）
- [ ] Debezium REST API 需要认证
- [ ] 容器镜像已扫描漏洞（Trivy/Clair）
- [ ] Security Groups 仅允许必要端口
- [ ] 所有服务在 Private Subnet 运行
- [ ] 启用 CloudWatch Logs + Audit Logs

### 运行中监控

- [ ] 每日检查 Debezium 凭据是否泄露（GitHub Secrets Scanner）
- [ ] 每周扫描容器镜像漏洞
- [ ] 每月轮换密码
- [ ] 每季度审查 Kafka ACL
- [ ] 每年渗透测试

---

## 8. 参考资料

- [Debezium Security Documentation](https://debezium.io/documentation/reference/configuration/security.html)
- [Kafka Security Guide](https://docs.confluent.io/platform/current/security/index.html)
- [PostgreSQL Security Best Practices](https://www.postgresql.org/docs/current/security-best-practices.html)
- [OWASP API Security Top 10](https://owasp.org/www-project-api-security/)
- [AWS Security Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)

---

**文档版本**: 1.0
**最后更新**: 2024-10-18
**负责人**: Security Team
**审核周期**: 每季度
