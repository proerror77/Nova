# Prometheus AlertManager 通知模板

## 概述

本文档定义了发送给 Slack、Email、PagerDuty 等渠道的告警通知模板。

---

## 1. Slack 通知模板

### 配置

```yaml
# alertmanager.yml
route:
  receiver: 'slack'
  group_by: ['alertname', 'cluster']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 6h

receivers:
  - name: 'slack'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
        channel: '#nova-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
```

### 消息格式

#### 严重级别（Critical）
```
🚨 CRITICAL ALERT

Alert: {{ .CommonAnnotations.summary }}
Status: {{ .Status }}
Severity: {{ .CommonLabels.severity }}

Description:
{{ .CommonAnnotations.description }}

Component: {{ .CommonLabels.component }}
Instance: {{ (index .Alerts 0).Labels.instance }}

View: {{ .GroupLabels.alertname }}

Runbook: https://wiki.internal.example.com/runbooks/{{ .GroupLabels.alertname }}
```

#### 警告级别（Warning）
```
⚠️ WARNING

Alert: {{ .CommonAnnotations.summary }}
Status: {{ .Status }}

Details: {{ .CommonAnnotations.description }}

View in Grafana: https://grafana.internal.example.com/d/{{ .CommonLabels.dashboard }}
```

#### 恢复通知（Resolved）
```
✅ RESOLVED

Alert: {{ .CommonAnnotations.summary }}
Status: Resolved at {{ .Alerts.0.EndsAt }}

Duration: {{ (now.Sub (index .Alerts 0).StartsAt).Round 5m }}
```

---

## 2. Email 通知模板

### 配置

```yaml
# alertmanager.yml
receivers:
  - name: 'email'
    email_configs:
      - to: 'oncall@example.com'
        from: 'alerts@nova.internal'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alerts@example.com'
        auth_password: '${SMTP_PASSWORD}'
        headers:
          Subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
```

### 邮件正文模板

**Subject**: `[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }} on {{ .CommonLabels.component }}`

**Body**:
```
{{ .Alerts.Firing | len }} active alerts:

Severity: {{ .CommonLabels.severity }}
Component: {{ .CommonLabels.component }}

{{ range .Alerts.Firing }}
Alert: {{ .Labels.alertname }}
Instance: {{ .Labels.instance }}
Fired: {{ .StartsAt.Format "2006-01-02 15:04:05" }} UTC

{{ .Annotations.description }}

Recommended Actions:
{{ .Annotations.runbook }}

---
{{ end }}

Silence this alert:
https://alertmanager.internal.example.com/?silences=component%3D{{ .CommonLabels.component }}
```

---

## 3. PagerDuty 通知模板

### 配置

```yaml
# alertmanager.yml
receivers:
  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
        description: '{{ .GroupLabels.alertname }}'
        details:
          firing: '{{ range .Alerts.Firing }}{{ .Labels.instance }} {{ end }}'
          resolved: '{{ range .Alerts.Resolved }}{{ .Labels.instance }} {{ end }}'
```

### 有效载荷示例

```json
{
  "routing_key": "${PAGERDUTY_ROUTING_KEY}",
  "event_action": "trigger",
  "dedup_key": "{{ .GroupLabels.alertname }}:{{ .CommonLabels.component }}",
  "payload": {
    "summary": "{{ .CommonAnnotations.summary }}",
    "severity": "{{ if eq .CommonLabels.severity \"critical\" }}critical{{ else }}warning{{ end }}",
    "source": "Prometheus AlertManager",
    "custom_details": {
      "component": "{{ .CommonLabels.component }}",
      "instance": "{{ (index .Alerts 0).Labels.instance }}",
      "description": "{{ .CommonAnnotations.description }}",
      "runbook_url": "{{ .CommonAnnotations.runbook }}",
      "dashboard_url": "https://grafana.internal.example.com/d/{{ .CommonLabels.dashboard }}"
    }
  }
}
```

---

## 4. 群聊通知（多个接收者）

### 路由配置

```yaml
# alertmanager.yml
route:
  receiver: 'default'
  routes:
    # Critical 告警立即通知所有渠道
    - match:
        severity: critical
      receiver: 'critical-all'
      continue: true
      group_wait: 10s
      repeat_interval: 1h

    # Warning 告警仅发送到 Slack
    - match:
        severity: warning
      receiver: 'slack'
      group_wait: 5m
      repeat_interval: 6h

receivers:
  - name: 'critical-all'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/CRITICAL'
        channel: '#nova-critical'
    email_configs:
      - to: 'oncall@example.com'
    pagerduty_configs:
      - service_key: '${PAGERDUTY_SERVICE_KEY}'
```

---

## 5. 通知去重策略

### 问题
相同告警重复触发导致噪音过多。

### 解决方案

```yaml
# alertmanager.yml
global:
  group_by: ['alertname', 'cluster', 'component']

route:
  # 等待 30 秒，聚合相同告警
  group_wait: 30s

  # 再次发送已聚合告警的间隔
  group_interval: 5m

  # 已解决告警的重复间隔
  repeat_interval: 6h
```

### 静音规则示例

```yaml
# 静音维护窗口期间的告警
- matchers:
    - name: component
      value: "database"
  start_time: "2025-10-21T10:00:00Z"
  end_time: "2025-10-21T12:00:00Z"
  created_by: "oncall@example.com"
  comment: "Database maintenance window"
```

---

## 6. 告警链接参考

### Grafana 仪表板链接
```
https://grafana.internal.example.com/d/{{ .CommonLabels.dashboard }}
?from={{ (now.Add -1h).Unix }}000&to={{ now.Unix }}000
```

### AlertManager UI 链接
```
https://alertmanager.internal.example.com/#/alerts
?filter={{ .GroupLabels.alertname }}
```

### Runbook Wiki
```
https://wiki.internal.example.com/runbooks/{{ .GroupLabels.alertname }}
```

---

## 7. 变量引用

| 变量 | 说明 |
|------|------|
| `{{ .Status }}` | firing / resolved |
| `{{ .GroupLabels.alertname }}` | 告警名称 |
| `{{ .CommonLabels.severity }}` | critical / warning / info |
| `{{ .CommonLabels.component }}` | 组件名称 |
| `{{ (index .Alerts 0).Labels.instance }}` | 实例标识 |
| `{{ .CommonAnnotations.summary }}` | 概要 |
| `{{ .CommonAnnotations.description }}` | 详细描述 |
| `{{ .Alerts.Firing \| len }}` | 激活告警数 |
| `{{ now }}` | 当前时间 |

---

## 8. 最佳实践

1. **清晰的摘要**: 通知摘要应在 2-3 句话内说明问题
2. **可操作的建议**: 每个告警应包含具体的修复步骤
3. **快速升级**: Critical 告警应在 10 秒内通知（不要等待 group_wait）
4. **避免告警疲劳**: 使用 repeat_interval 防止重复通知
5. **链接指向**: 包含仪表板、Runbook、日志查询器链接

---

## 9. 测试通知

使用 `amtool` 测试:

```bash
# 测试 Slack 通知
amtool config routes

# 创建测试告警
amtool alert add test_alert alertname=TestAlert severity=warning

# 查看告警状态
amtool alert list
```

---

**最后更新**: 2025-10-20
**维护者**: Platform Team
**相关文档**: [Prometheus 告警规则](./system-alerts.yml)
