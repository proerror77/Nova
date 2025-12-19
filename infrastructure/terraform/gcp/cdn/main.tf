# =============================================================================
# Cloud CDN Configuration for Media Service
# =============================================================================
# This module creates:
# - GCS bucket for media storage (publicly readable)
# - Cloud CDN with Global HTTP(S) Load Balancer
# - Backend bucket pointing to GCS
# =============================================================================

# -----------------------------------------------------------------------------
# Media Storage Bucket
# -----------------------------------------------------------------------------
resource "google_storage_bucket" "media" {
  name          = var.media_bucket_name
  location      = var.gcp_region
  force_destroy = false

  # Disable uniform bucket-level access for public read
  uniform_bucket_level_access = false

  versioning {
    enabled = false  # Media files don't need versioning
  }

  # CORS configuration for web/app access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Content-Length", "Content-Range", "Cache-Control"]
    max_age_seconds = 3600
  }

  # Lifecycle rules for cost optimization
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 90  # Move to NEARLINE after 90 days
    }
  }

  labels = merge(
    {
      environment = var.environment
      purpose     = "media-storage"
      service     = "media-service"
    },
    var.tags
  )
}

# Make bucket publicly readable
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Service account for media uploads
resource "google_service_account" "media_uploader" {
  account_id   = "media-uploader-${var.environment}"
  display_name = "Media Uploader for ${var.environment}"
  description  = "Service account for uploading media to GCS"
}

# Grant storage admin for uploads
resource "google_storage_bucket_iam_member" "media_uploader" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.media_uploader.email}"
}

# -----------------------------------------------------------------------------
# Cloud CDN with Global HTTP(S) Load Balancer
# -----------------------------------------------------------------------------

# Reserve a global static IP
resource "google_compute_global_address" "cdn_ip" {
  name        = "media-cdn-ip-${var.environment}"
  description = "Static IP for Media CDN"
}

# Backend bucket (connects GCS to Load Balancer)
resource "google_compute_backend_bucket" "media_cdn" {
  name        = "media-cdn-backend-${var.environment}"
  description = "Backend bucket for media CDN"
  bucket_name = google_storage_bucket.media.name

  enable_cdn  = true

  cdn_policy {
    cache_mode        = "CACHE_ALL_STATIC"
    default_ttl       = 3600      # 1 hour default cache
    max_ttl           = 86400     # 24 hours max cache
    client_ttl        = 3600      # 1 hour client cache

    negative_caching  = true
    negative_caching_policy {
      code = 404
      ttl  = 60  # Cache 404s for 1 minute
    }

    serve_while_stale = 86400  # Serve stale content for up to 24 hours

    # Signed URL support (optional, for private content)
    signed_url_cache_max_age_sec = 3600
  }
}

# URL Map (routing rules)
resource "google_compute_url_map" "media_cdn" {
  name            = "media-cdn-urlmap-${var.environment}"
  description     = "URL map for media CDN"
  default_service = google_compute_backend_bucket.media_cdn.id
}

# HTTP proxy (for redirect to HTTPS)
resource "google_compute_target_http_proxy" "media_cdn_http" {
  name    = "media-cdn-http-proxy-${var.environment}"
  url_map = google_compute_url_map.media_cdn_redirect.id
}

# URL Map for HTTP -> HTTPS redirect
resource "google_compute_url_map" "media_cdn_redirect" {
  name = "media-cdn-redirect-${var.environment}"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# HTTPS proxy
resource "google_compute_target_https_proxy" "media_cdn" {
  name             = "media-cdn-https-proxy-${var.environment}"
  url_map          = google_compute_url_map.media_cdn.id
  ssl_certificates = [google_compute_managed_ssl_certificate.media_cdn.id]
}

# Managed SSL Certificate
resource "google_compute_managed_ssl_certificate" "media_cdn" {
  name = "media-cdn-cert-${var.environment}"

  managed {
    domains = [var.cdn_domain]
  }
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "media_cdn_https" {
  name                  = "media-cdn-https-rule-${var.environment}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.media_cdn.id
  ip_address            = google_compute_global_address.cdn_ip.id
}

# Global forwarding rule for HTTP (redirect)
resource "google_compute_global_forwarding_rule" "media_cdn_http" {
  name                  = "media-cdn-http-rule-${var.environment}"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.media_cdn_http.id
  ip_address            = google_compute_global_address.cdn_ip.id
}

# -----------------------------------------------------------------------------
# DNS Record (if using Cloud DNS)
# -----------------------------------------------------------------------------
resource "google_dns_record_set" "media_cdn" {
  count        = var.create_dns_record ? 1 : 0
  name         = "${var.cdn_domain}."
  type         = "A"
  ttl          = 300
  managed_zone = var.dns_zone_name
  rrdatas      = [google_compute_global_address.cdn_ip.address]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------
output "cdn_ip_address" {
  description = "CDN static IP address"
  value       = google_compute_global_address.cdn_ip.address
}

output "cdn_url" {
  description = "CDN URL for media access"
  value       = "https://${var.cdn_domain}"
}

output "media_bucket_name" {
  description = "Media storage bucket name"
  value       = google_storage_bucket.media.name
}

output "media_bucket_url" {
  description = "Direct GCS URL (for fallback)"
  value       = "https://storage.googleapis.com/${google_storage_bucket.media.name}"
}

output "media_uploader_service_account" {
  description = "Service account email for media uploads"
  value       = google_service_account.media_uploader.email
}
