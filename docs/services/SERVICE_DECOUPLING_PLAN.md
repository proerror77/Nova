# 微服务解耦方案

## 问题总结

当前 4 个服务存在直接的服务间依赖，违反微服务独立性原则：

1. **feed-service** → content-service
2. **media-service** → content-service
3. **messaging-service** → identity-service
4. **realtime-chat-service** → identity-service + messaging-service

## 解耦方案

### 方案 1: 事件驱动架构 (推荐) ⭐

**原理**: 使用 Kafka 事件总线替代直接调用

#### 1.1 feed-service 解耦

**当前**:
```
feed-service --gRPC--> content-service.GetPost()
```

**改为**:
```
content-service 发布事件:
  Topic: content-events
  Event: PostCreated, PostUpdated, PostDeleted

feed-service 订阅:
  Topic: content-events
  消费事件并更新本地缓存/数据库
```

**实现步骤**:
1. content-service 在创建/更新/删除内容时发布 Kafka 事件
2. feed-service 启动时订阅 content-events topic
3. feed-service 维护本地内容副本（最终一致性）
4. 移除 feed-service 的 `wait-for-content-service` init container

**优点**:
- ✅ 完全解耦，content-service 故障不影响 feed-service
- ✅ 支持多个消费者（未来其他服务也能订阅）
- ✅ 自然支持数据同步

**缺点**:
- ❌ 最终一致性（可能有几秒延迟）

---

#### 1.2 media-service 解耦

**当前**:
```
media-service --gRPC--> content-service.AttachMedia()
```

**改为**:
```
media-service 发布事件:
  Topic: media-events
  Event: MediaUploaded { post_id, media_url, type }

content-service 订阅:
  Topic: media-events
  自动关联媒体到 post
```

**实现步骤**:
1. media-service 上传完成后发布 MediaUploaded 事件
2. content-service 订阅 media-events topic
3. content-service 自动处理媒体关联
4. 移除 media-service 的 `wait-for-content-service` init container

---

#### 1.3 messaging-service 解耦

**当前**:
```
messaging-service --gRPC--> identity-service.VerifyUser()
```

**改为方案 A - JWT Token**:
```
客户端请求:
  1. 先调用 identity-service.Login() 获取 JWT
  2. 携带 JWT 调用 messaging-service

messaging-service:
  验证 JWT 签名（无需调用 identity-service）
  从 JWT 解析 user_id, roles 等
```

**或者方案 B - 共享 Redis 缓存**:
```
identity-service:
  用户登录后写入 Redis: user:{id} -> {user_info}

messaging-service:
  从 Redis 读取用户信息（不调用 identity-service）
```

**推荐**: 方案 A (JWT)，符合 OAuth2/OIDC 标准

---

#### 1.4 realtime-chat-service 解耦

**当前**:
```
realtime-chat-service --> identity-service (认证)
                      --> messaging-service (消息)
```

**改为**:
```
1. 认证使用 JWT (同 1.3)
2. 消息通过 Kafka:
   - 订阅 messaging-events topic
   - 实时推送给 WebSocket 客户端
```

---

### 方案 2: API Gateway 模式

**原理**: 所有服务间调用通过 graphql-gateway 路由

```
feed-service --HTTP--> graphql-gateway --gRPC--> content-service
```

**优点**:
- ✅ 统一认证、限流、监控
- ✅ 服务发现由网关处理
- ✅ 容易切换后端实现

**缺点**:
- ❌ 网关成为单点故障
- ❌ 增加一跳延迟
- ❌ 没有真正解耦（只是间接依赖）

**不推荐**: 仍然是同步调用，未解决根本问题

---

### 方案 3: 数据库共享 (仅限读取)

**原理**: 通过只读副本共享数据

```
content-service --> postgres (主)
                       ↓ 复制
feed-service ------> postgres-replica (从，只读)
```

**优点**:
- ✅ 读取性能高
- ✅ 数据一致性强

**缺点**:
- ❌ 违反数据库隔离原则
- ❌ schema 变更影响多个服务
- ❌ 无法水平扩展

**不推荐**: 除非数据量极大且读多写少

---

## 推荐实施顺序

### Phase 1: 认证解耦 (最简单)
1. ✅ 实施 JWT 认证
2. ✅ messaging-service 使用 JWT
3. ✅ realtime-chat-service 使用 JWT
4. ✅ 移除 `wait-for-identity-service` init container

**预期效果**: messaging-service 和 realtime-chat-service 变为 Layer 1

---

### Phase 2: 内容服务解耦 (中等难度)
1. ✅ content-service 发布 content-events
2. ✅ feed-service 订阅 content-events
3. ✅ feed-service 维护本地内容索引
4. ✅ 移除 `wait-for-content-service` init container

**预期效果**: feed-service 变为 Layer 1

---

### Phase 3: 媒体服务解耦 (中等难度)
1. ✅ media-service 发布 media-events
2. ✅ content-service 订阅 media-events
3. ✅ 移除 media-service 的 content-service 依赖

**预期效果**: media-service 变为 Layer 1

---

## 最终目标架构

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 0: 基础设施                                            │
│ postgres, redis, kafka, elasticsearch, clickhouse           │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: 完全独立的业务服务 (只依赖基础设施)                  │
│                                                             │
│ ✅ identity-service     ✅ content-service                  │
│ ✅ media-service        ✅ feed-service                     │
│ ✅ messaging-service    ✅ realtime-chat-service            │
│ ✅ search-service       ✅ analytics-service                │
│ ✅ notification-service ✅ ranking-service                  │
│ ✅ trust-safety-service ✅ social-service                   │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: API Gateway (可选)                                 │
│ graphql-gateway, api-gateway/Ingress                        │
└─────────────────────────────────────────────────────────────┘
```

**关键特性**:
- 🎯 每个服务可以独立部署、扩展、失败
- 🎯 通过 Kafka 事件总线通信
- 🎯 通过 JWT 进行认证
- 🎯 无服务间直接调用
- 🎯 最终一致性模型

---

## 实施检查清单

### Phase 1: JWT 认证
- [ ] identity-service 支持签发 JWT
- [ ] messaging-service 验证 JWT
- [ ] realtime-chat-service 验证 JWT
- [ ] 更新 service-init-containers-patch.yaml
- [ ] 测试认证流程

### Phase 2: 内容事件
- [ ] content-service 发布 PostCreated 事件
- [ ] content-service 发布 PostUpdated 事件
- [ ] content-service 发布 PostDeleted 事件
- [ ] feed-service 订阅 content-events
- [ ] feed-service 建立本地索引
- [ ] 更新 service-init-containers-patch.yaml
- [ ] 测试事件流

### Phase 3: 媒体事件
- [ ] media-service 发布 MediaUploaded 事件
- [ ] content-service 订阅 media-events
- [ ] 更新 service-init-containers-patch.yaml
- [ ] 测试媒体上传流程

---

## 性能对比

| 指标 | 当前架构 (同步调用) | 目标架构 (事件驱动) |
|------|---------------------|---------------------|
| 服务间延迟 | 10-50ms | 100-500ms (异步) |
| 可用性 | 链式依赖，任一服务故障影响全链路 | 独立，一个服务故障不影响其他 |
| 吞吐量 | 受最慢服务限制 | 各服务独立，可分别扩展 |
| 一致性 | 强一致性 | 最终一致性 |
| 复杂度 | 简单 | 中等（需要事件管理） |

---

## 注意事项

1. **最终一致性**: 事件驱动架构会有延迟（通常 < 1秒），需要 UI 做乐观更新
2. **事件顺序**: Kafka 保证同一分区内有序，需要合理设置 partition key
3. **重复消费**: 实现幂等性，同一事件多次消费应产生相同结果
4. **事件版本**: 使用 schema registry (Avro/Protobuf) 管理事件格式变更
5. **监控**: 增加 Kafka lag 监控，确保消费者不落后

---

## 参考资料

- [Event-Driven Microservices](https://www.confluent.io/blog/event-driven-microservices-with-apache-kafka/)
- [JWT Best Practices](https://tools.ietf.org/html/rfc8725)
- [Kafka Patterns](https://www.confluent.io/blog/microservices-apache-kafka-event-driven-architecture/)
