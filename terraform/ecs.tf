# ============================================
# ECS Cluster
# ============================================

resource "aws_ecs_cluster" "main" {
  name = "nova-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "nova-${var.environment}"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ============================================
# CloudWatch Log Groups
# ============================================

resource "aws_cloudwatch_log_group" "services" {
  for_each = toset(var.services)

  name              = "/ecs/nova-${var.environment}/${each.key}"
  retention_in_days = 7

  tags = {
    Service = each.key
  }
}

# ============================================
# ECS Task Definitions
# ============================================

resource "aws_ecs_task_definition" "services" {
  for_each = toset(var.services)

  family                   = "nova-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "nova-${each.key}"
      image     = "${aws_ecr_repository.services[each.key].repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
          name          = "http"
        },
        {
          containerPort = tonumber(split("-", each.key)[0] == "auth" ? 50051 :
                                   split("-", each.key)[0] == "user" ? 50052 :
                                   split("-", each.key)[0] == "content" ? 50053 :
                                   split("-", each.key)[0] == "feed" ? 50054 :
                                   split("-", each.key)[0] == "media" ? 50055 :
                                   split("-", each.key)[0] == "messaging" ? 50056 :
                                   split("-", each.key)[0] == "search" ? 50057 :
                                   split("-", each.key)[0] == "streaming" ? 50058 :
                                   split("-", each.key)[0] == "notification" ? 50059 :
                                   split("-", each.key)[0] == "cdn" ? 50060 : 50061)
          protocol      = "tcp"
          name          = "grpc"
        }
      ]

      environment = [
        {
          name  = "SERVICE_NAME"
          value = each.key
        },
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "HTTP_PORT"
          value = "8080"
        },
        {
          name  = "GRPC_PORT"
          value = tostring(tonumber(split("-", each.key)[0] == "auth" ? 50051 :
                                     split("-", each.key)[0] == "user" ? 50052 :
                                     split("-", each.key)[0] == "content" ? 50053 :
                                     split("-", each.key)[0] == "feed" ? 50054 :
                                     split("-", each.key)[0] == "media" ? 50055 :
                                     split("-", each.key)[0] == "messaging" ? 50056 :
                                     split("-", each.key)[0] == "search" ? 50057 :
                                     split("-", each.key)[0] == "streaming" ? 50058 :
                                     split("-", each.key)[0] == "notification" ? 50059 :
                                     split("-", each.key)[0] == "cdn" ? 50060 : 50061))
        },
        {
          name  = "DATABASE_URL"
          value = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.main.endpoint}/${var.db_name}"
        },
        {
          name  = "REDIS_URL"
          value = "redis://${aws_elasticache_cluster.main.cache_nodes[0].address}:${aws_elasticache_cluster.main.port}"
        },
        {
          name  = "LOG_LEVEL"
          value = var.environment == "production" ? "info" : "debug"
        },
        {
          name  = "RUST_BACKTRACE"
          value = var.environment == "production" ? "0" : "1"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Service = each.key
  }
}

# ============================================
# ECS Services
# ============================================

resource "aws_ecs_service" "services" {
  for_each = toset(var.services)

  name            = "nova-${each.key}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.services[each.key].arn
  desired_count   = var.ecs_task_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.services[each.key].arn
    container_name   = "nova-${each.key}"
    container_port   = 8080
  }

  # Deployment configuration for ECS service
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Enable service discovery for inter-service gRPC communication
  service_registries {
    registry_arn = aws_service_discovery_service.services[each.key].arn
  }

  depends_on = [
    aws_lb_listener.https,
    aws_iam_role_policy.ecs_task_execution_ecr
  ]

  tags = {
    Service = each.key
  }
}

# ============================================
# Service Discovery (for gRPC inter-service communication)
# ============================================

resource "aws_service_discovery_private_dns_namespace" "main" {
  name = "nova-${var.environment}.local"
  vpc  = aws_vpc.main.id

  tags = {
    Name = "nova-${var.environment}-service-discovery"
  }
}

resource "aws_service_discovery_service" "services" {
  for_each = toset(var.services)

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = {
    Service = each.key
  }
}

# ============================================
# Auto Scaling (for production)
# ============================================

resource "aws_appautoscaling_target" "services" {
  for_each = var.environment == "production" ? toset(var.services) : toset([])

  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.services[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "services_cpu" {
  for_each = var.environment == "production" ? toset(var.services) : toset([])

  name               = "nova-${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

resource "aws_appautoscaling_policy" "services_memory" {
  for_each = var.environment == "production" ? toset(var.services) : toset([])

  name               = "nova-${each.key}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 70.0
  }
}
