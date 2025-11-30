# VPC Network
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC for Nova ${var.environment}"

  delete_default_routes_on_create = false
}

# Primary Subnet (for nodes and services)
resource "google_compute_subnetwork" "primary" {
  name          = "${var.vpc_name}-primary"
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
  region        = var.gcp_region
  description   = "Primary subnet for ${var.environment}"

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Secondary IP range for pods
resource "google_compute_subnetwork_secondary_range" "pods" {
  name          = "${var.vpc_name}-pods"
  ip_cidr_range = "10.4.0.0/14"
  subnetwork    = google_compute_subnetwork.primary.name
}

# Secondary IP range for services
resource "google_compute_subnetwork_secondary_range" "services" {
  name          = "${var.vpc_name}-services"
  ip_cidr_range = "10.0.0.0/20"
  subnetwork    = google_compute_subnetwork.primary.name
}

# Cloud Router (for Cloud NAT)
resource "google_compute_router" "router" {
  name    = "${var.vpc_name}-router"
  region  = var.gcp_region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  name                               = "${var.vpc_name}-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  enable_endpoint_independent_mapping = false
  min_ports_per_vm = 2048

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rules
# Allow internal communication
resource "google_compute_firewall" "internal" {
  name    = "${var.vpc_name}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_cidr]
}

# Allow SSH from anywhere (restrictive for production)
resource "google_compute_firewall" "ssh" {
  name    = "${var.vpc_name}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]  # Should be restricted in production
}

# Allow health checks
resource "google_compute_firewall" "health_checks" {
  name    = "${var.vpc_name}-allow-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }

  source_ranges = [
    "35.191.0.0/16",     # GCP health checks
    "130.211.0.0/22",    # GCP health checks
  ]
}

# Outputs
output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.vpc.id
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "subnet_id" {
  description = "Primary subnet ID"
  value       = google_compute_subnetwork.primary.id
}

output "subnet_name" {
  description = "Primary subnet name"
  value       = google_compute_subnetwork.primary.name
}

output "pods_secondary_range" {
  description = "Pods secondary IP range"
  value       = google_compute_subnetwork_secondary_range.pods.ip_cidr_range
}

output "services_secondary_range" {
  description = "Services secondary IP range"
  value       = google_compute_subnetwork_secondary_range.services.ip_cidr_range
}
