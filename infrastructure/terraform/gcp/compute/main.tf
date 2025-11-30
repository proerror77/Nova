# GKE Cluster
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.gcp_region

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_name
  subnetwork = var.subnet_name

  # VPC-native cluster
  networking_mode = "VPC_NATIVE"

  # IP ranges for pods and services (secondary ranges)
  cluster_secondary_range_name  = "pods"
  services_secondary_range_name = "services"

  # Kubernetes version
  min_master_version = var.kubernetes_version
  release_channel {
    channel = "REGULAR"
  }

  # Security
  enable_shielded_nodes = true
  enable_network_policy = true
  network_policy {
    enabled = true
  }
  enable_intra_node_visibility = true

  # Workload Identity
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  # Logging and Monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Enable GKE Backup (optional)
  addons_config {
    backup_restore_config {
      enabled = false  # Enable for production
    }
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  # IP allocation policy
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  # Cost optimization
  enable_cost_allocation = true

  labels = merge(
    {
      environment = var.environment
      cluster     = var.cluster_name
    },
    var.tags
  )

  depends_on = [
    # Ensure network and subnets are created first
  ]
}

# On-Demand Node Pool (base, stable workload)
resource "google_container_node_pool" "on_demand" {
  name       = "${var.cluster_name}-on-demand"
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = var.on_demand_initial_node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = var.on_demand_min_node_count
    max_node_count = var.on_demand_max_node_count
  }

  node_config {
    preemptible  = false
    machine_type = var.on_demand_machine_type
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      pool_type   = "on-demand"
      environment = var.environment
    }

    tags = ["nova-${var.environment}", "gke-node"]

    # Node taints (optional: for workload separation)
    taint {
      key    = "workload-type"
      value  = "system"
      effect = "NoExecute"
    }

    # Shielded Instance
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

# Spot Node Pool (burstable workload, cost optimization)
resource "google_container_node_pool" "spot" {
  name       = "${var.cluster_name}-spot"
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = var.spot_initial_node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = var.spot_min_node_count
    max_node_count = var.spot_max_node_count
  }

  node_config {
    preemptible  = true  # Spot nodes
    machine_type = var.spot_machine_type
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      pool_type   = "spot"
      environment = var.environment
    }

    tags = ["nova-${var.environment}", "gke-spot"]

    # Taint to prevent critical workloads
    taint {
      key    = "workload-type"
      value  = "batch"
      effect = "NoExecute"
    }
  }
}

# Outputs
output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "gke_network_name" {
  description = "GKE network name"
  value       = google_container_cluster.primary.network
}

output "gke_subnetwork_name" {
  description = "GKE subnetwork name"
  value       = google_container_cluster.primary.subnetwork
}
