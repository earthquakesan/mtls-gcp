# 4. GKE Autopilot Cluster (Existing)
data "google_container_cluster" "gke_cluster" {
  count    = var.environment == "dev" ? 1 : 0
  name     = var.cluster_name
  location = var.region
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
resource "google_compute_health_check" "hc" {
  count  = var.environment == "dev" ? 1 : 0
  name   = "mtls-hc"

  http_health_check {
    port_specification = "USE_SERVING_PORT"
    request_path       = "/healthz"
  }
}

resource "google_compute_backend_service" "backend" {
  count                 = var.environment == "dev" ? 1 : 0
  name                  = "mtls-backend"
  protocol              = "HTTP"
  load_balancing_scheme = "INTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.hc.0.id]

  custom_request_headers = ["X-Client-Cert-Fingerprint:{client_cert_sha256_fingerprint}"]

  # Backends will be NEGs created by GKE. 
  # Since they are managed by GKE, we construct the IDs manually.
  dynamic "backend" {
    for_each = flatten(data.google_container_cluster.gke_cluster[*].node_locations)
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

# 8. URL Map & Target HTTPS Proxy
resource "google_compute_url_map" "url_map" {
  count           = var.environment == "dev" ? 1 : 0
  name            = "mtls-url-map"
  default_service = google_compute_backend_service.backend.0.id
}

resource "google_compute_target_https_proxy" "target_proxy" {
  count             = var.environment == "dev" ? 1 : 0
  name              = "mtls-target-proxy"
  url_map           = google_compute_url_map.url_map.0.id
  certificate_manager_certificates = [google_certificate_manager_certificate.server_cert.0.id]
  server_tls_policy = google_network_security_server_tls_policy.server_tls_policy.0.id
}

# 9. Forwarding Rule
resource "google_compute_global_forwarding_rule" "forwarding_rule" {
  count                 = var.environment == "dev" ? 1 : 0
  name                  = "mtls-forwarding-rule"
  load_balancing_scheme = "INTERNAL_MANAGED"
  network               = google_compute_network.vpc.0.id
  ip_address            = google_compute_address.lb_ip.0.id
  port_range            = "443"
  target                = google_compute_target_https_proxy.target_proxy.0.id
}
