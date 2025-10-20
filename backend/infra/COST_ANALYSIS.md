# Nova CDC Infrastructure Cost Analysis

## 执行摘要

| 环境 | 月度成本 | 年度成本 | 成本优化后 |
|------|---------|---------|-----------|
| 开发环境 | $120 | $1,440 | $60 (Spot) |
| 预生产环境 | $850 | $10,200 | $520 (混合) |
| 生产环境 | $3,500 | $42,000 | $2,100 (优化) |

**关键结论**：通过 Spot Instances、Tiered Storage 和右侧调整，可节省 **40-50% 成本**。

---

## 1. 生产环境成本明细（AWS US-East-1）

### 1.1 Debezium Connect 集群

**配置**：3x m5.xlarge (4 vCPU, 16GB RAM)

| 项目 | 配置 | 单价 | 数量 | 月度成本 |
|------|------|------|------|---------|
| EC2 实例 | m5.xlarge | $0.192/h | 3 | $414 |
| EBS 存储 | gp3 100GB | $0.08/GB | 3 | $24 |
| **小计** | | | | **$438** |

**优化方案**：
- 使用 Spot Instances → **$165/月**（节省 60%）
- 使用 Graviton 实例（m6g.xlarge）→ **$330/月**（节省 20%）

---

### 1.2 Kafka 集群（Amazon MSK）

**配置**：5x kafka.m5.2xlarge (8 vCPU, 32GB RAM)

| 项目 | 配置 | 单价 | 数量 | 月度成本 |
|------|------|------|------|---------|
| MSK Broker | kafka.m5.2xlarge | $0.777/h | 5 | $2,798 |
| 存储 (EBS) | 500GB per broker | $0.10/GB | 5 | $250 |
| 数据传输（入站）| 100GB/天 | $0.01/GB | 3000GB | $30 |
| 数据传输（出站）| 50GB/天 | $0.09/GB | 1500GB | $135 |
| **小计** | | | | **$3,213** |

**优化方案**：
- **Tiered Storage**（Kafka 3.6+）：
  - 本地保留 1 天，远程保留 30 天
  - 本地存储：100GB x 5 = 500GB → $50/月
  - S3 远程存储：3TB → $69/月
  - **总成本**：$2,892/月（节省 10%）

- **使用 Kafka Connect 自建**（不推荐生产环境）：
  - 5x m5.2xlarge EC2 + EBS
  - 成本：$1,400/月（节省 50%）
  - 缺点：需要人工运维

---

### 1.3 PostgreSQL（RDS）

**配置**：db.r6g.4xlarge (16 vCPU, 128GB RAM) + 读副本

| 项目 | 配置 | 单价 | 数量 | 月度成本 |
|------|------|------|------|---------|
| 主实例 | db.r6g.4xlarge | $1.224/h | 1 | $881 |
| 读副本 | db.r6g.2xlarge | $0.612/h | 1 | $441 |
| 存储 (io2) | 1TB | $0.149/GB | 1000GB | $149 |
| IOPS | 20000 IOPS | $0.119/IOPS | 20000 | $2,380 |
| 备份存储 | 500GB | $0.095/GB | 500GB | $48 |
| **小计** | | | | **$3,899** |

**CDC 额外开销**：
- WAL 存储增加：+50GB → **+$7/月**
- CPU 利用率增加 10-15%（无额外成本）

**优化方案**：
- 使用 Aurora PostgreSQL：
  - 自动扩缩容
  - 无需管理 WAL
  - 成本约 $3,200/月（节省 18%）

---

### 1.4 数据传输成本

| 项目 | 流量 | 单价 | 月度成本 |
|------|------|------|---------|
| PostgreSQL → Debezium | 100GB/天 | 同 AZ 免费 | $0 |
| Debezium → Kafka | 100GB/天 | 同 AZ 免费 | $0 |
| Kafka → Flink | 50GB/天 | 同 AZ 免费 | $0 |
| 跨 AZ 传输 | 20GB/天 | $0.01/GB | $6 |
| **小计** | | | **$6** |

**关键**：部署在同一 AZ 内可节省 90% 传输成本。

---

## 2. 总成本汇总（月度）

### 生产环境

| 组件 | 基础成本 | 优化后成本 | 节省率 |
|------|---------|-----------|--------|
| Debezium Connect | $438 | $165 (Spot) | 62% |
| Kafka (MSK) | $3,213 | $2,892 (Tiered) | 10% |
| PostgreSQL CDC 额外成本 | $7 | $7 | 0% |
| 数据传输 | $6 | $6 | 0% |
| **总计** | **$3,664** | **$3,070** | **16%** |

### 预生产环境（规模减半）

| 组件 | 成本 |
|------|------|
| Debezium Connect | 2x m5.large (Spot) → $80 |
| Kafka (MSK) | 3x kafka.m5.xlarge → $840 |
| PostgreSQL | db.r6g.xlarge → $220 |
| **总计** | **$1,140** |

### 开发环境（本地 Docker）

| 组件 | 成本 |
|------|------|
| 本地 Docker | $0 |
| **总计** | **$0** |

---

## 3. 容量规划

### 当前吞吐量假设

| 指标 | 值 |
|------|---|
| 日活用户（DAU） | 1,000,000 |
| 每用户日均操作 | 50 次 |
| 日总操作量 | 50,000,000 |
| 每秒操作峰值 | 2,000 ops/s (假设峰谷比 3:1) |
| 平均消息大小 | 2KB |
| 日数据量 | 100GB |

### Kafka 分区容量

| Topic | 分区数 | 日消息量 | 保留时间 | 存储需求 |
|-------|-------|---------|---------|---------|
| cdc.users | 3 | 100万 | 7天 | 14GB |
| cdc.posts | 10 | 1000万 | 30天 | 600GB |
| cdc.follows | 5 | 500万 | 7天 | 70GB |
| cdc.comments | 5 | 800万 | 14天 | 224GB |
| cdc.likes | 8 | 2000万 | 14天 | 560GB |
| events | 300 | 5000万 | 3天 | 300GB |
| **总计** | **331** | **79,000万** | | **1.7TB** |

### 扩容触发条件

| 指标 | 当前配置 | 扩容阈值 | 扩容后配置 |
|------|---------|---------|-----------|
| Kafka Broker CPU | 5x m5.2xlarge | 平均 CPU > 70% | 7x m5.2xlarge |
| Kafka Disk | 500GB/broker | 磁盘使用 > 80% | 1TB/broker |
| Debezium Lag | < 1000 records | Lag > 5000 | 增加 tasks.max 到 3 |
| Kafka Partitions | 331 | 消费延迟 > 10s | 增加 50% 分区 |

---

## 4. 成本优化策略

### 4.1 Compute 优化（节省 40%）

**1. Spot Instances for Debezium**
```bash
# Terraform 示例
resource "aws_spot_instance_request" "debezium" {
  instance_type = "m5.xlarge"
  spot_price    = "0.08"  # 60% discount

  user_data = <<-EOF
    #!/bin/bash
    docker run -d debezium/connect:2.4
  EOF
}
```

成本：$438 → **$165/月**

**2. Graviton Instances（ARM 架构）**
- m5.xlarge → m6g.xlarge
- 性能相当，成本降低 20%

成本：$438 → **$330/月**

**3. Auto Scaling Groups**
```hcl
resource "aws_autoscaling_group" "debezium" {
  min_size = 2
  max_size = 5
  desired_capacity = 3

  # 非峰值时间缩容到 2 实例
  target_tracking_configuration {
    predefined_metric_type = "ASGAverageCPUUtilization"
    target_value = 60.0
  }
}
```

节省：非峰值 8 小时/天 → **额外节省 $100/月**

---

### 4.2 Storage 优化（节省 30%）

**1. Kafka Tiered Storage**
```properties
# server.properties
remote.log.storage.enable=true
remote.log.storage.system.enable=true
log.local.retention.ms=86400000  # 1 day local
log.retention.ms=2592000000      # 30 days remote (S3)
```

存储成本：
- 本地 500GB x 5 = 2.5TB @ $0.10/GB → $250/月
- 远程 3TB @ $0.023/GB → $69/月

优化后：100GB x 5 (local) + 3TB (S3) = **$119/月**（节省 52%）

**2. 日志压缩**
```properties
compression.type=snappy  # 或 lz4, zstd
```

压缩率：2KB → 1.2KB（40% 压缩）
存储需求：1.7TB → **1TB**（节省 $70/月）

**3. 定期清理 Replication Slots**
```sql
-- 监控 WAL 占用
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn))
FROM pg_replication_slots;

-- 删除不活跃的 slot
SELECT pg_drop_replication_slot('old_slot');
```

---

### 4.3 Network 优化（节省 $120/月）

**1. 同 AZ 部署**
```
┌─────────────────────────────────┐
│         us-east-1a              │
│  ┌──────────┐  ┌──────────┐    │
│  │ Postgres │→ │ Debezium │    │
│  └──────────┘  └─────┬────┘    │
│                      ↓          │
│               ┌──────────┐      │
│               │  Kafka   │      │
│               └─────┬────┘      │
│                     ↓           │
│               ┌──────────┐      │
│               │  Flink   │      │
│               └──────────┘      │
└─────────────────────────────────┘
```

数据传输成本：$171/月 → **$6/月**（节省 97%）

**2. VPC Endpoint for S3（Tiered Storage）**
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.s3"
}
```

节省 S3 数据传输费用：$50/月

**3. 启用 Kafka Compression**
- 出站流量：150GB/天 → 90GB/天（40% 压缩）
- 成本：$135/月 → **$81/月**

---

### 4.4 FinOps 最佳实践

**1. Reserved Instances（1年预付）**
- RDS db.r6g.4xlarge: $881/月 → $529/月（40% 折扣）
- MSK Broker: $2,798/月 → $1,959/月（30% 折扣）

**2. Savings Plans（3年预付）**
- EC2/MSK 额外节省 10-15%

**3. 成本分配标签**
```hcl
tags = {
  Project     = "nova"
  Component   = "cdc-infrastructure"
  Environment = "production"
  Team        = "platform"
  CostCenter  = "engineering"
}
```

**4. 日度成本监控**
```bash
# AWS Cost Explorer API
aws ce get-cost-and-usage \
  --time-period Start=2024-10-01,End=2024-10-18 \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter file://filter.json
```

**5. 预算告警**
```hcl
resource "aws_budgets_budget" "cdc" {
  name         = "nova-cdc-monthly"
  budget_type  = "COST"
  limit_amount = "4000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator = "GREATER_THAN"
    threshold           = 80
    notification_type   = "ACTUAL"
  }
}
```

---

## 5. 优化后成本对比

### 月度成本

| 优化措施 | 基础成本 | 优化后成本 | 节省 |
|---------|---------|-----------|------|
| **Compute** | | | |
| Debezium (Spot + Graviton) | $438 | $132 | $306 |
| Kafka (MSK Reserved) | $2,798 | $1,959 | $839 |
| **Storage** | | | |
| Kafka (Tiered + Compression) | $250 | $119 | $131 |
| PostgreSQL WAL | $7 | $7 | $0 |
| **Network** | | | |
| Same AZ + Compression | $171 | $40 | $131 |
| **总计** | **$3,664** | **$2,257** | **$1,407 (38%)** |

### 年度成本

| 场景 | 月度成本 | 年度成本 | 年度节省 |
|------|---------|---------|---------|
| 基础配置 | $3,664 | $43,968 | - |
| 优化配置 | $2,257 | $27,084 | **$16,884** |
| 进一步优化（3年 RI） | $1,900 | $22,800 | **$21,168** |

---

## 6. ROI 分析

### 投入

| 项目 | 成本 |
|------|------|
| 初始搭建（工程师时间） | $8,000（40小时 x $200/h） |
| 首月云资源 | $3,664 |
| 监控工具（Datadog） | $200/月 |
| **初始投入** | **$11,864** |

### 对比方案：定时轮询（传统方案）

| 项目 | 成本 |
|------|------|
| Cron Job EC2 (m5.xlarge x 3) | $414/月 |
| RDS 额外负载（需要更大实例） | +$500/月 |
| 延迟问题导致用户流失 | **不可量化** |
| **月度成本** | **$914/月** |

**CDC 相对传统方案的额外成本**：$3,664 - $914 = **$2,750/月**

**但获得**：
- 实时数据（< 1s 延迟 vs 分钟级）
- 数据库负载降低 90%
- 支持实时热榜（核心产品功能）

**结论**：CDC 是**必需投入**，不是可选优化。

---

## 7. 推荐配置

### 阶段 1: MVP（0-100K DAU）

| 组件 | 配置 | 月度成本 |
|------|------|---------|
| Debezium | 2x m6g.large (Spot) | $60 |
| Kafka (Self-Hosted) | 3x m5.xlarge (Spot) | $180 |
| PostgreSQL | db.t4g.xlarge (RDS) | $150 |
| **总计** | | **$390/月** |

### 阶段 2: 成长期（100K-1M DAU）

| 组件 | 配置 | 月度成本 |
|------|------|---------|
| Debezium | 3x m6g.xlarge (Spot) | $200 |
| Kafka (MSK) | 3x kafka.m5.xlarge | $1,680 |
| PostgreSQL | db.r6g.xlarge (RDS) | $450 |
| **总计** | | **$2,330/月** |

### 阶段 3: 规模化（1M+ DAU）

| 组件 | 配置 | 月度成本 |
|------|------|---------|
| Debezium | 3x m6g.xlarge (1年 RI) | $165 |
| Kafka (MSK) | 5x kafka.m5.2xlarge (1年 RI) + Tiered | $2,078 |
| PostgreSQL Aurora | db.r6g.4xlarge (1年 RI) | $1,600 |
| **总计** | | **$3,843/月** |

---

## 8. 监控成本漂移

### 关键指标

```sql
-- Kafka 存储增长率（每日监控）
SELECT
  topic,
  SUM(size_bytes) / 1024 / 1024 / 1024 AS size_gb,
  LAG(SUM(size_bytes)) OVER (PARTITION BY topic ORDER BY DATE) AS prev_size
FROM kafka_metrics
GROUP BY topic, DATE
HAVING (SUM(size_bytes) - prev_size) / prev_size > 0.1;  -- 增长 > 10%

-- Debezium Lag（每分钟监控）
SELECT
  connector_name,
  max_lag_ms
FROM debezium_metrics
WHERE max_lag_ms > 5000;  -- 延迟 > 5s

-- PostgreSQL WAL 占用（每小时监控）
SELECT
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag_size
FROM pg_replication_slots
WHERE lag_size > '10GB';
```

### 成本告警规则

```yaml
# CloudWatch Alarm
alarms:
  - name: kafka-storage-high
    metric: kafka.log.size
    threshold: 2000  # 2TB
    period: 1h
    action: email + auto-scale

  - name: debezium-lag-critical
    metric: debezium.records.lag
    threshold: 10000
    period: 5m
    action: pagerduty

  - name: monthly-cost-overage
    metric: aws.billing.estimated_charges
    threshold: 4000  # $4000/month
    period: 1d
    action: email
```

---

## 9. 总结与建议

### 立即执行（第 1 周）

1. ✅ 使用 Spot Instances 部署 Debezium（节省 $273/月）
2. ✅ 所有服务部署在同一 AZ（节省 $165/月）
3. ✅ 启用 Kafka 压缩（节省 $54/月）

**快速节省**：**$492/月**

### 短期优化（第 1 个月）

4. ✅ 配置 Kafka Tiered Storage（节省 $131/月）
5. ✅ 切换到 Graviton 实例（节省 $88/月）
6. ✅ 实施 Auto Scaling（节省 $100/月）

**短期节省**：**$319/月**

### 长期规划（3 个月后）

7. ✅ 购买 1 年 Reserved Instances（节省 $1,400/月）
8. ✅ 切换到 Aurora PostgreSQL（节省 $700/月）
9. ✅ 实施日志压缩策略（节省 $70/月）

**长期节省**：**$2,170/月**

### 最终成本

| 时间点 | 成本 | 累计节省 |
|-------|------|---------|
| 当前（未优化） | $3,664/月 | - |
| 第 1 周（Spot + Same AZ） | $3,172/月 | $492/月 |
| 第 1 月（Tiered Storage） | $2,853/月 | $811/月 |
| 第 3 月（Reserved Instances） | $1,900/月 | $1,764/月 |

**年度节省**：**$21,168**

---

## 附录：Terraform Cost Estimation

```hcl
# 使用 Infracost 自动估算成本
# https://www.infracost.io/

resource "aws_msk_cluster" "nova_kafka" {
  cluster_name           = "nova-kafka-prod"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 5

  broker_node_group_info {
    instance_type   = "kafka.m5.2xlarge"
    storage_info {
      ebs_storage_info {
        volume_size = 500
      }
    }
  }
}

# 运行成本估算
# infracost breakdown --path . --format table
#
# 输出示例：
# Name                         Monthly Qty  Unit         Monthly Cost
# aws_msk_cluster.nova_kafka
#  ├─ Broker hours                    3,720  hours              $2,890
#  ├─ Storage                         2,500  GB                   $250
#  └─ Data transfer                   1,500  GB                   $135
# TOTAL                                                         $3,275
```

---

**文档版本**: 1.0
**最后更新**: 2024-10-18
**负责人**: Platform Team
**审核周期**: 每季度
