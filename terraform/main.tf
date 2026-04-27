# 4. GKE Autopilot Cluster
resource "google_container_cluster" "gke_cluster" {
  count            = var.environment == "dev" ? 1 : 0
  name             = var.cluster_name
  location         = var.region
  network          = google_compute_network.vpc.0.id
  subnetwork       = google_compute_subnetwork.lb_subnet.0.id
  enable_autopilot = true

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  depends_on = [google_project_service.services]
}

# 5. Static Internal IP
resource "google_compute_address" "lb_ip" {
  count        = var.environment == "dev" ? 1 : 0
  name         = "mtls-lb-static-ip"
  region       = var.region
  subnetwork   = google_compute_subnetwork.lb_subnet.0.id
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  address      = "10.0.0.10"
}

# 6. Health Check & Backend Service
resource "google_compute_region_health_check" "hc" {
  count  = var.environment == "dev" ? 1 : 0
  name   = "mtls-hc"
  region = var.region

  http_health_check {
    port_specification = "USE_SERVING_PORT"
    request_path       = "/healthz"
  }
}

resource "google_compute_region_backend_service" "backend" {
  count                 = var.environment == "dev" ? 1 : 0
  name                  = "mtls-backend"
  region                = var.region
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [google_compute_region_health_check.hc.0.id]

  dynamic "backend" {
    for_each = flatten(google_container_cluster.gke_cluster[*].node_locations)
    content {
      group           = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/zones/${backend.value}/networkEndpointGroups/nginx-neg"
      balancing_mode  = "RATE"
      max_rate_per_endpoint = 5
    }
  }

  lifecycle {
    ignore_changes = []
  }
}

# 7. mTLS Configuration
resource "google_certificate_manager_certificate" "server_cert" {
  count    = var.environment == "dev" ? 1 : 0
  name     = "mtls-server-cert"
  location = "global"

  self_managed {
    pem_certificate = file("${path.module}/../certs/server.pem")
    pem_private_key = file("${path.module}/../certs/server.key")
  }
}

resource "google_certificate_manager_trust_config" "trust_config" {
  count    = var.environment == "dev" ? 1 : 0
  name     = "mtls-trust-config"
  location = "global"

  trust_stores {
    trust_anchors {
      pem_certificate = file("${path.module}/../certs/root-ca.pem")
    }
  }
}

resource "google_network_security_server_tls_policy" "server_tls_policy" {
  count    = var.environment == "dev" ? 1 : 0
  name     = "mtls-server-tls-policy"
  location = "global"

  description = "mTLS policy for internal L7 LB"

  mtls_policy {
    client_validation_mode         = "REJECT_INVALID"
    client_validation_trust_config = "projects/${var.project_id}/locations/global/trustConfigs/${google_certificate_manager_trust_config.trust_config.0.name}"
  }
}

# 8. URL Map with mTLS fingerprint header (via headerAction)
resource "google_compute_region_url_map" "url_map" {
  count           = var.environment == "dev" ? 1 : 0
  name            = "mtls-url-map"
  region          = var.region
  default_service = google_compute_region_backend_service.backend.0.id

  path_matcher {
    name = "default-matcher"
    default_service = google_compute_region_backend_service.backend.0.id

    route_rules {
      priority = 0
      match_rules {
        prefix_match = "/"
      }
      route_action {
        weighted_backend_services {
          backend_service = google_compute_region_backend_service.backend.0.id
          weight          = 100
          header_action {
            request_headers_to_add {
              header_name  = "X-Client-Cert-Fingerprint"
              header_value = "{client_cert_sha256_fingerprint}"
              replace      = true
            }
          }
        }
      }
    }
  }
}

# 9. Target HTTPS Proxy
resource "google_compute_region_target_https_proxy" "target_proxy" {
  count             = var.environment == "dev" ? 1 : 0
  name              = "mtls-target-proxy"
  region            = var.region
  url_map           = google_compute_region_url_map.url_map.0.id
  certificate_manager_certificates = [google_certificate_manager_certificate.server_cert.0.id]
  server_tls_policy = google_network_security_server_tls_policy.server_tls_policy.0.id
}

# 10. Forwarding Rule
resource "google_compute_forwarding_rule" "forwarding_rule" {
  count                 = var.environment == "dev" ? 1 : 0
  name                  = "mtls-forwarding-rule"
  load_balancing_scheme = "INTERNAL_MANAGED"
  region                = var.region
  network               = google_compute_network.vpc.0.id
  subnetwork            = google_compute_subnetwork.lb_subnet.0.id
  ip_address            = google_compute_address.lb_ip.0.id
  port_range            = "443"
  target                = google_compute_region_target_https_proxy.target_proxy.0.id
}
