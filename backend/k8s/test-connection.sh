#!/bin/bash

echo "=== 测试 Redis 连接 ==="
kubectl run -it --rm redis-test --image=redis:7-alpine --restart=Never -n nova-redis -- redis-cli -h redis-service -p 6379 -a redis_password_change_me ping 2>&1 || echo "Redis 测试完成"

echo ""
echo "=== 测试 PostgreSQL 连接 ==="
kubectl run -it --rm psql-test --image=postgres:15-alpine --restart=Never -n nova-database -- psql -h postgres-primary -U postgres -d nova_auth -c "SELECT version();" 2>&1 || echo "PostgreSQL 测试完成"

echo ""
echo "=== 端口转发信息 ==="
echo "Redis:      kubectl port-forward svc/redis-service 6379:6379 -n nova-redis"
echo "PostgreSQL: kubectl port-forward svc/postgres-primary 5432:5432 -n nova-database"
