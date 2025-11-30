# Cloud SQL Instance (PostgreSQL)
resource "google_sql_database_instance" "primary" {
  name             = "${var.database_instance_name}-${var.environment}"
  database_version = var.postgres_version
  region           = var.gcp_region
  deletion_protection = var.environment == "production" ? true : false

  settings {
    tier              = var.database_machine_type
    availability_type = var.environment == "production" ? "REGIONAL" : "ZONAL"
    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      location                       = var.gcp_region
      point_in_time_recovery_enabled = var.environment == "production" ? true : false
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      require_ssl     = true
    }

    database_flags {
      name  = "max_connections"
      value = "200"
    }

    database_flags {
      name  = "log_statement"
      value = "all"
    }

    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    user_labels = merge(
      {
        environment = var.environment
        service     = "database"
      },
      var.tags
    )
  }

  depends_on = [var.private_vpc_connection]
}

# Cloud SQL Database
resource "google_sql_database" "main" {
  name     = var.database_name
  instance = google_sql_database_instance.primary.name

  depends_on = [google_sql_database_instance.primary]
}

# Cloud SQL User (Password-based)
resource "random_password" "db_password" {
  length  = 32
  special = true
}

resource "google_sql_user" "db_user" {
  name     = var.database_user
  instance = google_sql_database_instance.primary.name
  password = random_password.db_password.result
}

# Store DB password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.database_instance_name}-${var.environment}-password"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Store connection string in Secret Manager
resource "google_secret_manager_secret" "db_connection_string" {
  secret_id = "${var.database_instance_name}-${var.environment}-connection-string"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_connection_string" {
  secret = google_secret_manager_secret.db_connection_string.id
  secret_data = format(
    "postgresql://%s:%s@%s:5432/%s?sslmode=require",
    var.database_user,
    random_password.db_password.result,
    google_sql_database_instance.primary.private_ip_address,
    var.database_name
  )
}

# Cloud SQL Proxy Service Account (for K8s)
resource "google_service_account" "cloudsql_proxy" {
  account_id   = "cloudsql-proxy-${var.environment}"
  display_name = "Cloud SQL Proxy for ${var.environment}"
  description  = "Service account for Cloud SQL proxy from Kubernetes"
}

# Grant Cloud SQL Client role
resource "google_project_iam_member" "cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloudsql_proxy.email}"
}

# Memorystore Redis Instance
resource "google_redis_instance" "cache" {
  name           = "${var.redis_instance_name}-${var.environment}"
  memory_size_gb = var.redis_size_gb
  tier           = var.redis_tier
  region         = var.gcp_region

  version = var.redis_version

  # Networking
  connect_mode = "PRIVATE_SERVICE_ACCESS"
  authorized_network = var.network_id

  # Persistence
  persistence_config {
    persistence_type = "RDB"
    rdb_snapshot_period = "TWELVE_HOURS"
  }

  # Backup configuration
  backup_configuration {
    start_time = "02:00"
  }

  # Maintenance
  maintenance_policy {
    weekly_maintenance_window {
      day        = "SUNDAY"
      start_time = "00:00"
    }
  }

  display_name = "Redis Cache for ${var.environment}"
  labels = merge(
    {
      environment = var.environment
      service     = "cache"
    },
    var.tags
  )

  depends_on = [var.private_vpc_connection]
}

# Store Redis connection info in Secret Manager
resource "google_secret_manager_secret" "redis_connection" {
  secret_id = "${var.redis_instance_name}-${var.environment}-connection"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "redis_connection" {
  secret      = google_secret_manager_secret.redis_connection.id
  secret_data = format("redis://%s:6379/0", google_redis_instance.cache.host)
}

# Redis Service Account (for K8s)
resource "google_service_account" "redis_access" {
  account_id   = "redis-access-${var.environment}"
  display_name = "Redis Access for ${var.environment}"
  description  = "Service account for accessing Memorystore Redis from Kubernetes"
}

# Grant Redis Client role
resource "google_project_iam_member" "redis_client" {
  project = var.gcp_project_id
  role    = "roles/redis.editor"
  member  = "serviceAccount:${google_service_account.redis_access.email}"
}

# Outputs
output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.primary.name
}

output "cloud_sql_private_ip" {
  description = "Cloud SQL private IP address"
  value       = google_sql_database_instance.primary.private_ip_address
  sensitive   = true
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (project:region:instance)"
  value       = google_sql_database_instance.primary.connection_name
  sensitive   = true
}

output "redis_host" {
  description = "Memorystore Redis host IP"
  value       = google_redis_instance.cache.host
  sensitive   = true
}

output "redis_port" {
  description = "Memorystore Redis port"
  value       = google_redis_instance.cache.port
}

output "cloudsql_proxy_service_account" {
  description = "Cloud SQL Proxy service account email"
  value       = google_service_account.cloudsql_proxy.email
}

output "redis_access_service_account" {
  description = "Redis access service account email"
  value       = google_service_account.redis_access.email
}

output "db_password_secret" {
  description = "Secret Manager secret ID for DB password"
  value       = google_secret_manager_secret.db_password.id
}

output "db_connection_string_secret" {
  description = "Secret Manager secret ID for DB connection string"
  value       = google_secret_manager_secret.db_connection_string.id
}

output "redis_connection_secret" {
  description = "Secret Manager secret ID for Redis connection"
  value       = google_secret_manager_secret.redis_connection.id
}
