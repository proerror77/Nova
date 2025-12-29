# Profile / Social / Graph 事件契约与数据所有权矩阵

## 范围与原则
- 范围：identity-service（Profile）、social-service（互动）、graph-service（关系与图谱）
- 原则：单一写入者（single-writer）、事件驱动同步、读写分离（Neo4j 作为读优化）

## 数据所有权矩阵
| 领域 | 数据/实体 | 写入/唯一写入 | SoT 存储 | 读取/对外 | 备注 |
| --- | --- | --- | --- | --- | --- |
| Profile | users（username/display_name/bio/avatar/隐私/扩展字段） | identity-service | identity Postgres | GraphQL Gateway / identity gRPC | follower_count 不归 identity 维护 |
| Social | likes/comments/shares | social-service | social Postgres | GraphQL Gateway / social gRPC | 触发通知、排序等下游 |
| Social | post_counters/comment_count/share_count | social-service | social Postgres | feed/content | 计数为派生数据 |
| Graph | follows/blocks/mutes | graph-service | graph Postgres + Neo4j | GraphQL Gateway / graph gRPC | Dual-write，Postgres 为 SoT |
| Graph | 关系图特征（互关、推荐特征） | graph-service | Neo4j/缓存 | ranking/feed | 读优化/派生 |

## 事件契约概览
### 通用 Payload + Header（identity.events）
- Kafka Header：event_type（下游稳定路由）
- Payload：事件数据本体（identity-service 使用 outbox 发布）

### Outbox Envelope（social.events）
- 字段：id、aggregate_type、aggregate_id、event_type、payload、created_at
- 由 social-service transactional outbox 产生

## nova.identity.events（`KAFKA_IDENTITY_EVENTS_TOPIC`，默认 `nova.identity.events`）
| event_type | Producer | Payload 关键字段 | Consumers | 备注 |
| --- | --- | --- | --- | --- |
| identity.user.created | identity-service | user_id, email, username, created_at | graph-service | 建立本地 users |
| identity.user.profile_updated | identity-service | user_id, username, display_name, bio, avatar_url, is_verified, follower_count, updated_at | graph-service, search-service | follower_count 为派生值 |
| identity.user.deleted | identity-service | user_id, deleted_at, soft_delete, deleted_by | graph-service | 软删除本地 users |

## social.events（`${KAFKA_TOPIC_PREFIX}.social.events`，默认 `nova.social.events`）
| event_type | Producer | Payload 关键字段 | Consumers | 备注 |
| --- | --- | --- | --- | --- |
| social.follow.created | social-service (outbox) | follower_id, followee_id | graph-service | 创建关系边 |
| social.follow.deleted | social-service (outbox) | follower_id, followee_id | graph-service | 删除关系边 |

## 一致性与边界规则
- Profile 只允许 identity-service 写入；其他服务读或订阅事件，不做反向写回。
- 社交关系的最终权威在 graph-service（Postgres SoT + Neo4j 读优化）。
- social-service 负责互动与计数，graph-service 仅消费关系类事件。
- 新增事件时，优先扩展 event_type 与 payload，不复用既有事件语义。
